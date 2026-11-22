import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/storage/draft_store.dart';
import '../data/chat_repository.dart';
import '../models/chat_event.dart';
import '../models/chat_message.dart';
import '../data/stomp_client.dart';
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
    bool Function()? isCurrent,
    this.ackTimeout = const Duration(seconds: 15),
  }) : _isCurrent = isCurrent ?? (() => true);
  final ChatRepository repository;
  final DraftStore draftStore;
  final String userId, currentUserName, conversationId, partnerName;
  final String? partnerAvatarUrl;
  final bool Function() _isCurrent;
  final Duration ackTimeout;
  List<ChatMessage> _messages = [];
  bool _isLoading = false, _isLoadingEarlier = false, _isPartnerTyping = false;
  bool _disposed = false,
      _ready = false,
      _accessDenied = false,
      _reconnecting = false;
  int _generation = 0;
  String? _errorMessage, _after;
  bool _hasNext = false;
  String _draftText = '';
  final _acks = <String, Timer>{};
  final _sending = <String>{};
  final _uploadCancel = CancelToken();
  Timer? _typingTimer, _typingDebounce;
  StreamSubscription<StompConnectionState>? _socketStates;
  Future<void> _draftWrites = Future.value();
  bool _draftDurable = true;
  bool get _active => !_disposed && _isCurrent();
  bool get ready => _ready;
  bool get canCompose =>
      _active && _ready && !_accessDenied && _outbox.length < 10;
  bool get accessDenied => _accessDenied;
  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isLoading => _isLoading;
  bool get isLoadingEarlier => _isLoadingEarlier;
  bool get isPartnerTyping => _isPartnerTyping;
  String? get errorMessage => _errorMessage;
  bool get hasNext => _hasNext;
  String get draftText => _draftText;
  String get _draftKey => 'chat_draft_$conversationId';
  void _notify() {
    if (_active) notifyListeners();
  }

  List<ChatMessage> get _outbox =>
      _messages.where((m) => m.messageId.isEmpty).toList();

  void _boundMessages() {
    final pending = _outbox;
    final confirmed = _messages.where((m) => m.messageId.isNotEmpty).toList()
      ..sort((a, b) {
        final date = b.createdAt.compareTo(a.createdAt);
        if (date != 0) return date;
        return (BigInt.tryParse(b.messageId) ?? BigInt.zero).compareTo(
          BigInt.tryParse(a.messageId) ?? BigInt.zero,
        );
      });
    _messages = [...pending, ...confirmed.take(200 - pending.length)];
  }

  Future<void> initialize() async {
    try {
      final draft = await draftStore.read(userId: userId, name: _draftKey);
      if (!_active) return;
      _draftText = draft?['text'] is String ? draft!['text'] as String : '';
      final outbox = (draft?['outbox'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(ChatMessage.fromCache)
          .toList();
      final cached = await repository.loadCachedMessages(
        userId: userId,
        conversationId: conversationId,
      );
      if (!_active) return;
      final byId = <String, ChatMessage>{};
      for (final m in [...?cached, ...outbox]) {
        byId[m.messageId.isEmpty ? 'local:${m.clientMsgId}' : m.messageId] = m;
      }
      _messages = byId.values.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (_) {
      if (_active) {
        _errorMessage =
            'Không đọc được bản lưu hội thoại. Đang thử tải dữ liệu mới.';
      }
    }
    if (!_active) return;
    _ready = true;
    _notify();
    _setupRealtimeListeners();
    await reconnect();
  }

  void _setupRealtimeListeners() {
    final stomp = repository.stomp;
    if (stomp == null || !_active) return;
    stomp.subscribe('/user/queue/messages', _onEvent);
    _socketStates = stomp.stateStream.listen((state) {
      if (!_active) return;
      if (state == StompConnectionState.disconnected) {
        for (final m in _outbox.where(
          (m) => m.status == MessageStatus.sending,
        )) {
          _setStatus(m.clientMsgId, MessageStatus.unconfirmed);
        }
        _errorMessage =
            stomp.lastError ??
            'Kết nối trò chuyện đã ngắt. Hãy tải lại để kết nối.';
        unawaited(_persist());
        _notify();
      }
    });
  }

  Future<void> reconnect() async {
    if (!_active || _reconnecting) return;
    _reconnecting = true;
    try {
      // This GET also lets ApiClient refresh an expired access token safely.
      await fetchFirstPage(showLoading: _messages.isEmpty);
      if (!_active || _accessDenied) return;
      await repository.stomp?.connect();
      if (_active && repository.stomp?.isConnected == false) {
        _errorMessage =
            repository.stomp?.lastError ??
            'Chưa kết nối được trò chuyện. Hãy thử lại.';
      }
    } finally {
      _reconnecting = false;
      _notify();
    }
  }

  void _onEvent(Map<String, dynamic> payload) {
    // Multiple callbacks can arrive after an account switch or screen closure.
    if (!_active) return;
    final event = ChatEvent.parse(payload);
    if (event.conversationId != conversationId) return;
    final data = event.data;
    switch (event.type) {
      case ChatEventType.message:
        final m = ChatMessage.fromJson(data);
        if (m.messageId.isEmpty || m.senderId.isEmpty) return;
        _mergeMessage(m);
        if (!m.isMine(userId)) _read(m.messageId);
      case ChatEventType.typing:
        if ((data['user_id'] ?? data['sender_id'])?.toString() == userId) {
          return;
        }
        _isPartnerTyping = data['typing'] == true || data['is_typing'] == true;
        _typingTimer?.cancel();
        if (_isPartnerTyping) {
          _typingTimer = Timer(const Duration(seconds: 4), () {
            _isPartnerTyping = false;
            _notify();
          });
        }
      case ChatEventType.read:
        final reader =
            (data['user_id'] ??
                    data['reader_id'] ??
                    data['reader_user_id'] ??
                    (data['reader'] is Map ? data['reader']['user_id'] : null))
                ?.toString();
        if (reader == null || reader == userId) return;
        final lastRead = BigInt.tryParse(data['message_id']?.toString() ?? '');
        if (lastRead == null) return;
        _messages = _messages.map((m) {
          final id = BigInt.tryParse(m.messageId);
          return m.isMine(userId) && id != null && id <= lastRead
              ? m.copyWith(isRead: true)
              : m;
        }).toList();
      case ChatEventType.revoked:
        final id = data['message_id']?.toString();
        _messages = _messages.where((m) => m.messageId != id).toList();
      case ChatEventType.accessChanged:
        unawaited(fetchFirstPage());
      case ChatEventType.unknown:
        return;
    }
    _boundMessages();
    _notify();
    unawaited(_persist());
  }

  void pause() {
    if (!_active) return;
    _isPartnerTyping = false;
    if (repository.stomp?.isConnected == true) {
      try {
        repository.sendTypingStatus(
          conversationId: conversationId,
          isTyping: false,
        );
      } catch (_) {}
    }
    repository.stomp?.disconnect();
  }

  void _mergeMessage(ChatMessage message) {
    // Never merge confirmed messages by text/time; identical messages are valid.
    final index = _messages.indexWhere(
      (m) =>
          m.messageId.isNotEmpty && m.messageId == message.messageId ||
          m.messageId.isEmpty &&
              message.clientMsgId.isNotEmpty &&
              m.clientMsgId == message.clientMsgId,
    );
    if (index < 0) {
      _messages.insert(0, message);
    } else {
      _acks.remove(_messages[index].clientMsgId)?.cancel();
      _messages[index] = message.copyWith(status: MessageStatus.sent);
    }
  }

  void _read(String id) {
    if (!_active || repository.stomp?.isConnected != true) return;
    try {
      repository.sendReadStatus(conversationId: conversationId, messageId: id);
    } catch (_) {}
  }

  Future<void> fetchFirstPage({bool showLoading = true}) async {
    if (!_active || _isLoading) return;
    final generation = ++_generation;
    _isLoading = true;
    _isLoadingEarlier = false;
    _notify();
    try {
      final response = await repository.fetchMessages(
        conversationId,
        limit: 20,
      );
      if (!_active || generation != _generation) return;
      final pending = _outbox;
      if (response.conversationType != 'DIRECT') {
        _accessDenied = true;
        _hasNext = false;
        _messages = [];
        _errorMessage = 'Ứng dụng hiện chỉ hỗ trợ trò chuyện một-một.';
        repository.stomp?.disconnect();
        try {
          await repository.clearCachedMessages(userId, conversationId);
        } catch (_) {}
        return;
      }
      _messages = [...pending];
      for (final m in response.messages.reversed) {
        _mergeMessage(m);
      }
      _messages.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _after = response.after;
      _hasNext = response.hasNext;
      _errorMessage = null;
      _accessDenied = false;
      await _persist();
    } on AppFailure catch (e) {
      if (!_active || generation != _generation) return;
      _errorMessage = e.message;
      if (const [
        FailureKind.unauthorized,
        FailureKind.forbidden,
        FailureKind.notFound,
      ].contains(e.kind)) {
        _messages = _outbox;
        _hasNext = false;
        _accessDenied =
            e.kind == FailureKind.forbidden ||
            e.kind == FailureKind.notFound ||
            e.kind == FailureKind.unauthorized;
        if (_accessDenied) {
          repository.stomp?.disconnect();
          try {
            await repository.clearCachedMessages(userId, conversationId);
          } catch (_) {}
        }
      }
    } catch (_) {
      if (_active) _errorMessage = 'Không thể tải tin nhắn. Hãy thử lại.';
    } finally {
      if (_active && generation == _generation) {
        _isLoading = false;
        _notify();
      }
    }
  }

  Future<void> loadEarlierMessages() async {
    if (!_active ||
        _isLoading ||
        _isLoadingEarlier ||
        !_hasNext ||
        _after == null ||
        _messages.length >= 200) {
      return;
    }
    final generation = _generation, cursor = _after;
    _isLoadingEarlier = true;
    _notify();
    try {
      final page = await repository.fetchMessages(
        conversationId,
        after: cursor,
        limit: 20,
      );
      if (!_active || generation != _generation) return;
      final ids = _messages.map((e) => e.messageId).toSet();
      _messages.addAll(page.messages.where((e) => ids.add(e.messageId)));
      _boundMessages();
      _hasNext = page.hasNext && page.after != cursor && _messages.length < 200;
      _after = page.after;
      await _persist();
    } on AppFailure catch (e) {
      if (!_active || generation != _generation) return;
      _errorMessage = e.message;
      if (const [
        FailureKind.unauthorized,
        FailureKind.forbidden,
        FailureKind.notFound,
      ].contains(e.kind)) {
        _messages = _outbox;
        _hasNext = false;
        _accessDenied = true;
        repository.stomp?.disconnect();
        try {
          await repository.clearCachedMessages(userId, conversationId);
        } catch (_) {}
      }
    } catch (_) {
      if (_active) _errorMessage = 'Không thể tải tin nhắn cũ.';
    } finally {
      if (_active && generation == _generation) {
        _isLoadingEarlier = false;
        _notify();
      }
    }
  }

  void onTextChanged(String text) {
    if (!_active || !_ready) return;
    _draftText = text;
    unawaited(_saveDraft());
    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(milliseconds: 300), () {
      if (_active && repository.stomp?.isConnected == true) {
        try {
          repository.sendTypingStatus(
            conversationId: conversationId,
            isTyping: text.trim().isNotEmpty,
          );
        } catch (_) {}
      }
    });
  }

  Future<void> _saveDraft() {
    final snapshot = {
      'text': _draftText,
      'outbox': _outbox.map((m) => m.toJson()).toList(),
    };
    final write = _draftWrites.then((_) async {
      if (!_isCurrent()) return;
      if ((snapshot['text'] as String).isEmpty &&
          (snapshot['outbox'] as List).isEmpty) {
        await draftStore.remove(userId: userId, name: _draftKey);
      } else {
        await draftStore.save(userId: userId, name: _draftKey, data: snapshot);
      }
      _draftDurable = true;
    });
    _draftWrites = write.catchError((Object _) {
      _draftDurable = false;
      if (_active) {
        _errorMessage = 'Không lưu được bản nháp. Hãy giữ màn hình này mở.';
        _notify();
      }
    });
    return _draftWrites;
  }

  Future<bool> _persist() async {
    if (!_active) return false;
    await _saveDraft();
    if (!_active || !_draftDurable) return false;
    try {
      await repository.saveCachedMessages(
        userId: userId,
        conversationId: conversationId,
        messages: _messages,
      );
    } catch (_) {
      if (_active) {
        _errorMessage = 'Không lưu được hội thoại trên máy.';
        _notify();
      }
    }
    return _active && _draftDurable;
  }

  String _id() =>
      '${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 32)}';
  bool _canSend() {
    if (!_active || !_ready || _accessDenied) return false;
    if (_outbox.length >= 10) {
      _errorMessage =
          'Hãy kiểm tra các tin chưa được xác nhận trước khi gửi thêm.';
      _notify();
      return false;
    }
    return true;
  }

  Future<bool> sendTextMessage(String text) async {
    if (text.trim().isEmpty || !_canSend()) return false;
    final message = ChatMessage(
      messageId: '',
      clientMsgId: _id(),
      conversationId: conversationId,
      senderId: userId,
      senderName: currentUserName,
      content: ChatEmoteConverter.convertEmotes(text.trim()),
      createdAt: DateTime.now(),
      status: MessageStatus.sending,
    );
    _messages.insert(0, message);
    _boundMessages();
    _draftText = '';
    _notify();
    if (!await _persist()) {
      _draftText = text;
      _setStatus(message.clientMsgId, MessageStatus.failed);
      return false;
    }
    await _sendExisting(message);
    return true;
  }

  Future<void> sendImageMessage(String path) async {
    if (!_canSend()) return;
    await _addImage(path, '[Hình ảnh]');
  }

  Future<void> _addImage(String path, String text) async {
    final m = ChatMessage(
      messageId: '',
      clientMsgId: _id(),
      conversationId: conversationId,
      senderId: userId,
      senderName: currentUserName,
      content: text,
      messageType: MessageType.image,
      mediaUrls: [path],
      createdAt: DateTime.now(),
      status: MessageStatus.sending,
    );
    _messages.insert(0, m);
    _boundMessages();
    _notify();
    if (!await _persist()) {
      _setStatus(m.clientMsgId, MessageStatus.failed);
      return;
    }
    await _sendExisting(m);
  }

  Future<void> _sendExisting(ChatMessage original) async {
    if (!_active || !_sending.add(original.clientMsgId)) return;
    var message = original;
    var handedOff = false, uploadStarted = false;
    _setStatus(message.clientMsgId, MessageStatus.sending);
    try {
      await repository.stomp?.connect();
      if (!_active || _accessDenied) return;
      if (repository.stomp?.isConnected != true) throw AppFailure.offline;
      if (message.messageType == MessageType.image &&
          message.mediaUrls.isNotEmpty &&
          !message.mediaUrls.first.startsWith('https://')) {
        final uploaded = await repository.uploadChatImage(
          message.mediaUrls.first,
          cancelToken: _uploadCancel,
          onProgress: (sent, total) {
            if (sent > 0) uploadStarted = true;
          },
        );
        if (!_active) return;
        message = message.copyWith(mediaUrls: [uploaded.url]);
        _replace(message);
        await _persist();
      }
      if (!_active || _accessDenied) return;
      // Persist uncertainty BEFORE a non-replayable write reaches the socket.
      _setStatus(message.clientMsgId, MessageStatus.unconfirmed);
      if (!await _persist()) {
        _setStatus(message.clientMsgId, MessageStatus.failed);
        return;
      }
      if (!_active) return;
      handedOff = true;
      repository.sendStompMessage(
        conversationId: conversationId,
        content: message.content,
        clientMsgId: message.clientMsgId,
        mediaUrls: message.mediaUrls,
      );
      // A synchronous test/broadcast may already have confirmed this message.
      if (_outbox.any((m) => m.clientMsgId == message.clientMsgId)) {
        _setStatus(message.clientMsgId, MessageStatus.sending);
        _acks.remove(message.clientMsgId)?.cancel();
        _acks[message.clientMsgId] = Timer(ackTimeout, () {
          _acks.remove(message.clientMsgId);
          if (!_active) return;
          _setStatus(message.clientMsgId, MessageStatus.unconfirmed);
          _errorMessage = 'Chưa nhận được xác nhận gửi tin. Hãy tải lại lịch sử để kiểm tra; app không tự gửi lại.';
          unawaited(_persist());
        });
      }
    } catch (_) {
      _setStatus(
        message.clientMsgId,
        handedOff || uploadStarted
            ? MessageStatus.unconfirmed
            : MessageStatus.failed,
      );
      if (_active) {
        _errorMessage = handedOff || uploadStarted
            ? 'Chưa xác định được kết quả. Hãy tải lại để kiểm tra trước khi gửi lại.'
            : 'Chưa gửi được tin nhắn. Hãy kiểm tra kết nối.';
      }
    } finally {
      _sending.remove(message.clientMsgId);
      if (_active) {
        await _persist();
        _notify();
      }
    }
  }

  Future<void> retryFailedMessage(ChatMessage message) async {
    if (!_active || _accessDenied) return;
    if (message.status == MessageStatus.unconfirmed) {
      await reconnect();
      return;
    }
    if (message.status != MessageStatus.failed) return;
    await _sendExisting(message); // Same local ID and uploaded URL, one bubble.
  }

  Future<void> discardUnconfirmed(String clientId) async {
    if (!_active || _sending.contains(clientId)) return;
    _acks.remove(clientId)?.cancel();
    _messages.removeWhere(
      (m) =>
          m.clientMsgId == clientId &&
          m.messageId.isEmpty &&
          m.status == MessageStatus.unconfirmed,
    );
    await _persist();
    _notify();
  }

  /// Explicit user reconciliation, never infer an acknowledgement by matching
  /// text/time. The selected server message must already be in this history.
  Future<bool> reconcileUnconfirmed(
    String clientId,
    String serverMessageId,
  ) async {
    if (!_active || _accessDenied || _sending.contains(clientId)) return false;
    final pending = _messages.any(
      (m) =>
          m.clientMsgId == clientId &&
          m.messageId.isEmpty &&
          m.status == MessageStatus.unconfirmed,
    );
    final confirmed = _messages.any(
      (m) =>
          m.messageId.isNotEmpty &&
          m.messageId == serverMessageId &&
          m.senderId == userId,
    );
    if (!pending || !confirmed) return false;
    _acks.remove(clientId)?.cancel();
    _messages.removeWhere(
      (m) => m.messageId.isEmpty && m.clientMsgId == clientId,
    );
    await _persist();
    _notify();
    return true;
  }

  void _replace(ChatMessage message) {
    if (!_active) return;
    final index = _messages.indexWhere(
      (m) => m.clientMsgId == message.clientMsgId,
    );
    if (index >= 0) _messages[index] = message;
  }

  void _setStatus(String id, MessageStatus status) {
    if (!_active) return;
    final index = _messages.indexWhere(
      (m) => m.clientMsgId == id && m.messageId.isEmpty,
    );
    if (index >= 0) {
      _messages[index] = _messages[index].copyWith(status: status);
      _notify();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_generation;
    _uploadCancel.cancel();
    _typingTimer?.cancel();
    _typingDebounce?.cancel();
    for (final timer in _acks.values) {
      timer.cancel();
    }
    unawaited(_socketStates?.cancel());
    repository.stomp?.unsubscribe('/user/queue/messages');
    repository.stomp?.disconnect();
    super.dispose();
  }
}
