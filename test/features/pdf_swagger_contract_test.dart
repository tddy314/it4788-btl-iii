import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:it4788_btl/core/config/app_config.dart';
import 'package:it4788_btl/core/errors/app_failure.dart';
import 'package:it4788_btl/core/media/media_upload_service.dart';
import 'package:it4788_btl/core/network/api_client.dart';
import 'package:it4788_btl/core/storage/draft_store.dart';
import 'package:it4788_btl/core/storage/json_cache.dart';
import 'package:it4788_btl/core/storage/session_store.dart';
import 'package:it4788_btl/features/chat/controllers/conversations_controller.dart';
import 'package:it4788_btl/features/chat/data/chat_attachment_store.dart';
import 'package:it4788_btl/features/chat/data/chat_repository.dart';
import 'package:it4788_btl/features/chat/models/chat_message.dart';
import 'package:it4788_btl/features/chat/models/conversation_item.dart';
import 'package:it4788_btl/features/notifications/data/notification_repository.dart';
import 'package:it4788_btl/features/notifications/models/notification_item.dart';
import 'package:it4788_btl/features/posts/post_models.dart';
import 'package:it4788_btl/features/search/post_search.dart';
import 'package:it4788_btl/features/question_bank/question_bank_cache.dart';

import '../support/fakes.dart';
import 'auth/auth_test.dart' show AuthAdapter, response;
import 'chat/chat_flows_test.dart' show TestStomp;

class ControlledSearch extends Fake implements PostSearchRepository {
  final requests = <String, Completer<CursorPage<PostSearchResult>>>{};
  @override
  Future<CursorPage<PostSearchResult>> find(
    String query, {
    int? after,
    required CancelToken cancel,
  }) => (requests[query] = Completer()).future;
}

class MigrationStore extends MemoryStore {
  bool failWrites = true;
  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw StateError('Storage unavailable');
    await super.write(key, value);
  }
}

class CapturingStomp extends TestStomp {
  Map<String, dynamic>? body;
  String? destination;
  @override
  void send(String destination, Map<String, dynamic> body) {
    this.destination = destination;
    this.body = body;
  }
}

class ConversationPages extends Fake implements ChatRepository {
  final calls = <String?>[];
  @override
  final stomp = TestStomp();
  @override
  Future<ConversationListResponse?> loadCachedConversations(
    String userId,
  ) async => null;
  @override
  Future<List<ChatPartnerSummary>> fetchFriendsForChat({
    int limit = 30,
  }) async => [];
  @override
  Future<void> saveCachedConversations(
    String id,
    ConversationListResponse page,
  ) async {}
  @override
  Future<ConversationListResponse> fetchConversations({
    String? after,
    String? cursor,
    int limit = 20,
  }) async {
    calls.add(cursor);
    return ConversationListResponse(
      items: [
        ConversationItem(
          conversationId: calls.length.toString(),
          type: 'DIRECT',
          displayName: 'Bạn học',
        ),
      ],
      after: '1000',
      nextCursor: cursor == null ? 'opaque:1000:2' : 'opaque:1000:1',
      hasNext: calls.length == 1,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AuthAdapter adapter;
  late ApiClient api;
  late SessionStore session;
  setUp(() async {
    adapter = AuthAdapter();
    session = SessionStore(MemoryStore());
    await session.save(
      const SessionTokens(
        userId: '7',
        accessToken: 'test-access',
        refreshToken: 'test-refresh',
      ),
    );
    api = ApiClient(
      config: AppConfig(),
      session: session,
      connection: FakeConnection(),
      dio: Dio()..httpClientAdapter = adapter,
    );
  });
  tearDown(() {
    api.close();
    session.dispose();
  });

  test('Chat sends only documented wire fields; direct-chat rejects invalid IDs and old account repositories', () async {
    final socket = CapturingStomp();
    final repo = ChatRepository(
      api: api,
      cache: JsonCache(MemoryStore()),
      mediaUploadService: MediaUploadService(api),
      stompClient: socket,
      privateStore: DraftStore(MemoryStore()),
    );
    repo.sendStompMessage(
      conversationId: '10',
      content: 'Xin chào',
      clientMsgId: 'local-outbox-id',
    );
    expect(socket.destination, '/app/chat.send');
    expect(socket.body, {
      'conversation_id': 10,
      'content': 'Xin chào',
      'message_type': 'TEXT',
      'media_urls': [],
    });
    for (final id in ['abc', '-1', '0', '7']) {
      await expectLater(
        repo.createDirectConversation(id),
        throwsA(isA<AppFailure>()),
      );
    }
    expect(adapter.requests, isEmpty);
    adapter.respond = (_) async => response(200, {});
    await expectLater(
      repo.createDirectConversation('8'),
      throwsA(isA<AppFailure>()),
    );
    expect(adapter.requests.single.data, {'target_user_id': 8});
    await session.clear();
    await session.save(
      const SessionTokens(
        userId: '9',
        accessToken: 'next-test-access',
        refreshToken: 'next-test-refresh',
      ),
    );
    await expectLater(
      repo.createDirectConversation('8'),
      throwsA(isA<AppFailure>()),
    );
    expect(adapter.requests, hasLength(1));
    repo.dispose();
  });

  test('Malformed chat discovery is an error rather than a fake empty friends list', () {
    for (final bad in [
      null,
      {},
      {'items': 'bad'},
      {
        'items': [1],
      },
      {
        'items': [
          {'user_id': 'abc'},
        ],
      },
    ]) {
      expect(
        () => ChatRepository.decodePartnerList(bad),
        throwsA(isA<AppFailure>()),
      );
    }
    expect(ChatRepository.decodePartnerList({'items': []}), isEmpty);
  });

  test('Failed secure migration retains the only valid offline copies and retries safely', () async {
    final old = JsonCache(MemoryStore());
    final secure = MigrationStore();
    final notificationPage = NotificationListResponse(
      items: [
        NotificationItem(
          notificationId: '88',
          type: 'NEW_COMMENT',
          title: 'Thông báo',
          body: '',
          createdAt: DateTime.utc(2026),
        ),
      ],
      unreadCount: 1,
    );
    await old.write(
      userId: '7',
      resource: 'notifications',
      data: notificationPage.toJson(),
    );
    await old.write(
      userId: '7',
      resource: 'qb.submission.42',
      data: {'source': 'LLM'},
    );
    final notifications = NotificationRepository(
      api: api,
      cache: old,
      privateStore: DraftStore(secure),
    );
    final questions = QuestionBankCache(
      drafts: DraftStore(secure),
      legacy: old,
    );
    expect(
      (await notifications.loadCached('7'))!.items.single.notificationId,
      '88',
    );
    expect(
      (await questions.read(userId: '7', resource: 'qb.submission.42'))!.data,
      {'source': 'LLM'},
    );
    expect(await old.read(userId: '7', resource: 'notifications'), isNotNull);
    expect(
      await old.read(userId: '7', resource: 'qb.submission.42'),
      isNotNull,
    );
    secure.failWrites = false;
    await notifications.loadCached('7');
    await questions.read(userId: '7', resource: 'qb.submission.42');
    expect(await old.read(userId: '7', resource: 'notifications'), isNull);
    expect(await old.read(userId: '7', resource: 'qb.submission.42'), isNull);
  });

  test(
    'Notification read parses Swagger read/count/date and legacy PDF is_read',
    () async {
      adapter.respond = (request) async {
        expect(request.method, 'POST');
        expect(request.path, 'notifications/88/read');
        expect(request.headers['Authorization'], 'Bearer test-access');
        expect(request.data, isNull);
        return response(200, {
          'notification_id': 88,
          'read': true,
          'read_at': '2026-11-17T08:30:00Z',
          'unread_count': 9,
        });
      };
      final repo = NotificationRepository(
        api: api,
        cache: JsonCache(MemoryStore()),
        privateStore: DraftStore(MemoryStore()),
      );
      final result = await repo.markAsRead('88');
      expect(result.unreadCount, 9);
      expect(result.readAt, DateTime.utc(2026, 11, 17, 8, 30));
      final old = NotificationReadResult.fromJson({
        'notification_id': '88',
        'is_read': 'true',
        'read_at': '2026-11-17T08:30:00Z',
        'unread_count': '9',
      });
      expect(old.unreadCount, 9);
      adapter.respond = (_) async => response(200, {
        'notification_id': 89,
        'read': true,
        'read_at': '2026-11-17T08:30:00Z',
        'unread_count': 0,
      });
      await expectLater(repo.markAsRead('88'), throwsA(isA<AppFailure>()));
    },
  );

  test(
    'Notification cache migrates to secure storage and stays scoped to account',
    () async {
      final plain = MemoryStore(), secure = MemoryStore();
      final cache = JsonCache(plain);
      final page = NotificationListResponse(
        items: [
          NotificationItem(
            notificationId: '88',
            type: 'NEW_COMMENT',
            title: 'Thông báo riêng tư',
            body: 'Nội dung',
            createdAt: DateTime.utc(2026),
          ),
        ],
        unreadCount: 1,
      );
      await cache.write(
        userId: '7',
        resource: 'notifications',
        data: page.toJson(),
      );
      final repo = NotificationRepository(
        api: api,
        cache: cache,
        privateStore: DraftStore(secure),
      );
      expect(
        (await repo.loadCached('7'))!.items.single.title,
        'Thông báo riêng tư',
      );
      expect(await cache.read(userId: '7', resource: 'notifications'), isNull);
      expect(secure.values, isNotEmpty);
      expect(await repo.loadCached('8'), isNull);
      await repo.clearCache('7');
      expect(await repo.loadCached('7'), isNull);
    },
  );

  test('Question submissions/answer cache uses secure storage, preserves timestamps, migrates and separates accounts', () async {
    final preferences = MemoryStore(), encrypted = MemoryStore();
    final legacy = JsonCache(preferences);
    final cache = QuestionBankCache(
      drafts: DraftStore(encrypted),
      legacy: legacy,
    );
    await legacy.write(
      userId: '7',
      resource: 'qb.submission.42',
      data: {'source': 'LLM', 'confidence_score': 4},
    );
    final old = await legacy.read(userId: '7', resource: 'qb.submission.42');
    final restored = await cache.read(
      userId: '7',
      resource: 'qb.submission.42',
    );
    expect(restored!.data, old!.data);
    expect(restored.savedAt, old.savedAt);
    expect(
      await legacy.read(userId: '7', resource: 'qb.submission.42'),
      isNull,
    );
    expect(await cache.read(userId: '8', resource: 'qb.submission.42'), isNull);
    await cache.write(
      userId: '7',
      resource: 'qb.submission.42',
      data: {'updated': true},
    );
    expect(preferences.values, isEmpty);
    expect(
      (await cache.read(userId: '7', resource: 'qb.submission.42'))!.data,
      {'updated': true},
    );
    await cache.remove(userId: '7', resource: 'qb.submission.42');
    expect(await cache.read(userId: '7', resource: 'qb.submission.42'), isNull);
  });

  test('Full conversation cursor crosses a shared timestamp and last_message uses message_id', () async {
    final repo = ConversationPages();
    final controller = ConversationsController(repository: repo, userId: '7');
    await controller.initialize();
    await controller.loadMore();
    expect(repo.calls, [null, 'opaque:1000:2']);
    expect(controller.items, hasLength(2));
    expect(controller.hasNext, isFalse);
    controller.dispose();
    final item = ConversationItem.fromJson({
      'conversation_id': 10,
      'type': 'DIRECT',
      'display_name': 'Bạn',
      'last_message': {'message_id': 123, 'content': 'Xin chào'},
    });
    expect(item.lastMessageId, '123');
    final transport = ChatRepository(
      api: api,
      cache: JsonCache(MemoryStore()),
      mediaUploadService: MediaUploadService(api),
      stompClient: TestStomp(),
      privateStore: DraftStore(MemoryStore()),
    );
    adapter.respond = (request) async {
      expect(request.queryParameters['cursor'], 'opaque:1000:2');
      expect(request.queryParameters.containsKey('after'), isFalse);
      return response(200, {
        'items': [],
        'next_cursor': 'opaque:1000:1',
        'pagination': {'after': 1000, 'has_next': true},
      });
    };
    expect(
      (await transport.fetchConversations(cursor: 'opaque:1000:2')).nextCursor,
      'opaque:1000:1',
    );
    transport.dispose();
  });

  test('Sender reading their own message is not a partner read receipt', () {
    Map<String, dynamic> message(List<Object> readers) => {
      'message_id': 1,
      'sender_id': 7,
      'content': 'Chào',
      'read_by': readers,
    };
    expect(
      ChatMessage.fromJson(
        message([
          {'user_id': 7},
        ]),
      ).isRead,
      isFalse,
    );
    expect(
      ChatMessage.fromJson(
        message([
          {'user_id': 7},
          {'user_id': 8},
        ]),
      ).isRead,
      isTrue,
    );
  });

  test('Chat rejects renamed GIF, broken PNG and animated PNG/WebP before upload', () async {
    final fixtures = [
      Uint8List.fromList(utf8.encode('GIF89a-not-an-image')),
      Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10, 0]),
      // Generated two-frame 2x2 red/blue fixtures, not a live user attachment.
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAACGFjVEwAAAACAAAAAPONk3AAAAAaZmNUTAAAAAAAAAACAAAAAgAAAAAAAAAAAAEACgAA6FTcAAAAABBJREFUeJxj/M8AAkxgkgEADR0BA4LJcf8AAAAaZmNUTAAAAAEAAAACAAAAAgAAAAAAAAAAAAEACgAAcyc21AAAABZmZEFUAAAAAnicY2Rg+M/AwMDEAAYACx8BAyVgX34AAAAASUVORK5CYII=',
      ),
      base64Decode(
        'UklGRsQAAABXRUJQVlA4WAoAAAACAAAAAQAAAQAAQU5JTQYAAAAAAAAAAABBTk1GSgAAAAAAAAAAAAEAAAEAAGQAAAJWUDggMgAAADABAJ0BKgIAAgABQCYloAADcAD+8ut///mwP/bz/wR6Af//0uD//pcH//S4P/SkAAAAQU5NRkYAAAAAAAAAAAABAAABAABkAAAAVlA4IC4AAAA0AQCdASoCAAIAAAAmJaAAA3AA/vtV4///S4P/+lwf/9Lg/9Lg//rV5Vesq6AA',
      ),
    ];
    for (final bytes in fixtures) {
      await expectLater(
        ChatAttachmentStore.validateBytes(bytes),
        throwsA(isA<AppFailure>()),
      );
    }
  });

  test('Post search uses server full text query and offset pagination, not client filtering', () async {
    adapter.respond = (r) async {
      expect(r.method, 'GET');
      expect(r.path, 'search');
      expect(r.queryParameters, {
        'query': 'đội bóng Nam Việt đá',
        'type': 'POST',
        'after': 20,
        'limit': 20,
      });
      return response(200, {
        'items': [
          {
            'type': 'POST',
            'post': {
              'post_id': 42,
              'content': 'đội bóng Việt Nam đá',
              'author_id': 7,
              'author_name': 'Sinh viên',
            },
          },
        ],
        'pagination': {'after': 40, 'has_next': true},
        'total_hits': 50,
      });
    };
    final result = await PostSearchRepository(api)
        .find(' đội bóng Nam Việt đá ', after: 20, cancel: CancelToken());
    expect(result.items.single.id, 42);
    expect(result.after, 40);
    // Fixtures verify transport. Real word-order matching is backend behavior,
    // not evidence of a live Elasticsearch integration test.
  });

  test('Search ignores late queries, clears blank text, retains same-query data offline and invalidates on logout', () async {
    final repo = ControlledSearch();
    final c = PostSearchController(repository: repo, session: session);
    c.updateQuery('cũ');
    final old = c.search();
    c.updateQuery('mới');
    final current = c.search();
    repo.requests['mới']!.complete(
      const CursorPage(
        [PostSearchResult(42, 'Bài mới', PostAuthor(7, 'Bạn', ''), null)],
        null,
        false,
      ),
    );
    await current;
    repo.requests['cũ']!.complete(const CursorPage([], null, false));
    await old;
    expect(c.items.single.id, 42);
    final retry = c.search();
    repo.requests['mới']!.completeError(AppFailure.offline);
    await retry;
    expect(c.items.single.id, 42);
    expect(c.failure!.kind, FailureKind.offline);
    c.updateQuery('   ');
    expect(c.items, isEmpty);
    expect(c.searched, isFalse);
    c.updateQuery('đang tải');
    final late = c.search();
    await session.clear();
    repo.requests['đang tải']!.complete(const CursorPage([], null, false));
    await late;
    expect(c.active, isFalse);
    expect(c.items, isEmpty);
    c.dispose();
  });
}
