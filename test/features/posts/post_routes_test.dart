import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:it4788_btl/app/app_dependencies.dart';
import 'package:it4788_btl/app/app_shell.dart';
import 'package:it4788_btl/core/config/app_config.dart';
import 'package:it4788_btl/core/storage/draft_store.dart';
import 'package:it4788_btl/core/storage/json_cache.dart';
import 'package:it4788_btl/core/storage/session_store.dart';
import 'package:it4788_btl/core/network/api_client.dart';
import 'package:it4788_btl/features/auth/auth_application.dart';
import 'package:it4788_btl/features/auth/login_screen.dart';
import 'package:it4788_btl/features/feed/feed_screen.dart';
import 'package:it4788_btl/features/notifications/models/notification_item.dart';
import 'package:it4788_btl/features/notifications/presentation/widgets/notification_deep_link_handler.dart';
import 'package:it4788_btl/features/posts/post_detail_screen.dart';
import 'package:it4788_btl/features/posts/post_routes.dart';
import 'package:it4788_btl/features/question_bank/question_bank_tab.dart';

import '../../support/fakes.dart';
import '../auth/auth_test.dart' show AuthAdapter, response;
import 'posts_test.dart' show postJson, pageJson, testSession;

void main() {
  late AppDependencies dependencies;
  late AuthAdapter adapter;
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    final session = SessionStore(MemoryStore());
    final connection = FakeConnection();
    final config = AppConfig();
    adapter = AuthAdapter();
    adapter.respond = (options) async => response(
      200,
      options.path.endsWith('posts/10') ? postJson() : pageJson([]),
    );
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

  Future<void> mount(WidgetTester tester, {bool signedIn = true}) async {
    if (signedIn) await dependencies.session.save(testSession);
    await tester.pumpWidget(
      AuthApplication(
        dependencies: dependencies,
        tabBuilders: {AppTab.feed: (_) => const FeedScreen()},
        protectedRoutes: PostRoutes.routes,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Merged shell keeps feed and question bank; POST notification opens detail',
    (tester) async {
      await mount(tester);
      expect(find.byType(FeedScreen), findsOneWidget);
      await tester.tap(find.text('Ngân hàng'));
      await tester.pumpAndSettle();
      expect(find.byType(QuestionBankTab), findsOneWidget);
      await tester.tap(find.text('Bảng tin'));
      await tester.pumpAndSettle();
      NotificationDeepLinkHandler.handleTap(
        tester.element(find.byType(FeedScreen)),
        NotificationItem(
          notificationId: 'test-notification',
          type: 'POST_LIKED',
          title: 'Lượt thích',
          body: '',
          createdAt: DateTime(2026, 11, 14),
          target: const NotificationTarget(type: 'POST', id: '10'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PostDetailScreen), findsOneWidget);
      expect(find.text('Xin chào 👋'), findsOneWidget);
      expect(
        adapter.requests.where((r) => r.path.endsWith('posts/10')).length,
        1,
      );
      await dependencies.session.clear();
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(PostDetailScreen), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Invalid post IDs make no request; deleted target shows an error',
    (tester) async {
      await mount(tester);
      final navigator = Navigator.of(tester.element(find.byType(FeedScreen)));
      final requestsBefore = adapter.requests.length;
      for (final arg in [
        null,
        {'postId': '-1'},
        {'postId': 1.5},
        {'postId': 'x'},
        0,
      ]) {
        navigator.pushNamed(PostRoutes.detail, arguments: arg);
        await tester.pumpAndSettle();
        expect(find.text('Bài viết không hợp lệ.'), findsOneWidget);
        expect(adapter.requests.length, requestsBefore);
        navigator.pop();
        await tester.pumpAndSettle();
      }
      adapter.respond = (_) async => response(404, null, code: '2009');
      navigator.pushNamed(PostRoutes.detail, arguments: {'postId': 10});
      await tester.pumpAndSettle();
      expect(find.byType(PostDetailScreen), findsOneWidget);
      expect(find.text('Thích'), findsNothing);
      expect(find.text('Thử lại'), findsOneWidget);
      expect(adapter.requests.last.path, endsWith('posts/10'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Post deep link cannot bypass login', (tester) async {
    await mount(tester, signedIn: false);
    Navigator.of(tester.element(find.byType(LoginScreen)))
        .pushNamed(PostRoutes.detail, arguments: {'postId': '10'});
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(PostDetailScreen), findsNothing);
    expect(adapter.requests, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
