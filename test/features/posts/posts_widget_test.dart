import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:it4788_btl/app/app_dependencies.dart';
import 'package:it4788_btl/app/app_scope.dart';
import 'package:it4788_btl/app/theme/app_theme.dart';
import 'package:it4788_btl/core/config/app_config.dart';
import 'package:it4788_btl/core/network/api_client.dart';
import 'package:it4788_btl/core/network/connection_monitor.dart';
import 'package:it4788_btl/core/storage/draft_store.dart';
import 'package:it4788_btl/core/storage/json_cache.dart';
import 'package:it4788_btl/core/storage/session_store.dart';
import 'package:it4788_btl/features/feed/feed_repository.dart';
import 'package:it4788_btl/features/feed/feed_screen.dart';
import 'package:it4788_btl/features/posts/comments_screen.dart';
import 'package:it4788_btl/features/posts/post_card.dart';
import 'package:it4788_btl/features/posts/post_detail_screen.dart';
import 'package:it4788_btl/features/posts/post_composer_screen.dart';
import 'package:it4788_btl/features/posts/post_models.dart';
import 'package:it4788_btl/features/posts/posts_repository.dart';
import 'package:it4788_btl/features/posts/report_post_screen.dart';

import '../../support/fakes.dart';
import '../auth/auth_test.dart' show AuthAdapter, response;
import 'posts_test.dart' show postJson, pageJson, testSession;

class _RouteObserver extends NavigatorObserver {
  int pushes = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
    super.didPush(route, previousRoute);
  }
}

void main() {
  setUpAll(() => WidgetController.hitTestWarningShouldBeFatal = true);
  tearDownAll(() => WidgetController.hitTestWarningShouldBeFatal = false);
  late AppDependencies dependencies;
  late AuthAdapter adapter;
  late FakeConnection connection;

  setUp(() async {
    adapter = AuthAdapter();
    connection = FakeConnection();
    final session = SessionStore(MemoryStore());
    await session.save(testSession);
    final config = AppConfig();
    dependencies = AppDependencies(
      config: config,
      session: session,
      connection: connection,
      cache: JsonCache(MemoryStore()),
      drafts: DraftStore(MemoryStore()),
      api: ApiClient(
        config: config,
        session: session,
        connection: connection,
        dio: Dio()..httpClientAdapter = adapter,
      ),
    );
  });
  tearDown(() => dependencies.dispose());
  Widget host(Widget child, {double scale = 1, double keyboard = 0}) =>
      AppScope(
        dependencies: dependencies,
        child: MaterialApp(
          theme: AppTheme.light,
          builder: (context, page) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              viewInsets: EdgeInsets.only(bottom: keyboard),
            ),
            child: page!,
          ),
          home: child,
        ),
      );
  void small(WidgetTester tester) {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget likeCard({Post? post, ValueChanged<Post>? changed}) => host(
    Scaffold(
      body: PostCard(
        post: post ?? Post.fromJson(postJson()),
        repository: PostsRepository(dependencies.api),
        onChanged: changed ?? (_) {},
        onUnavailable: () {},
      ),
    ),
  );

  testWidgets(
    'Comments sheet leaves the post scrollable and opens no new route',
    (tester) async {
      final observer = _RouteObserver();
      final postScroll = ScrollController();
      adapter.respond = (r) async =>
          response(200, r.path == 'comments' ? pageJson([]) : postJson());
      await tester.pumpWidget(
        AppScope(
          dependencies: dependencies,
          child: MaterialApp(
            theme: AppTheme.light,
            navigatorObservers: [observer],
            home: Scaffold(
              body: ListView(
                controller: postScroll,
                children: [
                  PostCard(
                    post: Post.fromJson(postJson()),
                    repository: PostsRepository(dependencies.api),
                    onChanged: (_) {},
                    onUnavailable: () {},
                  ),
                  const SizedBox(height: 1200),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Bình luận'));
      await tester.pumpAndSettle();
      expect(find.byType(CommentsScreen), findsOneWidget);
      expect(find.text('Xin chào 👋'), findsOneWidget);
      final rect = tester.getRect(find.byType(CommentsScreen));
      expect(rect.top, greaterThan(0));
      expect(rect.height, lessThan(tester.view.physicalSize.height));
      expect(observer.pushes, 1);
      await tester.dragFrom(const Offset(150, 70), const Offset(0, -45));
      await tester.pumpAndSettle();
      expect(postScroll.offset, greaterThan(0));
      expect(find.byType(CommentsScreen), findsOneWidget);
      await tester.tap(find.byTooltip('Đóng bình luận'));
      await tester.pumpAndSettle();
      expect(find.byType(CommentsScreen), findsNothing);
      expect(observer.pushes, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      postScroll.dispose();
    },
  );

  testWidgets(
    'Detail comments fit large font and keyboard; closing and Back preserve the draft',
    (tester) async {
      small(tester);
      adapter.respond = (r) async =>
          response(200, r.path == 'comments' ? pageJson([]) : postJson());
      await tester.pumpWidget(
        host(const PostDetailScreen(id: 10), scale: 1.4, keyboard: 220),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Bình luận'));
      await tester.tap(find.text('Bình luận'));
      await tester.pumpAndSettle();
      expect(find.byType(CommentsScreen), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Nháp trong cửa sổ');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Đóng bình luận'));
      await tester.pumpAndSettle();
      expect(find.byType(PostDetailScreen), findsOneWidget);
      await tester.ensureVisible(find.text('Bình luận'));
      await tester.tap(find.text('Bình luận'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Nháp trong cửa sổ',
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(CommentsScreen), findsNothing);
      expect(find.byType(PostDetailScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Replies stay inline, preserve separate drafts and submit to the selected parent',
    (tester) async {
      final parent = {
        'comment_id': 101,
        'content': 'Bình luận cha',
        'reply_count': 1,
        'author': {'user_id': 8, 'full_name': 'Bạn cùng lớp'},
      };
      final reply = {
        'comment_id': 102,
        'content': 'Phản hồi trước',
        'author': {'user_id': 8, 'full_name': 'Bạn cùng lớp'},
      };
      final sent = {
        'comment_id': 103,
        'content': 'Phản hồi của tôi',
        'author': {'user_id': 7, 'full_name': 'Sinh viên'},
      };
      var posted = false;
      adapter.respond = (r) async {
        if (r.method == 'POST') {
          posted = true;
          expect((r.data as Map)['parent_comment_id'], 101);
          return response(200, sent);
        }
        return response(
          200,
          pageJson(
            r.queryParameters['parent_comment_id'] == 101
                ? [if (posted) sent, reply]
                : [parent],
          ),
        );
      };
      await tester.pumpWidget(host(const CommentsScreen(postId: 10)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Nháp bình luận gốc');
      await tester.tap(find.byKey(const ValueKey('reply-101')));
      await tester.pumpAndSettle();
      expect(find.byType(CommentsScreen), findsOneWidget);
      expect(find.text('Bình luận cha'), findsOneWidget);
      expect(find.text('Phản hồi trước'), findsOneWidget);
      expect(find.text('Đang trả lời Bạn cùng lớp'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Nháp phản hồi');
      await tester.tap(find.byTooltip('Hủy trả lời'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Nháp bình luận gốc',
      );
      await tester.tap(find.byKey(const ValueKey('reply-101')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Nháp phản hồi',
      );
      await tester.enterText(find.byType(TextField), 'Phản hồi của tôi');
      await tester.tap(find.text('Gửi bình luận'));
      await tester.pumpAndSettle();
      expect(find.text('Phản hồi của tôi'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('reply-101')),
          matching: find.text('Phản hồi (2)'),
        ),
        findsOneWidget,
      );
      expect(find.byType(CommentsScreen), findsOneWidget);
      expect(adapter.requests.where((r) => r.method == 'POST'), hasLength(1));
      expect(
        (await dependencies.drafts.read(
          userId: '7',
          name: 'comment/10/root',
        ))!['content'],
        'Nháp bình luận gốc',
      );
      expect(
        (await dependencies.drafts.read(
          userId: '7',
          name: 'comment/10/101',
        ))!['content'],
        '',
      );
    },
  );

  for (final paged in [false, true]) {
    testWidgets('Deleting a reply updates its parent count (paged=$paged)', (
      tester,
    ) async {
      final parent = {
        'comment_id': 101,
        'content': 'Bình luận cha',
        'reply_count': paged ? 4 : 1,
        'author': {'user_id': 8, 'full_name': 'Bạn cùng lớp'},
      };
      final reply = {
        'comment_id': 102,
        'content': 'Phản hồi sẽ xóa',
        'author': {'user_id': 7, 'full_name': 'Sinh viên'},
      };
      final deletion = Completer<ResponseBody>();
      adapter.respond = (r) async {
        if (r.method == 'DELETE') return deletion.future;
        return response(
          200,
          r.queryParameters['parent_comment_id'] == 101
              ? pageJson([reply], next: paged, after: paged ? 102 : null)
              : pageJson([parent]),
        );
      };
      await tester.pumpWidget(host(const CommentsScreen(postId: 10)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('reply-101')));
      await tester.pumpAndSettle();
      final counter = find.descendant(
        of: find.byKey(const ValueKey('reply-101')),
        matching: find.byType(Text),
      );
      expect(tester.widget<Text>(counter).data, 'Phản hồi (${paged ? 4 : 1})');
      await tester.tap(find.byTooltip('Xóa bình luận'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xóa'));
      await tester.pump();
      expect(tester.widget<Text>(counter).data, 'Phản hồi (${paged ? 4 : 1})');
      deletion.complete(response(200, null));
      await tester.pumpAndSettle();
      expect(find.text('Phản hồi sẽ xóa'), findsNothing);
      expect(tester.widget<Text>(counter).data, 'Phản hồi (${paged ? 3 : 0})');
    });
  }

  testWidgets(
    'A complete reply list excludes deleted placeholders from count',
    (tester) async {
      adapter.respond = (r) async => response(
        200,
        pageJson(
          r.queryParameters['parent_comment_id'] == 101
              ? [
                  {'comment_id': 102, 'deleted': true},
                ]
              : [
                  {
                    'comment_id': 101,
                    'content': 'Bình luận cha',
                    'reply_count': 1,
                    'author': {'user_id': 8, 'full_name': 'Bạn cùng lớp'},
                  },
                ],
        ),
      );
      await tester.pumpWidget(host(const CommentsScreen(postId: 10)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('reply-101')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('reply-101')),
          matching: find.text('Phản hồi (0)'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'A timed-out inline reply keeps its draft and checking uses its thread only',
    (tester) async {
      final parent = {
        'comment_id': 101,
        'content': 'Bình luận cha',
        'author': {'user_id': 8, 'full_name': 'Bạn cùng lớp'},
      };
      adapter.respond = (r) async {
        if (r.method == 'POST') {
          throw DioException(
            requestOptions: r,
            type: DioExceptionType.receiveTimeout,
          );
        }
        return response(
          200,
          pageJson(
            r.queryParameters['parent_comment_id'] == 101 ? [] : [parent],
          ),
        );
      };
      await tester.pumpWidget(host(const CommentsScreen(postId: 10)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('reply-101')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Giữ nháp phản hồi');
      await tester.tap(find.text('Gửi bình luận'));
      await tester.pumpAndSettle();
      expect(find.text('Chưa xác nhận được'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('replies-101')),
          matching: find.byKey(const ValueKey('pending-comment')),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Tải lại để kiểm tra'));
      await tester.pumpAndSettle();
      expect(adapter.requests.last.queryParameters['parent_comment_id'], 101);
      expect(adapter.requests.where((r) => r.method == 'POST'), hasLength(1));
      expect(
        (await dependencies.drafts.read(
          userId: '7',
          name: 'comment/10/101',
        ))!['uncertain'],
        true,
      );
    },
  );

  testWidgets(
    'Like is immediate during slow GET, blocks repeats and uses server count',
    (tester) async {
      final get = Completer<ResponseBody>();
      final write = Completer<ResponseBody>();
      Post? saved;
      adapter.respond = (r) => r.method == 'GET' ? get.future : write.future;
      await tester.pumpWidget(likeCard(changed: (p) => saved = p));
      await tester.tap(find.text('Thích'));
      await tester.pump();
      expect(find.text('Đã thích'), findsOneWidget);
      expect(find.text('3 lượt thích'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(saved, isNull);
      await tester.tap(find.text('Đã thích'), warnIfMissed: false);
      await tester.pump();
      // Dio can still be scheduling its first request at this frame.
      expect(adapter.requests.length, lessThanOrEqualTo(1));
      get.complete(response(200, postJson()));
      await tester.pumpAndSettle();
      expect(find.text('Đã thích'), findsOneWidget);
      expect(saved, isNull);
      write.complete(response(200, {'my_reaction': 'LIKE', 'total_count': 8}));
      await tester.pumpAndSettle();
      expect(find.text('8 lượt thích'), findsOneWidget);
      expect(saved!.reactCount, 8);
      expect(adapter.requests.where((r) => r.method == 'POST'), hasLength(1));
      expect(adapter.requests.where((r) => r.method == 'GET'), hasLength(1));
    },
  );

  testWidgets('Unlike is immediate and a rejected toggle rolls back', (
    tester,
  ) async {
    final write = Completer<ResponseBody>();
    final original = Post.fromJson({
      ...postJson(),
      'my_reaction': 'LIKE',
      'react_count': 2,
    });
    adapter.respond = (r) async =>
        r.method == 'GET' ? response(200, original.toJson()) : write.future;
    await tester.pumpWidget(likeCard(post: original));
    await tester.tap(find.text('Đã thích'));
    await tester.pumpAndSettle();
    expect(find.text('Thích'), findsOneWidget);
    expect(find.text('1 lượt thích'), findsOneWidget);
    write.complete(response(400, null));
    await tester.pumpAndSettle();
    expect(find.text('Đã thích'), findsOneWidget);
    expect(find.text('2 lượt thích'), findsOneWidget);
  });

  testWidgets(
    'Like timeout only reads on checking, even after a failed check',
    (tester) async {
      var rejectRead = false;
      adapter.respond = (r) async {
        if (r.method == 'POST' || rejectRead) {
          throw DioException(
            requestOptions: r,
            type: DioExceptionType.receiveTimeout,
          );
        }
        return response(200, postJson());
      };
      await tester.pumpWidget(likeCard());
      await tester.tap(find.text('Thích'));
      await tester.pumpAndSettle();
      expect(find.text('Kiểm tra lượt thích'), findsOneWidget);
      rejectRead = true;
      await tester.tap(find.text('Kiểm tra lượt thích'));
      await tester.pumpAndSettle();
      expect(find.text('Kiểm tra lượt thích'), findsOneWidget);
      rejectRead = false;
      await tester.tap(find.text('Kiểm tra lượt thích'));
      await tester.pumpAndSettle();
      expect(find.text('Thích'), findsOneWidget);
      expect(adapter.requests.where((r) => r.method == 'POST'), hasLength(1));
    },
  );

  testWidgets('Offline Like keeps its state and sends nothing', (tester) async {
    connection.change(ConnectionStatus.offline);
    await tester.pumpWidget(likeCard());
    await tester.tap(find.text('Thích'));
    await tester.pumpAndSettle();
    expect(find.text('Thích'), findsOneWidget);
    expect(find.text('2 lượt thích'), findsOneWidget);
    expect(adapter.requests, isEmpty);
  });

  testWidgets(
    'Late Like read cannot toggle a different post after a card is reused',
    (tester) async {
      final read = Completer<ResponseBody>();
      final changes = <Post>[];
      adapter.respond = (_) => read.future;
      await tester.pumpWidget(likeCard(changed: changes.add));
      await tester.tap(find.text('Thích'));
      await tester.pump();
      await tester.pumpWidget(
        likeCard(post: Post.fromJson(postJson(11)), changed: changes.add),
      );
      read.complete(response(200, postJson()));
      await tester.pumpAndSettle();
      expect(changes, isEmpty);
      expect(adapter.requests.where((r) => r.method == 'POST'), isEmpty);
      expect(find.text('Thích'), findsOneWidget);
      expect(find.text('2 lượt thích'), findsOneWidget);
    },
  );

  testWidgets(
    'Comment appears while POST waits; confirmed ID replaces it without duplicates',
    (tester) async {
      final write = Completer<ResponseBody>();
      var sent = false;
      final comment = {
        'comment_id': 41,
        'content': 'Bình luận nhanh',
        'author': {'user_id': 7, 'full_name': 'Sinh viên'},
      };
      adapter.respond = (r) async {
        if (r.method == 'POST') {
          sent = true;
          return write.future;
        }
        return response(200, pageJson(sent ? [comment] : []));
      };
      await tester.pumpWidget(host(const CommentsScreen(postId: 10)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Bình luận nhanh');
      await tester.tap(find.text('Gửi bình luận'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pending-comment')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('pending-comment')),
          matching: find.text('Bình luận nhanh'),
        ),
        findsOneWidget,
      );
      expect(find.text('Đã gửi bình luận.'), findsNothing);
      expect(
        (await dependencies.drafts.read(
          userId: '7',
          name: 'comment/10/root',
        ))!['content'],
        'Bình luận nhanh',
      );
      write.complete(response(200, comment));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pending-comment')), findsNothing);
      expect(find.text('Bình luận nhanh'), findsOneWidget);
      expect(find.text('Đã gửi bình luận.'), findsOneWidget);
      expect(adapter.requests.where((r) => r.method == 'POST'), hasLength(1));
    },
  );

  testWidgets(
    'Rejected comment keeps text and failed card; editing removes stale preview',
    (tester) async {
      adapter.respond = (r) async => r.method == 'POST'
          ? response(400, null)
          : response(200, pageJson([]));
      await tester.pumpWidget(host(const CommentsScreen(postId: 10)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Giữ nội dung');
      await tester.tap(find.text('Gửi bình luận'));
      await tester.pumpAndSettle();
      expect(find.text('Gửi thất bại'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Giữ nội dung',
      );
      expect(find.text('Đã gửi bình luận.'), findsNothing);
      await tester.enterText(find.byType(TextField), 'Đã sửa');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pending-comment')), findsNothing);
      expect(adapter.requests.where((r) => r.method == 'POST'), hasLength(1));
    },
  );

  testWidgets(
    'Unknown comment survives reopening without replay and stays distinct from server results',
    (tester) async {
      adapter.respond = (r) async {
        if (r.method == 'POST') {
          throw DioException(
            requestOptions: r,
            type: DioExceptionType.receiveTimeout,
          );
        }
        return response(200, pageJson([]));
      };
      await tester.pumpWidget(host(const CommentsScreen(postId: 10)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Chưa rõ kết quả');
      await tester.tap(find.text('Gửi bình luận'));
      await tester.pumpAndSettle();
      expect(find.text('Chưa xác nhận được'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      connection.change(ConnectionStatus.offline);
      await tester.pumpWidget(host(const CommentsScreen(postId: 10)));
      await tester.pumpAndSettle();
      expect(find.text('Chưa xác nhận được'), findsOneWidget);
      expect(find.byKey(const ValueKey('pending-comment')), findsOneWidget);
      expect(adapter.requests.where((r) => r.method == 'POST'), hasLength(1));
    },
  );

  testWidgets(
    'Confirmed comment remains visible if refresh loses the network',
    (tester) async {
      var sent = false;
      adapter.respond = (r) async {
        if (r.method == 'POST') {
          sent = true;
          return response(200, {
            'comment_id': 42,
            'content': 'Đã lưu ở server',
            'author': {'user_id': 7, 'full_name': 'Sinh viên'},
          });
        }
        if (sent) {
          throw DioException(
            requestOptions: r,
            type: DioExceptionType.receiveTimeout,
          );
        }
        return response(200, pageJson([]));
      };
      await tester.pumpWidget(host(const CommentsScreen(postId: 10)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Đã lưu ở server');
      await tester.tap(find.text('Gửi bình luận'));
      await tester.pumpAndSettle();
      expect(find.text('Đã lưu ở server'), findsOneWidget);
      expect(find.byKey(const ValueKey('pending-comment')), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
    },
  );

  testWidgets(
    'Cached home remains visible after offline refresh on small screen',
    (tester) async {
      small(tester);
      final item = FeedItem.fromJson({
        'feed_id': 10,
        'target_type': 'POST',
        'target_id': 10,
        'action_type': 'CREATED_POST',
        'actor': {'user_id': 7, 'full_name': 'Sinh viên'},
        'content': postJson(),
        'created_at': '2026-11-04T00:00:00Z',
      });
      await dependencies.cache.write(
        userId: '7',
        resource: 'feed/home-v1',
        data: [item.toJson()],
      );
      connection.change(ConnectionStatus.offline);
      await tester.pumpWidget(
        host(
          Scaffold(
            appBar: AppBar(title: const Text('SQB')),
            body: const FeedScreen(),
          ),
          scale: 1.3,
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Xin chào 👋'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Xin chào 👋'), findsOneWidget);
      expect(adapter.requests, isEmpty);
      await tester.scrollUntilVisible(
        find.text('Thử lại'),
        -180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Thử lại'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Xin chào 👋'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Xin chào 👋'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'Cached like reconciles a previously accepted write without toggling it off',
    (tester) async {
      adapter.respond = (_) async => response(200, {
        ...postJson(),
        'my_reaction': 'LIKE',
        'react_count': 3,
      });
      Post? result;
      await tester.pumpWidget(
        host(
          Scaffold(
            body: PostCard(
              post: Post.fromJson(postJson()),
              repository: PostsRepository(dependencies.api),
              onChanged: (p) => result = p,
              onUnavailable: () {},
            ),
          ),
        ),
      );
      await tester.tap(find.text('Thích'));
      await tester.pumpAndSettle();
      expect(result!.liked, isTrue);
      expect(adapter.requests.length, 1);
      expect(adapter.requests.single.method, 'GET');
      expect(find.text('Đã thích'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'Composer validates before offline, keeps text and fits large font/keyboard',
    (tester) async {
      small(tester);
      connection.change(ConnectionStatus.offline);
      await tester.pumpWidget(
        host(const PostComposerScreen(), scale: 1.4, keyboard: 220),
      );
      await tester.pumpAndSettle();
      expect(find.text('Chọn video'), findsNothing);
      expect(find.text('Quay video'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Đăng bài'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await Scrollable.ensureVisible(
        tester.element(find.widgetWithText(FilledButton, 'Đăng bài')),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Đăng bài'));
      await tester.pumpAndSettle();
      expect(
        find.text('Nhập nội dung hoặc chọn ảnh cho bài viết.'),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.byType(TextField),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(find.byType(TextField), 'Bản nháp tiếng Việt 👋');
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Đăng bài'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await Scrollable.ensureVisible(
        tester.element(find.widgetWithText(FilledButton, 'Đăng bài')),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Đăng bài'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Không thể kết nối mạng. Vui lòng kiểm tra kết nối và thử lại.',
        ),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.byType(TextField),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Bản nháp tiếng Việt 👋'), findsOneWidget);
      expect(adapter.requests, isEmpty);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'Comments preserve offline draft and show validation with keyboard/large font',
    (tester) async {
      small(tester);
      connection.change(ConnectionStatus.offline);
      await tester.pumpWidget(
        host(const CommentsScreen(postId: 10), scale: 1.4, keyboard: 220),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gửi bình luận'));
      await tester.pumpAndSettle();
      expect(find.text('Vui lòng nhập đầy đủ thông tin.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Bình luận chưa gửi');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gửi bình luận'));
      await tester.pumpAndSettle();
      expect(adapter.requests, isEmpty);
      expect(find.text('Bình luận chưa gửi'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'Comment acknowledged once; newest server page appears and draft clears',
    (tester) async {
      var sent = false;
      final comment = {
        'comment_id': 4,
        'content': 'Ý kiến mới',
        'author': {'user_id': 7, 'full_name': 'Sinh viên'},
      };
      adapter.respond = (r) async {
        if (r.method == 'POST') {
          sent = true;
          return response(200, comment);
        }
        return response(200, pageJson(sent ? [comment] : []));
      };
      await tester.pumpWidget(host(const CommentsScreen(postId: 10)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Ý kiến mới');
      await tester.tap(find.text('Gửi bình luận'));
      await tester.pumpAndSettle();
      expect(adapter.requests.where((r) => r.method == 'POST').length, 1);
      expect(find.text('Ý kiến mới'), findsOneWidget);
      expect(find.text('Đã gửi bình luận.'), findsOneWidget);
      expect(
        (await dependencies.drafts.read(
          userId: '7',
          name: 'comment/10/root',
        ))!['content'],
        '',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'Reporting offline does not send or leave a false unknown-result lock',
    (tester) async {
      connection.change(ConnectionStatus.offline);
      await tester.pumpWidget(host(const ReportPostScreen(postId: 10)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gửi báo cáo'));
      await tester.pumpAndSettle();
      expect(adapter.requests, isEmpty);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Gửi báo cáo'),
      );
      expect(button.onPressed, isNotNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'A lost comment response with emotes can be reviewed and closed without sending twice',
    (tester) async {
      var sent = false;
      final comment = {
        'comment_id': 4,
        'content': 'Chào 😊 https://example.com/a',
        'author': {'user_id': 7, 'full_name': 'Sinh viên'},
        'created_at': '2026-11-17T10:00:00Z',
      };
      adapter.respond = (r) async {
        if (r.method == 'POST') {
          sent = true;
          throw DioException(
            requestOptions: r,
            type: DioExceptionType.receiveTimeout,
          );
        }
        return response(200, pageJson(sent ? [comment] : []));
      };
      await tester.pumpWidget(host(const CommentsScreen(postId: 10)));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'Chào :) https://example.com/a',
      );
      await tester.tap(find.text('Gửi bình luận'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tải lại để kiểm tra'));
      await tester.pumpAndSettle();
      expect(find.text('Đã thấy bình luận, đóng bản nháp'), findsOneWidget);
      await tester.tap(find.text('Đã thấy bình luận, đóng bản nháp'));
      await tester.pumpAndSettle();
      expect(
        (await dependencies.drafts.read(
          userId: '7',
          name: 'comment/10/root',
        ))?['content'],
        '',
      );
      expect(adapter.requests.where((r) => r.method == 'POST'), hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
