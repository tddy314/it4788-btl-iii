import 'package:dio/dio.dart';

import '../../../core/media/media_upload_service.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/json_cache.dart';
import '../models/chat_message.dart';
import '../models/conversation_item.dart';
import 'stomp_client.dart';

class ChatRepository {
  ChatRepository({
    required ApiClient api,
    required JsonCache cache,
    required MediaUploadService mediaUploadService,
    SqbStompClient? stompClient,
  }) : _api = api,
       _cache = cache,
       _mediaUploadService = mediaUploadService,
       _stomp = stompClient;

  final ApiClient _api;
  final JsonCache _cache;
  final MediaUploadService _mediaUploadService;
  final SqbStompClient? _stomp;

  static const _conversationsResource = 'conversations';
  static String _messagesResource(String convId) => 'messages_$convId';

  SqbStompClient? get stomp => _stomp;

  // 1. Tải danh sách các cuộc hội thoại
  Future<ConversationListResponse> fetchConversations({
    String? after,
    int limit = 20,
  }) async {
    final query = <String, dynamic>{
      'limit': limit,
      if (after != null && after.isNotEmpty) 'after': after,
    };

    return _api.get(
      'conversations',
      query: query,
      decode: ConversationListResponse.fromJson,
    );
  }

  // 2. Mở hoặc tạo cuộc trò chuyện 1-1
  Future<ConversationItem> createDirectConversation(String targetUserId) async {
    return _api.request(
      'conversations/direct',
      method: 'POST',
      data: {'target_user_id': targetUserId},
      decode: (data) => ConversationItem.fromJson(data as Map<String, dynamic>),
    );
  }

  // 3. Tải danh sách tin nhắn của cuộc trò chuyện
  Future<ChatMessagesResponse> fetchMessages(
    String conversationId, {
    String? after,
    int limit = 20,
  }) async {
    final query = <String, dynamic>{
      'limit': limit,
      if (after != null && after.isNotEmpty) 'after': after,
    };

    return _api.get(
      'conversations/$conversationId/messages',
      query: query,
      decode: ChatMessagesResponse.fromJson,
    );
  }

  // 4. Gửi tin nhắn qua STOMP WebSocket
  void sendStompMessage({
    required String conversationId,
    required String content,
    required String clientMsgId,
    List<String> mediaUrls = const [],
  }) {
    if (_stomp != null && _stomp!.isConnected) {
      _stomp!.send('/app/chat.send', {
        'conversation_id': conversationId,
        'content': content,
        'client_msg_id': clientMsgId,
        'message_type': mediaUrls.isNotEmpty ? 'IMAGE' : 'TEXT',
        'media_urls': mediaUrls,
      });
    }
  }

  // 5. Gửi trạng thái đang nhập (Typing)
  void sendTypingStatus({
    required String conversationId,
    required bool isTyping,
  }) {
    if (_stomp != null && _stomp!.isConnected) {
      _stomp!.send('/app/chat.typing', {
        'conversation_id': conversationId,
        'is_typing': isTyping,
      });
    }
  }

  // 6. Gửi trạng thái đã đọc tin nhắn
  void sendReadStatus({
    required String conversationId,
    required String messageId,
  }) {
    if (_stomp != null && _stomp!.isConnected) {
      _stomp!.send('/app/chat.read', {
        'conversation_id': conversationId,
        'message_id': messageId,
      });
    }
  }

  // 7. Upload ảnh gửi trong chat (Tối đa 4MB)
  Future<UploadedMedia> uploadChatImage(
    String filePath, {
    ProgressCallback? onProgress,
    CancelToken? cancelToken,
  }) {
    return _mediaUploadService.upload(
      filePath: filePath,
      purpose: MediaPurpose.chat,
      maxBytes: 4 * 1024 * 1024,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
  }

  // --- Cache Offline Support ---

  Future<ConversationListResponse?> loadCachedConversations(
    String userId,
  ) async {
    final entry = await _cache.read(
      userId: userId,
      resource: _conversationsResource,
    );
    if (entry == null || entry.data == null) return null;
    try {
      return ConversationListResponse.fromJson(entry.data);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveCachedConversations(
    String userId,
    ConversationListResponse response,
  ) async {
    final toSave = ConversationListResponse(
      items: response.items.take(30).toList(),
      after: response.after,
      hasNext: response.hasNext,
    ).toJson();

    await _cache.write(
      userId: userId,
      resource: _conversationsResource,
      data: toSave,
    );
  }

  Future<List<ChatMessage>?> loadCachedMessages({
    required String userId,
    required String conversationId,
  }) async {
    final entry = await _cache.read(
      userId: userId,
      resource: _messagesResource(conversationId),
    );
    if (entry == null || entry.data == null) return null;
    try {
      final listRaw = entry.data;
      if (listRaw is List) {
        return listRaw
            .whereType<Map<String, dynamic>>()
            .map(ChatMessage.fromJson)
            .toList();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveCachedMessages({
    required String userId,
    required String conversationId,
    required List<ChatMessage> messages,
  }) async {
    // Chỉ cache tối đa 50 tin nhắn gần nhất theo đúng giới hạn bộ nhớ
    final toSave = messages.take(50).map((e) => e.toJson()).toList();
    await _cache.write(
      userId: userId,
      resource: _messagesResource(conversationId),
      data: toSave,
    );
  }
}
