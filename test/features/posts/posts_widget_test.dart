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
import 'package:it4788_btl/features/posts/post_composer_screen.dart';
import 'package:it4788_btl/features/posts/post_models.dart';
import 'package:it4788_btl/features/posts/posts_repository.dart';
import 'package:it4788_btl/features/posts/report_post_screen.dart';

import '../../support/fakes.dart';
import '../auth/auth_test.dart' show AuthAdapter, response;
import 'posts_test.dart' show postJson, pageJson, testSession;

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
        find.text('Nhập nội dung hoặc chọn ảnh/video cho bài viết.'),
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
}
