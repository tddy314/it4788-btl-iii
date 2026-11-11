import 'package:dio/dio.dart';

import '../../../core/media/media_upload_service.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/json_cache.dart';
import '../models/chat_message.dart';
import '../models/conversation_item.dart';
import 'stomp_client.dart';

class ChatRepository {
  ChatRepository({
    required this.api,
    required this.cache,
    required this.mediaUploadService,
    SqbStompClient? stompClient,
    String? wsUrl,
  }) : _stomp =
           stompClient ??
           SqbStompClient(
             url: wsUrl ?? 'wss://snsqb.duckdns.org/api/v1/ws',
             tokenProvider: () async => api.session.tokens?.accessToken,
           );

  final ApiClient api;
  final JsonCache cache;
  final MediaUploadService mediaUploadService;
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

    return api.get(
      'conversations',
      query: query,
      decode: ConversationListResponse.fromJson,
    );
  }

  // 2. Mở hoặc tạo cuộc trò chuyện 1-1
  Future<ConversationItem> createDirectConversation(
    String targetUserId, {
    String? currentUserId,
  }) async {
    final parsedId = int.tryParse(targetUserId.trim());
    return api.request(
      'conversations/direct',
      method: 'POST',
      data: {'target_user_id': parsedId ?? targetUserId.trim()},
      decode: (data) => ConversationItem.fromJson(
        data as Map<String, dynamic>,
        currentUserId: currentUserId,
      ),
    );
  }

  // 2b. Lấy danh sách bạn bè để hiển thị và chọn nhắn tin nhanh
  Future<List<ChatPartnerSummary>> fetchFriendsForChat({int limit = 30}) async {
    return api.get(
      'friendships',
      query: {'limit': limit},
      decode: decodePartnerList,
    );
  }

  // 2c. Tìm người dùng theo tên hoặc MSSV (GET /search?type=USER)
  Future<List<ChatPartnerSummary>> searchUsersForChat(
    String query, {
    CancelToken? cancelToken,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    return api.get(
      'search',
      query: {'query': trimmed, 'type': 'USER', 'limit': 20},
      cancelToken: cancelToken,
      decode: decodePartnerList,
    );
  }

  static List<ChatPartnerSummary> decodePartnerList(Object? data) {
    if (data is! Map<String, dynamic>) return const [];
    final items = data['items'];
    if (items is! List) return const [];
    final result = <ChatPartnerSummary>[];
    for (final raw in items) {
      if (raw is Map<String, dynamic>) {
        final userMap = raw['user'] is Map<String, dynamic>
            ? raw['user'] as Map<String, dynamic>
            : raw;
        final partner = ChatPartnerSummary.fromJson(userMap);
        if (partner.userId.isNotEmpty) {
          result.add(partner);
        }
      }
    }
    return result;
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

    return api.get(
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
    final client = _stomp;
    if (client != null && client.isConnected) {
      client.send('/app/chat.send', {
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
    final client = _stomp;
    if (client != null && client.isConnected) {
      client.send('/app/chat.typing', {
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
    final client = _stomp;
    if (client != null && client.isConnected) {
      client.send('/app/chat.read', {
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
    return mediaUploadService.upload(
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
    final entry = await cache.read(
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

    await cache.write(
      userId: userId,
      resource: _conversationsResource,
      data: toSave,
    );
  }

  Future<List<ChatMessage>?> loadCachedMessages({
    required String userId,
    required String conversationId,
  }) async {
    final entry = await cache.read(
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
    await cache.write(
      userId: userId,
      resource: _messagesResource(conversationId),
      data: toSave,
    );
  }
}
