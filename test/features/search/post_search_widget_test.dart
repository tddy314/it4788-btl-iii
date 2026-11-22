import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:it4788_btl/app/app_dependencies.dart';
import 'package:it4788_btl/app/app_scope.dart';
import 'package:it4788_btl/app/theme/app_theme.dart';
import 'package:it4788_btl/core/config/app_config.dart';
import 'package:it4788_btl/core/network/api_client.dart';
import 'package:it4788_btl/core/storage/draft_store.dart';
import 'package:it4788_btl/core/storage/json_cache.dart';
import 'package:it4788_btl/core/storage/session_store.dart';
import 'package:it4788_btl/features/posts/post_routes.dart';
import 'package:it4788_btl/features/search/post_search_screen.dart';

import '../../support/fakes.dart';
import '../auth/auth_test.dart' show AuthAdapter, response;

void main() {
  testWidgets(
    'Post search fits a small screen with large font and opens a deleted result safely',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = SessionStore(MemoryStore());
      await session.save(
        const SessionTokens(
          userId: '7',
          accessToken: 'test-access',
          refreshToken: 'test-refresh',
        ),
      );
      final connection = FakeConnection();
      final adapter = AuthAdapter()
        ..respond = (r) async {
          if (r.path == 'search') {
            return response(200, {
              'items': [
                {
                  'type': 'POST',
                  'post': {
                    'post_id': 42,
                    'content': 'đội bóng Việt Nam đá',
                    'author_name': 'Sinh viên',
                  },
                },
              ],
              'pagination': {'after': null, 'has_next': false},
            });
          }
          return response(404, null, code: '9999');
        };
      final config = AppConfig();
      final deps = AppDependencies(
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
      addTearDown(deps.dispose);
      await tester.pumpWidget(
        AppScope(
          dependencies: deps,
          child: MaterialApp(
            theme: AppTheme.light,
            routes: PostRoutes.routes,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(1.6),
                viewInsets: const EdgeInsets.only(bottom: 180),
              ),
              child: child!,
            ),
            home: const PostSearchScreen(),
          ),
        ),
      );
      await tester.enterText(
        find.byType(TextFormField),
        'đội bóng Nam Việt đá',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.textContaining('đội bóng Việt Nam đá'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.textContaining('đội bóng Việt Nam đá'));
      await tester.pumpAndSettle();
      expect(find.textContaining('không còn tồn tại'), findsWidgets);
      expect(adapter.requests.where((r) => r.path == 'posts/42'), hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
