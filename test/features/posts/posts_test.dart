import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:it4788_btl/core/config/app_config.dart';
import 'package:it4788_btl/core/errors/app_failure.dart';
import 'package:it4788_btl/core/network/api_client.dart';
import 'package:it4788_btl/core/network/connection_monitor.dart';
import 'package:it4788_btl/core/storage/draft_store.dart';
import 'package:it4788_btl/core/storage/json_cache.dart';
import 'package:it4788_btl/core/storage/session_store.dart';
import 'package:it4788_btl/features/feed/feed_repository.dart';
import 'package:it4788_btl/features/posts/composer_controller.dart';
import 'package:it4788_btl/features/posts/paged_controller.dart';
import 'package:it4788_btl/features/posts/post_media_service.dart';
import 'package:it4788_btl/features/posts/post_models.dart';
import 'package:it4788_btl/features/posts/posts_repository.dart';

import '../../support/fakes.dart';
import '../auth/auth_test.dart' show AuthAdapter, response;

Map<String, dynamic> postJson([int id = 10]) => {
  'post_id': id,
  'content': 'Xin chào 👋',
  'post_type': 'SOCIAL_POST',
  'visibility': 'PUBLIC',
  'author': {'user_id': 7, 'full_name': 'Sinh viên'},
  'media_urls': [],
  'react_count': 2,
  'comment_count': 0,
  'my_reaction': null,
  'created_at': '2026-11-04T00:00:00Z',
};
Map<String, dynamic> pageJson(
  List<Object?> items, {
  int? after,
  bool next = false,
}) => {
  'items': items,
  'pagination': {'after': after, 'has_next': next},
};
const testSession = SessionTokens(
  userId: '7',
  accessToken: 'test-access',
  refreshToken: 'test-refresh',
);

class BrokenStore extends MemoryStore {
  @override
  Future<void> write(String key, String value) async =>
      throw StateError('Disk full');
}

void main() {
  late AuthAdapter adapter;
  late ApiClient api;
  late SessionStore session;
  late FakeConnection connection;
  late PostsRepository posts;
  setUp(() async {
    adapter = AuthAdapter();
    connection = FakeConnection();
    session = SessionStore(MemoryStore());
    await session.save(testSession);
    api = ApiClient(
      config: AppConfig(),
      session: session,
      connection: connection,
      dio: Dio()..httpClientAdapter = adapter,
    );
    posts = PostsRepository(api);
  });
  tearDown(() {
    api.close();
    session.dispose();
    connection.dispose();
  });
  ComposerController composer(DraftStore store) => ComposerController(
    repository: posts,
    mediaService: PostMediaService(api),
    drafts: store,
    session: session,
  );

  test(
    '500 words including Vietnamese/emojis valid; 501 rejected before offline',
    () async {
      connection.change(ConnectionStatus.offline);
      for (final n in [499, 500]) {
        PostsRepository.validatePost(
          List.filled(n, 'tiếng-Việt👋').join(' \n'),
          [],
        );
      }
      expect(
        () => posts.create(List.filled(501, 'từ').join(' '), []),
        throwsA(
          isA<AppFailure>().having(
            (e) => e.message,
            'message',
            contains('500 từ'),
          ),
        ),
      );
      expect(() => posts.comment(10, ' \n '), throwsA(isA<AppFailure>()));
      expect(adapter.requests, isEmpty);
    },
  );
  test('Media count/type/size/duration boundary validation', () {
    const photo = PostMedia(url: 'https://example.com/a.jpg', type: 'IMAGE');
    const video = PostMedia(url: 'https://example.com/a.mp4', type: 'VIDEO');
    PostsRepository.validatePost('', List.filled(4, photo));
    PostsRepository.validatePost('', [video]);
    expect(
      () => PostsRepository.validatePost('', List.filled(5, photo)),
      throwsA(isA<AppFailure>()),
    );
    expect(
      () => PostsRepository.validatePost('', [photo, video]),
      throwsA(isA<AppFailure>()),
    );
    for (final ms in [1000, 10000]) {
      PostMediaService.validateSizeDuration(
        PostMediaService.videoBytes,
        video: true,
        duration: Duration(milliseconds: ms),
      );
    }
    for (final ms in [999, 10001]) {
      expect(
        () => PostMediaService.validateSizeDuration(
          100,
          video: true,
          duration: Duration(milliseconds: ms),
        ),
        throwsA(isA<AppFailure>()),
      );
    }
    PostMediaService.validateSizeDuration(
      PostMediaService.imageBytes,
      video: false,
    );
    expect(
      () => PostMediaService.validateSizeDuration(
        PostMediaService.imageBytes + 1,
        video: false,
      ),
      throwsA(isA<AppFailure>()),
    );
    expect(
      () => PostMediaService.validateSizeDuration(0, video: false),
      throwsA(isA<AppFailure>()),
    );
  });
  test(
    'Strict IDs/pagination and revoked comment cannot leak hidden content',
    () {
      expect(
        () => Post.fromJson({'post_id': 'not-an-id'}),
        throwsA(isA<AppFailure>()),
      );
      expect(
        () =>
            CursorPage<Post>.fromJson(pageJson([], next: true), Post.fromJson),
        throwsA(isA<AppFailure>()),
      );
      final hidden = PostComment.fromJson({
        'comment_id': 3,
        'content': 'private',
        'author': null,
      });
      expect(hidden.deleted, isTrue);
      expect(hidden.content, isEmpty);
      expect(
        () => PostMedia.fromJson({'url': 'file:///private', 'type': 'IMAGE'}),
        throwsA(isA<AppFailure>()),
      );
    },
  );
  test('Real observed SESSION feed shape maps without treating it as Post or exposing source', () {
    final item = FeedItem.fromJson({
      'feed_id': 115,
      'target_id': 103,
      'target_type': 'SESSION',
      'action_type': 'SESSION_RESOLVED_APPROVED',
      'actor': {'user_id': 164, 'full_name': 'Sinh viên'},
      'content': {
        'title': 'Đã có câu hỏi được chấp nhận!',
        'llm_generated': true,
        'questions': ['private'],
      },
      'created_at': '2026-11-01T17:05:19.210153Z',
    });
    expect(item.post, isNull);
    expect(item.toJson()['content'], {
      'title': 'Đã có câu hỏi được chấp nhận!',
    });
    expect(FeedItem.fromJson(item.toJson()).id, 115);
  });
  test(
    'Deleted feed events never reappear and an empty filtered page can advance',
    () async {
      final removed = <int>[];
      final feed = FeedRepository(api, onPostUnavailable: removed.add);
      Map<String, dynamic> event(int id) => {
        'feed_id': id, 'target_id': id, 'target_type': 'POST',
        'action_type': 'CREATED_POST', 'actor': {'user_id': 7},
        // Even a complete-looking snapshot can outlive its post.
        'content': postJson(id),
      };
      adapter.respond = (request) async {
        if (request.path == 'activity-feeds') {
          final after = request.queryParameters['after'];
          return response(200, switch (after) {
            null => pageJson([event(30)], after: 30, next: true),
            30 => pageJson([event(20)], after: 20, next: true),
            _ => pageJson([event(10)]),
          });
        }
        if (request.path == 'posts/30') {
          return response(404, null, code: '2009');
        }
        if (request.path == 'posts/20') return response(403, null);
        return response(200, postJson(10));
      };
      final controller = PagedController<FeedItem>(
        session: session,
        fetch: feed.fetch,
        id: (e) => e.id,
      );
      addTearDown(controller.dispose);
      await controller.start();
      expect(controller.items, isEmpty);
      expect(controller.hasNext, isTrue);
      await controller.more();
      expect(controller.failure, isNull);
      expect(controller.hasNext, isTrue);
      await controller.more();
      expect(controller.items.single.post!.id, 10);
      expect(controller.hasNext, isFalse);
      expect(removed, [30, 20]);
    },
  );
  test('Post feed with untyped content resolves visibility from detail before caching', () async {
    adapter.respond = (r) async => response(
      200,
      r.path == 'activity-feeds'
          ? pageJson([
              {
                'feed_id': 1,
                'target_id': 10,
                'target_type': 'POST',
                'actor': {'user_id': 7},
                'content': {
                  'text': 'summary',
                  'media_urls': ['https://example.com/a.jpg'],
                },
              },
            ])
          : postJson(),
    );
    final result = await FeedRepository(api).fetch(null, CancelToken());
    expect(result.items.single.post!.visibility, 'PUBLIC');
    expect(adapter.requests.map((e) => e.path), ['activity-feeds', 'posts/10']);
  });
  test(
    'Create/update/delete/like use verified DTOs, no NONE or replay',
    () async {
      adapter.respond = (r) async => response(200, switch (r.path) {
        'posts' => postJson(),
        'react' => {'my_reaction': null, 'total_count': 1},
        _ => {'post_id': 10},
      });
      await posts.create(' Xin chào 👋 ', []);
      expect(adapter.requests.last.data, {
        'content': 'Xin chào 👋',
        'media_urls': [],
        'visibility': 'PUBLIC',
        'post_type': 'SOCIAL_POST',
      });
      await posts.update(10, 'Sửa nội dung', []);
      expect(adapter.requests.last.method, 'PUT');
      final reaction = await posts.like(10);
      expect(reaction.mine, isNull);
      expect((adapter.requests.last.data as Map)['reaction_type'], 'LIKE');
      await posts.delete(10);
      expect(adapter.requests.last.method, 'DELETE');
    },
  );
  test(
    'Video endpoint and new-count use actual paths, page size and milliseconds',
    () async {
      adapter.respond = (r) async => response(
        200,
        r.path == 'video-posts' ? pageJson([]) : {'new_count': 3},
      );
      await posts.videos();
      expect(adapter.requests.last.queryParameters['limit'], 3);
      expect(
        await FeedRepository(api)
            .newCount(DateTime.fromMillisecondsSinceEpoch(1234), CancelToken()),
        3,
      );
      expect(adapter.requests.last.queryParameters['since'], '1234');
    },
  );
  test(
    'HTTP 200 business error and malformed Post are not successful creates',
    () async {
      adapter.respond = (_) async => response(200, postJson(), code: '9999');
      await expectLater(posts.create('Hello', []), throwsA(isA<AppFailure>()));
      adapter.respond = (_) async => response(200, {});
      await expectLater(posts.create('Hello', []), throwsA(isA<AppFailure>()));
    },
  );
  test(
    'Draft survives timeout and restart; submit never replays until reviewed',
    () async {
      final drafts = DraftStore(MemoryStore());
      var c = composer(drafts);
      await c.restore();
      c.changeContent('Bài đang soạn');
      adapter.respond = (r) async => throw DioException(
        requestOptions: r,
        type: DioExceptionType.receiveTimeout,
      );
      expect(await c.submit(), isNull);
      expect(c.uncertain, isTrue);
      await c.submit();
      expect(adapter.requests.length, 1);
      c.dispose();
      c = composer(drafts);
      await c.restore();
      expect(c.content, 'Bài đang soạn');
      expect(c.uncertain, isTrue);
      c.allowRetryAfterReview();
      expect(c.uncertain, isTrue);
      await c.submit();
      expect(adapter.requests.length, 1);
      c.dispose();
    },
  );
  test('Known offline preserves editable draft without sending or invalidating session', () async {
    final c = composer(DraftStore(MemoryStore()));
    await c.restore();
    c.changeContent('Bản nháp');
    connection.change(ConnectionStatus.offline);
    await c.submit();
    expect(c.uncertain, isFalse);
    expect(c.content, 'Bản nháp');
    expect(adapter.requests, isEmpty);
    expect(session.hasSession, isTrue);
    c.dispose();
  });
  test(
    'Storage failure prevents a write without a durable uncertainty marker',
    () async {
      final c = composer(DraftStore(BrokenStore()));
      await c.restore();
      c.changeContent('Nội dung');
      await c.submit();
      expect(adapter.requests, isEmpty);
      expect(c.content, 'Nội dung');
      expect(c.message, contains('Chưa gửi'));
      c.dispose();
    },
  );
  test(
    'Composer blocks double submit; server acknowledgment removes draft',
    () async {
      final drafts = DraftStore(MemoryStore());
      final c = composer(drafts);
      await c.restore();
      c.changeContent('Xin chào 👋');
      final started = Completer<void>(), reply = Completer<ResponseBody>();
      adapter.respond = (_) {
        started.complete();
        return reply.future;
      };
      final first = c.submit();
      await started.future;
      await c.submit();
      expect(adapter.requests.length, 1);
      reply.complete(response(200, postJson()));
      expect(await first, 10);
      expect(await drafts.read(userId: '7', name: 'post/new'), isNull);
      c.dispose();
    },
  );
  test(
    'A create timeout matching an older identical post is not auto-confirmed',
    () async {
      final c = composer(DraftStore(MemoryStore()));
      await c.restore();
      c.changeContent('Xin chào 👋');
      adapter.respond = (r) async => throw DioException(
        requestOptions: r,
        type: DioExceptionType.receiveTimeout,
      );
      await c.submit();
      adapter.respond = (_) async => response(200, pageJson([postJson()]));
      expect(await c.reconcile(), isNull);
      expect(c.reviewed, isTrue);
      expect(c.uncertain, isTrue);
      expect(c.matchesReviewedPost(Post.fromJson(postJson())), isTrue);
      expect(
        c.matchesReviewedPost(
          Post.fromJson({
            ...postJson(),
            'author': {'user_id': 8},
          }),
        ),
        isFalse,
      );
      c.allowRetryAfterReview();
      expect(c.uncertain, isFalse);
      c.dispose();
    },
  );
  test('Draft is isolated when switching accounts', () async {
    final drafts = DraftStore(MemoryStore());
    final a = composer(drafts);
    await a.restore();
    a.changeContent('A private draft');
    await a.save();
    await session.save(
      const SessionTokens(userId: '8', accessToken: 'b', refreshToken: 'br'),
    );
    expect(a.active, isFalse);
    final b = composer(drafts);
    await b.restore();
    expect(b.content, isEmpty);
    a.dispose();
    b.dispose();
  });

  group('Paged cache', () {
    late MemoryStore storage;
    late JsonCache cache;
    PagedController<Post> controller(
      Future<CursorPage<Post>> Function(int?, CancelToken) fetch,
    ) => PagedController(
      session: session,
      fetch: fetch,
      id: (Post p) => p.id,
      cache: cache,
      resource: 'test-feed',
      encode: (p) => p.toJson(),
      decode: Post.fromJson,
      cacheable: (p) => p.visibility == 'PUBLIC',
    );
    setUp(() {
      storage = MemoryStore();
      cache = JsonCache(storage);
    });
    test('Cold offline restores cache; refresh failures preserve it; reconnect replaces it', () async {
      await cache.write(userId: '7', resource: 'test-feed', data: [postJson()]);
      var offline = true;
      final c = controller((_, _) async {
        if (offline) throw AppFailure.offline;
        return CursorPage([Post.fromJson(postJson(11))], null, false);
      });
      await c.start();
      expect(c.items.single.id, 10);
      expect(c.cached, isTrue);
      expect(c.busy, isFalse);
      await c.refresh();
      expect(c.items.single.id, 10);
      offline = false;
      await c.refresh();
      expect(c.items.single.id, 11);
      expect(c.cached, isFalse);
      c.dispose();
    });
    test('403 clears RAM and persisted cache; malformed refresh keeps useful old data', () async {
      await cache.write(userId: '7', resource: 'test-feed', data: [postJson()]);
      AppFailure failure = AppFailure.invalidData;
      final c = controller((_, _) async => throw failure);
      await c.start();
      expect(c.items.length, 1);
      failure = const AppFailure(FailureKind.forbidden, 'No permission');
      await c.refresh();
      expect(c.items, isEmpty);
      expect(await cache.read(userId: '7', resource: 'test-feed'), isNull);
      c.dispose();
    });
    test('Pagination deduplicates; repeated cursor cannot loop; refresh/load-more serialized', () async {
      var calls = 0;
      final c = controller((after, _) async {
        calls++;
        return after == null
            ? CursorPage([Post.fromJson(postJson())], 10, true)
            : CursorPage(
                [Post.fromJson(postJson()), Post.fromJson(postJson(9))],
                9,
                true,
              );
      });
      await c.start();
      await c.more();
      expect(c.items.map((p) => p.id), [10, 9]);
      await c.more();
      expect(c.hasNext, isFalse);
      expect(c.failure!.kind, FailureKind.invalidData);
      await c.more();
      expect(calls, 3);
      c.dispose();
    });
    test('In-flight page cannot resurrect deletion or overwrite freshly confirmed like', () async {
      final c = controller(
        (_, _) async => CursorPage(
          [Post.fromJson(postJson()), Post.fromJson(postJson(11))],
          null,
          false,
        ),
      );
      await c.start();
      c.dispose();
      final gate = Completer<CursorPage<Post>>();
      var calls = 0;
      final d = controller((_, _) async {
        if (++calls == 1) {
          return CursorPage(
            [Post.fromJson(postJson()), Post.fromJson(postJson(11))],
            null,
            false,
          );
        }
        return gate.future;
      });
      await d.start();
      final refresh = d.refresh();
      d.removeWhere((p) => p.id == 10);
      d.replaceWhere(
        (p) => p.id == 11,
        (p) => p.withReaction(const Reaction('LIKE', 3)),
      );
      gate.complete(
        CursorPage(
          [Post.fromJson(postJson()), Post.fromJson(postJson(11))],
          null,
          false,
        ),
      );
      await refresh;
      expect(d.items.single.id, 11);
      expect(d.items.single.liked, isTrue);
      d.dispose();
    });
    test(
      'Logout during request drops late response and does not write cache',
      () async {
        final gate = Completer<CursorPage<Post>>();
        final started = Completer<void>();
        final c = controller((_, _) {
          started.complete();
          return gate.future;
        });
        final load = c.start();
        await started.future;
        await session.clear();
        gate.complete(CursorPage([Post.fromJson(postJson())], null, false));
        await load;
        expect(c.items, isEmpty);
        expect(await cache.read(userId: '7', resource: 'test-feed'), isNull);
        c.dispose();
      },
    );
    test(
      'Private posts excluded from disk and cache bounded to 40 records',
      () async {
        final c = controller(
          (_, _) async => CursorPage(
            [
              Post.fromJson({...postJson(500), 'visibility': 'ONLY_ME'}),
              ...List.generate(60, (i) => Post.fromJson(postJson(i + 1))),
            ],
            null,
            false,
          ),
        );
        await c.start();
        final saved =
            (await cache.read(userId: '7', resource: 'test-feed'))!.data
                as List;
        expect(saved.length, 40);
        expect(saved.any((p) => (p as Map)['visibility'] != 'PUBLIC'), isFalse);
        c.dispose();
      },
    );
    test(
      'Cache write failure does not turn successful fetch into an API failure',
      () async {
        cache = JsonCache(BrokenStore());
        final c = controller(
          (_, _) async => CursorPage([Post.fromJson(postJson())], null, false),
        );
        await c.start();
        expect(c.items.length, 1);
        expect(c.failure, isNull);
        expect(c.storageWarning, isNotNull);
        c.dispose();
      },
    );
  });
}
