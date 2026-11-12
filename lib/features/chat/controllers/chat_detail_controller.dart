import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/storage/draft_store.dart';
import '../data/chat_repository.dart';
import '../models/chat_message.dart';
import '../utils/chat_emote_converter.dart';

class ChatDetailController extends ChangeNotifier {
  ChatDetailController({
    required this.repository,
    required this.draftStore,
    required this.userId,
    required this.currentUserName,
    required this.conversationId,
    required this.partnerName,
    this.partnerAvatarUrl,
  });

  final ChatRepository repository;
  final DraftStore draftStore;
  final String userId;
  final String currentUserName;
  final String conversationId;
  final String partnerName;
  final String? partnerAvatarUrl;

  List<ChatMessage> _messages = [];
  bool _isLoading = false;
  bool _isLoadingEarlier = false;
  bool _isPartnerTyping = false;
  String? _errorMessage;
  String? _after;
  bool _hasNext = false;
  String _draftText = '';

  Timer? _typingIndicatorTimer;
  Timer? _typingDebounceTimer;
  Timer? _draftDebounceTimer;

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isLoading => _isLoading;
  bool get isLoadingEarlier => _isLoadingEarlier;
  bool get isPartnerTyping => _isPartnerTyping;
  String? get errorMessage => _errorMessage;
  bool get hasNext => _hasNext;
  String get draftText => _draftText;

  String get _draftKey => 'chat_draft_$conversationId';

  Future<void> initialize() async {
    // 1. Phục hồi bản nháp (Draft) từ secure storage
    final draftData = await draftStore.read(userId: userId, name: _draftKey);
    if (draftData != null && draftData['text'] is String) {
      _draftText = draftData['text'] as String;
    }

    // 2. Cache-first: Đọc tin nhắn offline đã lưu trên máy
    final cached = await repository.loadCachedMessages(
      userId: userId,
      conversationId: conversationId,
    );
    if (cached != null && cached.isNotEmpty) {
      _messages = cached;
      notifyListeners();
    }

    // 3. Lấy tin nhắn mới nhất từ server
    await fetchFirstPage(showLoading: _messages.isEmpty);

    // 4. Lắng nghe Realtime qua WebSocket STOMP
    _setupRealtimeListeners();
  }

  void _setupRealtimeListeners() {
    final stomp = repository.stomp;
    if (stomp == null) return;
    stomp.connect();

    // Lắng nghe tin nhắn mới gửi đến
    stomp.subscribe('/user/queue/messages', (payload) {
      final convId = payload['conversation_id']?.toString();
      if (convId != conversationId) return;

      final incoming = ChatMessage.fromJson(payload);
      _handleIncomingMessage(incoming);
    });

    // Lắng nghe sự kiện typing từ đối phương
    stomp.subscribe('/topic/conv.$conversationId.typing', (payload) {
      final senderUserId = payload['user_id']?.toString();
      if (senderUserId == userId) return; // Bỏ qua sự kiện của chính mình

      final isTyping =
          payload['is_typing'] == true ||
          payload['is_typing']?.toString().toLowerCase() == 'true';

      _isPartnerTyping = isTyping;
      notifyListeners();

      _typingIndicatorTimer?.cancel();
      if (isTyping) {
        // Tự động ẩn trạng thái typing sau 3.5 giây nếu không nhận được event tiếp theo
        _typingIndicatorTimer = Timer(const Duration(milliseconds: 3500), () {
          _isPartnerTyping = false;
          notifyListeners();
        });
      }
    });

    // Lắng nghe sự kiện đã xem tin nhắn từ đối phương
    stomp.subscribe('/topic/conv.$conversationId.read', (payload) {
      final readerUserId =
          payload['user_id']?.toString() ?? payload['reader_id']?.toString();
      if (readerUserId == userId) return;

      final readMessageId = payload['message_id']?.toString();
      _handlePartnerReadEvent(readMessageId);
    });
  }

  void _handlePartnerReadEvent(String? readMessageId) {
    var updated = false;
    for (var i = 0; i < _messages.length; i++) {
      final m = _messages[i];
      if (m.isMine(userId) && !m.isRead) {
        _messages[i] = m.copyWith(isRead: true);
        updated = true;
      }
    }
    if (updated) {
      notifyListeners();
      repository.saveCachedMessages(
        userId: userId,
        conversationId: conversationId,
        messages: _messages,
      );
    }
  }

  void _markAllIncomingAsRead() {
    for (final msg in _messages) {
      if (!msg.isMine(userId) && msg.messageId.isNotEmpty) {
        repository.sendReadStatus(
          conversationId: conversationId,
          messageId: msg.messageId,
        );
      }
    }
  }

  void _handleIncomingMessage(ChatMessage message) {
    // Kiểm tra tin nhắn đã tồn tại chưa (tránh trùng theo messageId, clientMsgId hoặc nội dung tương ứng của chính mình)
    final existingIndex = _messages.indexWhere((m) {
      if (m.messageId.isNotEmpty && m.messageId == message.messageId) {
        return true;
      }
      if (m.clientMsgId.isNotEmpty && m.clientMsgId == message.clientMsgId) {
        return true;
      }
      if (message.isMine(userId) && m.isMine(userId)) {
        if (m.content == message.content &&
            message.createdAt.difference(m.createdAt).abs().inSeconds < 30) {
          return true;
        }
      }
      return false;
    });

    if (existingIndex != -1) {
      _messages[existingIndex] = message.copyWith(status: MessageStatus.sent);
    } else {
      _messages.insert(0, message);
    }
    notifyListeners();

    // Lưu cache 50 tin nhắn mới nhất
    repository.saveCachedMessages(
      userId: userId,
      conversationId: conversationId,
      messages: _messages,
    );

    // Gửi xác nhận đã đọc nếu tin nhắn do đối phương gửi
    if (!message.isMine(userId) && message.messageId.isNotEmpty) {
      repository.sendReadStatus(
        conversationId: conversationId,
        messageId: message.messageId,
      );
    }
  }

  Future<void> fetchFirstPage({bool showLoading = true}) async {
    if (showLoading) {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();
    }

    try {
      final response = await repository.fetchMessages(
        conversationId,
        limit: 20,
      );

      // Giữ lại các tin nhắn cục bộ đang gửi hoặc gửi thất bại chưa được server xác nhận
      final pendingOrFailed = _messages
          .where(
            (m) =>
                m.status == MessageStatus.sending ||
                m.status == MessageStatus.failed,
          )
          .toList();

      final serverIds = response.messages.map((m) => m.messageId).toSet();
      final clientMsgIds = response.messages.map((m) => m.clientMsgId).toSet();

      final unconfirmed = pendingOrFailed.where(
        (m) =>
            !serverIds.contains(m.messageId) &&
            !clientMsgIds.contains(m.clientMsgId),
      );

      _messages = [...unconfirmed, ...response.messages];
      _after = response.after;
      _hasNext = response.hasNext;
      _errorMessage = null;

      await repository.saveCachedMessages(
        userId: userId,
        conversationId: conversationId,
        messages: _messages,
      );
      _markAllIncomingAsRead();
    } on AppFailure catch (failure) {
      _errorMessage = failure.message;
    } catch (_) {
      _errorMessage = 'Không thể tải tin nhắn.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadEarlierMessages() async {
    if (_isLoadingEarlier || !_hasNext || _after == null) return;

    _isLoadingEarlier = true;
    notifyListeners();

    try {
      final response = await repository.fetchMessages(
        conversationId,
        after: _after,
        limit: 20,
      );

      final existingIds = _messages.map((e) => e.messageId).toSet();
      final olderMessages = response.messages.where(
        (e) => !existingIds.contains(e.messageId),
      );

      _messages = [..._messages, ...olderMessages];
      _after = response.after;
      _hasNext = response.hasNext;
    } catch (_) {
      // Giữ nguyên khi tải thêm bị lỗi
    } finally {
      _isLoadingEarlier = false;
      notifyListeners();
    }
  }

  // --- Quản lý bản nháp (Draft) ---

  void onTextChanged(String text) {
    _draftText = text;

    // 1. Lưu bản nháp an toàn có debounce 500ms
    _draftDebounceTimer?.cancel();
    _draftDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (_draftText.trim().isEmpty) {
        draftStore.remove(userId: userId, name: _draftKey);
      } else {
        draftStore.save(
          userId: userId,
          name: _draftKey,
          data: {'text': _draftText},
        );
      }
    });

    // 2. Phát sự kiện typing qua socket (debounce 300ms)
    _typingDebounceTimer?.cancel();
    _typingDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      repository.sendTypingStatus(
        conversationId: conversationId,
        isTyping: text.trim().isNotEmpty,
      );
    });
  }

  // --- Gửi tin nhắn Text ---

  Future<void> sendTextMessage(String rawContent) async {
    final trimmed = rawContent.trim();
    if (trimmed.isEmpty) return;

    // Tự động chuyển đổi các ký tự emote (như :)) -> 😆, <3 -> ❤️) theo yêu cầu Slide 28
    final processedContent = ChatEmoteConverter.convertEmotes(trimmed);

    // Sinh Client Message ID duy nhất để chống duplicate và chống replay request
    final clientMsgId =
        '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999999)}';

    final tempMessage = ChatMessage(
      messageId: '',
      clientMsgId: clientMsgId,
      conversationId: conversationId,
      senderId: userId,
      senderName: currentUserName,
      content: processedContent,
      createdAt: DateTime.now(),
      status: MessageStatus.sending,
    );

    // 1. Optimistic Update hiển thị ngay lập tức
    _messages.insert(0, tempMessage);
    _draftText = '';
    notifyListeners();

    // 2. Xóa bản nháp sau khi đã bấm gửi
    draftStore.remove(userId: userId, name: _draftKey);

    // 3. Tắt trạng thái typing
    repository.sendTypingStatus(
      conversationId: conversationId,
      isTyping: false,
    );

    // 4. Gửi qua STOMP WebSocket
    try {
      final stomp = repository.stomp;
      if (stomp != null && !stomp.isConnected) {
        await stomp.connect();
        for (var i = 0; i < 25; i++) {
          if (stomp.isConnected) break;
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }

      if (stomp != null && stomp.isConnected) {
        repository.sendStompMessage(
          conversationId: conversationId,
          content: processedContent,
          clientMsgId: clientMsgId,
        );
        _markMessageStatus(clientMsgId, MessageStatus.sent);
      } else {
        // Nếu socket chưa nối hoặc offline, đánh dấu failed để có nút Thử lại
        _markMessageStatus(clientMsgId, MessageStatus.failed);
      }

      // Lưu cache cục bộ
      repository.saveCachedMessages(
        userId: userId,
        conversationId: conversationId,
        messages: _messages,
      );
    } catch (_) {
      _markMessageStatus(clientMsgId, MessageStatus.failed);
    }
  }

  // --- Gửi tin nhắn Ảnh ---

  Future<void> sendImageMessage(String imageFilePath) async {
    final clientMsgId =
        'img_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999999)}';

    final tempMessage = ChatMessage(
      messageId: '',
      clientMsgId: clientMsgId,
      conversationId: conversationId,
      senderId: userId,
      senderName: currentUserName,
      content: '[Hình ảnh]',
      messageType: MessageType.image,
      mediaUrls: [imageFilePath], // Đường dẫn local hiển thị trước
      createdAt: DateTime.now(),
      status: MessageStatus.sending,
    );

    _messages.insert(0, tempMessage);
    notifyListeners();

    try {
      // 1. Upload ảnh lên server với purpose=CHAT (Slide 157)
      final uploaded = await repository.uploadChatImage(imageFilePath);

      // 2. Gửi STOMP mang URL ảnh từ server
      final stomp = repository.stomp;
      if (stomp != null && !stomp.isConnected) {
        await stomp.connect();
        for (var i = 0; i < 25; i++) {
          if (stomp.isConnected) break;
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }

      if (stomp != null && stomp.isConnected) {
        repository.sendStompMessage(
          conversationId: conversationId,
          content: '[Hình ảnh]',
          clientMsgId: clientMsgId,
          mediaUrls: [uploaded.url],
        );
        _markMessageStatus(clientMsgId, MessageStatus.sent);
      } else {
        _markMessageStatus(clientMsgId, MessageStatus.failed);
      }
    } catch (_) {
      _markMessageStatus(clientMsgId, MessageStatus.failed);
    }
  }

  void retryFailedMessage(ChatMessage failedMessage) {
    final index = _messages.indexWhere(
      (m) => m.clientMsgId == failedMessage.clientMsgId,
    );
    if (index == -1) return;

    _messages[index] = failedMessage.copyWith(status: MessageStatus.sending);
    notifyListeners();

    if (failedMessage.messageType == MessageType.image &&
        failedMessage.mediaUrls.isNotEmpty) {
      sendImageMessage(failedMessage.mediaUrls.first);
    } else {
      try {
        final stomp = repository.stomp;
        if (stomp != null && !stomp.isConnected) {
          stomp.connect();
        }

        if (stomp != null && stomp.isConnected) {
          repository.sendStompMessage(
            conversationId: conversationId,
            content: failedMessage.content,
            clientMsgId: failedMessage.clientMsgId, // Giữ nguyên ID chống trùng
          );
          _markMessageStatus(failedMessage.clientMsgId, MessageStatus.sent);
        } else {
          _markMessageStatus(failedMessage.clientMsgId, MessageStatus.failed);
        }
      } catch (_) {
        _markMessageStatus(failedMessage.clientMsgId, MessageStatus.failed);
      }
    }
  }

  void _markMessageStatus(String clientMsgId, MessageStatus status) {
    final index = _messages.indexWhere((m) => m.clientMsgId == clientMsgId);
    if (index != -1) {
      _messages[index] = _messages[index].copyWith(status: status);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _typingIndicatorTimer?.cancel();
    _typingDebounceTimer?.cancel();
    _draftDebounceTimer?.cancel();
    super.dispose();
  }
}
