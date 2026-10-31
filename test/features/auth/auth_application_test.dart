import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:it4788_btl/app/app_dependencies.dart';
import 'package:it4788_btl/app/app_shell.dart';
import 'package:it4788_btl/core/config/app_config.dart';
import 'package:it4788_btl/core/network/api_client.dart';
import 'package:it4788_btl/core/storage/draft_store.dart';
import 'package:it4788_btl/core/storage/json_cache.dart';
import 'package:it4788_btl/core/storage/session_store.dart';
import 'package:it4788_btl/features/auth/auth_application.dart';
import 'package:it4788_btl/features/auth/login_screen.dart';
import 'package:it4788_btl/features/settings/change_password_screen.dart';

import '../../support/fakes.dart';
import 'auth_test.dart' show AuthAdapter, response;

void main() {
  testWidgets(
    'Login → settings → change password → logout removes protected stack',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final session = SessionStore(MemoryStore());
      final connection = FakeConnection();
      final adapter = AuthAdapter();
      final config = AppConfig();
      final api = ApiClient(
        config: config,
        session: session,
        connection: connection,
        dio: Dio()..httpClientAdapter = adapter,
      );
      final dependencies = AppDependencies(
        config: config,
        session: session,
        connection: connection,
        cache: JsonCache(MemoryStore()),
        drafts: DraftStore(MemoryStore()),
        api: api,
      );
      await tester.pumpWidget(AuthApplication(dependencies: dependencies));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      final loginFields = find.byType(TextFormField);
      await tester.enterText(loginFields.at(0), 'student@school.edu.vn');
      await tester.enterText(loginFields.at(1), 'test-password');
      await tester.ensureVisible(find.byType(FilledButton));
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(find.byType(AppShell), findsOneWidget);
      await tester.tap(find.text('Cá nhân'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Đổi mật khẩu'));
      await tester.pumpAndSettle();
      expect(find.byType(ChangePasswordScreen), findsOneWidget);
      adapter.respond = (_) async => response(200, null);
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'test-password');
      await tester.enterText(fields.at(1), 'next-password');
      await tester.enterText(fields.at(2), 'next-password');
      await tester.ensureVisible(find.byType(FilledButton));
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(find.byType(ChangePasswordScreen), findsNothing);
      expect(find.text('Đổi mật khẩu thành công.'), findsOneWidget);
      expect(adapter.requests.last.uri.path, '/api/v1/auth/change-password');
      await tester.tap(find.text('Đăng xuất'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Đăng xuất'));
      await tester.pumpAndSettle();
      expect(session.hasSession, isFalse);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(AppShell), findsNothing);
      expect(adapter.requests.last.uri.path, '/api/v1/auth/logout');
      expect(adapter.requests.last.data, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      dependencies.dispose();
    },
  );
}
