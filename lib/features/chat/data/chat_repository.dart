import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/media/media_upload_service.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/json_cache.dart';
import '../../../core/storage/draft_store.dart';
import '../../../core/storage/key_value_store.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/network/connection_monitor.dart';
import '../models/chat_message.dart';
import '../models/conversation_item.dart';
import 'stomp_client.dart';
import 'chat_attachment_store.dart';

class ChatRepository {
  ChatRepository({
    required this.api,
    required this.cache,
    required this.mediaUploadService,
    SqbStompClient? stompClient,
    String? wsUrl,
    DraftStore? privateStore,
  }) : _privateStore = privateStore ?? DraftStore(SecureKeyValueStore()),
       _stomp =
           stompClient ??
           SqbStompClient(
             url: wsUrl ?? 'wss://snsqb.duckdns.org/api/v1/ws',
             tokenProvider: () async {
               if (api.connection.status == ConnectionStatus.offline) {
                 throw AppFailure.offline;
               }
               return api.session.tokens?.accessToken;
             },
           ) {
    _userId = api.session.tokens?.userId;
    api.session.addListener(_sessionChanged);
  }

  final ApiClient api;
  final JsonCache cache;
  final MediaUploadService mediaUploadService;
  final SqbStompClient? _stomp;
  final DraftStore _privateStore;
  String? _userId;
  bool _disposed = false, _invalid = false;
  Future<void> _writes = Future.value();
  Future<void>? _migration;
  Future<void> _migrateLegacy(String userId) =>
      _migration ??= _cleanLegacy(userId);
  Future<void> _cleanLegacy(String userId) async {
    if (!isActive || userId != _userId) return;
    try {
      final preferences = SharedPreferencesAsync();
      final prefix = 'sqb.cache.v1/${Uri.encodeComponent(userId)}/';
      final keys = await preferences.getKeys();
      for (final key in keys.where(
        (key) =>
            key == '${prefix}conversations' ||
            key.startsWith('${prefix}messages_'),
      )) {
        if (!isActive) return;
        await preferences.remove(key);
      }
    } catch (_) {
      /* Older adapters can still remove known records below. */
    }
  }

  bool get isActive =>
      !_disposed && !_invalid && api.session.tokens?.userId == _userId;
  void _sessionChanged() {
    if (api.session.tokens?.userId != _userId) {
      _invalid = true;
      _stomp?.disconnect();
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    api.session.removeListener(_sessionChanged);
    _stomp?.dispose();
  }

  static const _conversationsResource = 'conversations';
  static String _messagesResource(String convId) => 'messages_$convId';

  SqbStompClient? get stomp => _stomp;

  // 1. Tải danh sách các cuộc hội thoại
  Future<ConversationListResponse> fetchConversations({
    String? after,
    String? cursor,
    int limit = 20,
  }) async {
    final query = <String, dynamic>{
      'limit': limit,
      if (after != null && after.isNotEmpty) 'after': after,
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
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
    if (!isActive) throw AppFailure.unauthorized;
    if (parsedId == null || parsedId <= 0 || parsedId.toString() == _userId) {
      throw const AppFailure(
        FailureKind.rejected,
        'Người nhận tin nhắn không hợp lệ.',
      );
    }
    final result = await api.request(
      'conversations/direct',
      method: 'POST',
      data: {'target_user_id': parsedId},
      decode: (data) {
        if (data is! Map<String, dynamic>) throw AppFailure.invalidData;
        final item = ConversationItem.fromJson(
          data,
          currentUserId: currentUserId,
        );
        if ((int.tryParse(item.conversationId) ?? 0) <= 0 ||
            item.type != 'DIRECT') {
          throw AppFailure.invalidData;
        }
        return item;
      },
    );
    if (!isActive) throw AppFailure.unauthorized;
    return result;
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
    if (data is! Map<String, dynamic>) throw AppFailure.invalidData;
    final items = data['items'];
    if (items is! List) throw AppFailure.invalidData;
    final result = <ChatPartnerSummary>[];
    for (final raw in items) {
      if (raw is Map<String, dynamic>) {
        final userMap = raw['user'] is Map<String, dynamic>
            ? raw['user'] as Map<String, dynamic>
            : raw;
        final partner = ChatPartnerSummary.fromJson(userMap);
        if ((int.tryParse(partner.userId) ?? 0) > 0) {
          result.add(partner);
        } else {
          throw AppFailure.invalidData;
        }
      } else {
        throw AppFailure.invalidData;
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

  Future<MessageDeleteResult> deleteMessage(
    String messageId,
    MessageDeleteScope scope,
  ) async {
    final id = int.tryParse(messageId);
    if (id == null || id <= 0) throw AppFailure.invalidData;
    if (!isActive) throw AppFailure.unauthorized;
    final result = await api.request(
      'messages/$id',
      method: 'DELETE',
      data: {'scope': scope.wire},
      decode: MessageDeleteResult.fromJson,
    );
    if (!isActive) throw AppFailure.unauthorized;
    if (result.messageId != id.toString() || result.scope != scope) {
      throw AppFailure.invalidData;
    }
    // A direct link can open chat without a conversations controller alive.
    // Redact its old preview on disk as well; storage failure cannot undo a
    // mutation that the server has already confirmed.
    try {
      final userId = _userId!;
      final cached = await loadCachedConversations(userId);
      if (isActive && cached != null) {
        await saveCachedConversations(
          userId,
          ConversationListResponse(
            items: cached.items
                .map(
                  (item) => item.lastMessageId == result.messageId
                      ? item.copyWith(
                          lastMessageContent: 'Tin nhắn không còn hiển thị.',
                        )
                      : item,
                )
                .toList(),
            after: cached.after,
            nextCursor: cached.nextCursor,
            hasNext: cached.hasNext,
          ),
        );
      }
    } catch (_) {
      // Keep the server confirmation even when local storage is unavailable.
    }
    return result;
  }

  // 4. Gửi tin nhắn qua STOMP WebSocket
  void sendStompMessage({
    required String conversationId,
    required String content,
    required String clientMsgId,
    List<String> mediaUrls = const [],
  }) {
    final client = _stomp;
    if (!isActive || client == null || !client.isConnected) {
      throw AppFailure.offline;
    }
    client.send('/app/chat.send', {
      'conversation_id': int.parse(conversationId),
      'content': content,
      // clientMsgId identifies the durable local outbox. The documented
      // SendWsMessageRequestDto has no such field; do not invent wire fields
      // or assume the server provides idempotence based on this UUID.
      'message_type': mediaUrls.isNotEmpty ? 'IMAGE' : 'TEXT',
      'media_urls': mediaUrls,
    });
  }

  // 5. Gửi trạng thái đang nhập (Typing)
  void sendTypingStatus({
    required String conversationId,
    required bool isTyping,
  }) {
    final client = _stomp;
    if (client != null && client.isConnected) {
      client.send('/app/chat.typing', {
        'conversation_id': int.parse(conversationId),
        'typing': isTyping,
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
        'conversation_id': int.parse(conversationId),
        'message_id': int.parse(messageId),
      });
    }
  }

  // 7. Upload ảnh gửi trong chat (Tối đa 4MB)
  Future<UploadedMedia> uploadChatImage(
    String filePath, {
    ProgressCallback? onProgress,
    CancelToken? cancelToken,
  }) async {
    await ChatAttachmentStore.validateFile(filePath);
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
    await _migrateLegacy(userId);
    await _removeLegacy(userId, _conversationsResource);
    if (!isActive) return null;
    try {
      final entry = await _privateStore.read(
        userId: userId,
        name: 'chat.cache.v2/conversations',
      );
      if (!isActive || entry == null) return null;
      return ConversationListResponse.fromJson(entry['data']);
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
      nextCursor: response.nextCursor,
      hasNext: response.hasNext,
    ).toJson();

    await _writePrivate(userId, 'conversations', toSave);
  }

  Future<List<ChatMessage>?> loadCachedMessages({
    required String userId,
    required String conversationId,
  }) async {
    await _migrateLegacy(userId);
    await _removeLegacy(userId, _messagesResource(conversationId));
    if (!isActive) return null;
    try {
      final entry = await _privateStore.read(
        userId: userId,
        name: 'chat.cache.v2/messages_$conversationId',
      );
      if (!isActive) return null;
      final listRaw = entry?['data'];
      if (listRaw is List) {
        return listRaw
            .whereType<Map<String, dynamic>>()
            .map(ChatMessage.fromCache)
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
    await _writePrivate(userId, 'messages_$conversationId', toSave);
  }

  Future<void> _removeLegacy(String userId, String resource) async {
    try {
      await cache.remove(userId: userId, resource: resource);
    } catch (_) {}
  }

  Future<void> clearCachedMessages(String userId, String conversationId) async {
    await _writes;
    await _privateStore.remove(
      userId: userId,
      name: 'chat.cache.v2/messages_$conversationId',
    );
    await _removeLegacy(userId, _messagesResource(conversationId));
  }

  Future<void> clearCachedConversations(String userId) async {
    await _writes;
    await _privateStore.remove(
      userId: userId,
      name: 'chat.cache.v2/conversations',
    );
    await _removeLegacy(userId, _conversationsResource);
  }

  Future<void> _writePrivate(String userId, String resource, Object data) {
    // Bound each encrypted record; do not silently lose an unconfirmed outbox.
    final snapshot = jsonDecode(jsonEncode(data));
    if (utf8.encode(jsonEncode(snapshot)).length > 512 * 1024) {
      throw const AppFailure(
        FailureKind.storage,
        'Không đủ chỗ lưu hội thoại trên máy.',
      );
    }
    final write = _writes.then((_) async {
      if (!isActive || _userId != userId) return;
      await _privateStore.save(
        userId: userId,
        name: 'chat.cache.v2/$resource',
        data: {'data': snapshot},
      );
      final index = await _privateStore.read(
        userId: userId,
        name: 'chat.cache.v2/index',
      );
      final resources = [
        resource,
        ...?(index?['resources'] as List?)?.whereType<String>().where(
          (e) => e != resource,
        ),
      ];
      for (final stale in resources.skip(12)) {
        await _privateStore.remove(
          userId: userId,
          name: 'chat.cache.v2/$stale',
        );
      }
      await _privateStore.save(
        userId: userId,
        name: 'chat.cache.v2/index',
        data: {'resources': resources.take(12).toList()},
      );
    });
    _writes = write.catchError((Object _) {});
    return write;
  }
}
