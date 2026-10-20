import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:it4788_btl/app/app.dart';
import 'package:it4788_btl/app/app_dependencies.dart';
import 'package:it4788_btl/app/app_shell.dart';
import 'package:it4788_btl/core/config/app_config.dart';
import 'package:it4788_btl/core/network/api_client.dart';
import 'package:it4788_btl/core/network/connection_monitor.dart';
import 'package:it4788_btl/core/storage/json_cache.dart';
import 'package:it4788_btl/core/storage/draft_store.dart';
import 'package:it4788_btl/core/storage/session_store.dart';
import 'package:it4788_btl/core/widgets/app_button.dart';

import 'support/fakes.dart';

void main() {
  late AppDependencies dependencies;
  late FakeConnection connection;
  setUp(() {
    final config = AppConfig();
    final session = SessionStore(MemoryStore());
    connection = FakeConnection();
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
        dio: Dio(),
      ),
    );
  });
  tearDown(() => dependencies.dispose());

  testWidgets('Signed out users cannot enter the shell; locale is Vietnamese', (
    tester,
  ) async {
    await tester.pumpWidget(SqbApp(dependencies: dependencies));
    await tester.pumpAndSettle();
    expect(find.text('Đăng nhập'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    final context = tester.element(find.text('Đăng nhập'));
    expect(Localizations.localeOf(context).languageCode, 'vi');
    Navigator.of(context).pushNamed('/protected');
    await tester.pumpAndSettle();
    expect(find.byType(AppShell), findsNothing);
  });

  testWidgets(
    'Session changes reset protected routes; offline keeps shell open',
    (tester) async {
      await dependencies.session.save(
        const SessionTokens(
          userId: 'a',
          accessToken: 'access',
          refreshToken: 'refresh',
        ),
      );
      await tester.pumpWidget(
        SqbApp(
          dependencies: dependencies,
          tabBuilders: {AppTab.feed: (_) => const Text('Nội dung đã lưu')},
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Nội dung đã lưu'), findsOneWidget);
      connection.change(ConnectionStatus.offline);
      await tester.pumpAndSettle();
      expect(find.textContaining('Không có kết nối mạng'), findsOneWidget);
      expect(find.text('Nội dung đã lưu'), findsOneWidget);
      expect(dependencies.session.hasSession, isTrue);
      await dependencies.session.clear();
      await tester.pumpAndSettle();
      expect(find.byType(AppShell), findsNothing);
      expect(find.text('Đăng nhập'), findsOneWidget);
    },
  );

  testWidgets('Busy button cannot submit a second time', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppButton(
            label: 'Gửi',
            isLoading: true,
            onPressed: () => calls++,
          ),
        ),
      ),
    );
    await tester.tap(find.byType(FilledButton));
    expect(calls, 0);
  });
}
