import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:it4788_btl/app/theme/app_theme.dart';
import 'package:it4788_btl/core/config/app_config.dart';
import 'package:it4788_btl/core/errors/app_failure.dart';
import 'package:it4788_btl/core/network/api_client.dart';
import 'package:it4788_btl/core/network/connection_monitor.dart';
import 'package:it4788_btl/core/storage/session_store.dart';
import 'package:it4788_btl/features/auth/auth_controller.dart';
import 'package:it4788_btl/features/auth/auth_repository.dart';
import 'package:it4788_btl/features/auth/auth_validation.dart';
import 'package:it4788_btl/features/auth/device_identity.dart';
import 'package:it4788_btl/features/auth/login_screen.dart';
import 'package:it4788_btl/features/settings/change_password_screen.dart';

import '../../support/fakes.dart';

class AuthAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  Future<ResponseBody> Function(RequestOptions)? respond;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return respond != null
        ? respond!(options)
        : response(200, {
            'user_id': 7,
            'access_token': 'test-access',
            'refresh_token': 'test-refresh',
          });
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody response(int status, Object? data, {String code = '1000'}) =>
    ResponseBody.fromString(
      jsonEncode({'code': code, 'data': data}),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

void main() {
  late AuthAdapter adapter;
  late ApiClient api;
  late SessionStore session;
  late FakeConnection connection;
  late AuthRepository repository;
  late AuthController auth;
  late MemoryStore deviceStore;
  setUp(() {
    adapter = AuthAdapter();
    session = SessionStore(MemoryStore());
    connection = FakeConnection();
    deviceStore = MemoryStore();
    api = ApiClient(
      config: AppConfig(),
      session: session,
      connection: connection,
      dio: Dio()..httpClientAdapter = adapter,
    );
    repository = AuthRepository(api: api, device: DeviceIdentity(deviceStore));
    auth = AuthController(repository: repository, session: session);
    api.refreshTokens = auth.refresh;
  });
  tearDown(() {
    auth.dispose();
    api.close();
    session.dispose();
    connection.dispose();
  });

  test('Login validates before network, does not trim password and reuses installation ID', () async {
    connection.change(ConnectionStatus.offline);
    await auth.login('bad', '');
    expect(auth.message, 'Email không đúng định dạng.');
    expect(adapter.requests, isEmpty);
    connection.change(ConnectionStatus.available);
    await auth.login(' student@school.edu.vn ', ' supplied password ');
    expect(session.tokens?.userId, '7');
    final body = adapter.requests.single.data as Map;
    expect(body['email'], 'student@school.edu.vn');
    expect(body['password'], ' supplied password ');
    expect(body['platform'], 'ANDROID');
    expect(
      adapter.requests.single.headers.containsKey('Authorization'),
      isFalse,
    );
    final second = DeviceIdentity(deviceStore);
    expect(await second.getId(), body['device_id']);
  });

  test('Only one login is submitted while busy', () async {
    final done = Completer<ResponseBody>();
    final started = Completer<void>();
    adapter.respond = (_) {
      started.complete();
      return done.future;
    };
    final first = auth.login('student@school.edu.vn', 'password');
    await started.future;
    await auth.login('student@school.edu.vn', 'password');
    expect(adapter.requests.length, 1);
    done.complete(
      response(200, {'user_id': 7, 'access_token': 'a', 'refresh_token': 'r'}),
    );
    await first;
    expect(auth.busy, isFalse);
  });

  test(
    'Login 400, locked account and malformed success do not create a session',
    () async {
      adapter.respond = (_) async => response(400, null, code: 'test-invalid');
      await auth.login('student@school.edu.vn', 'password');
      expect(auth.message, contains('Email hoặc mật khẩu'));
      expect(session.hasSession, isFalse);
      adapter.respond = (_) async => response(403, null);
      await auth.login('student@school.edu.vn', 'password');
      expect(auth.message, contains('liên hệ giảng viên'));
      adapter.respond = (_) async => response(200, {'user_id': 7});
      await auth.login('student@school.edu.vn', 'password');
      expect(session.hasSession, isFalse);
      expect(auth.message, AppFailure.invalidData.message);
    },
  );

  test(
    'Offline login is not successful; restored session stays usable offline',
    () async {
      connection.change(ConnectionStatus.offline);
      await auth.login('student@school.edu.vn', 'password');
      expect(session.hasSession, isFalse);
      expect(auth.busy, isFalse);
      expect(auth.message, AppFailure.offline.message);
      await session.save(
        const SessionTokens(userId: '7', accessToken: 'a', refreshToken: 'r'),
      );
      await expectLater(
        auth.refresh(session.tokens!),
        throwsA(isA<AppFailure>()),
      );
      expect(session.hasSession, isTrue);
    },
  );

  test(
    'Server rejected refresh clears session; transport errors do not',
    () async {
      await auth.login('student@school.edu.vn', 'password');
      adapter.respond = (_) async => response(401, null, code: '9998');
      await expectLater(
        auth.refresh(session.tokens!),
        throwsA(isA<AppFailure>()),
      );
      expect(session.hasSession, isFalse);
      expect(auth.message, contains('đăng nhập lại'));
    },
  );

  test(
    'Refresh posts only refresh token and produces new pair for same user',
    () async {
      adapter.respond = (_) async =>
          response(200, {'access_token': 'new', 'refresh_token': 'next'});
      final next = await repository.refresh(
        const SessionTokens(
          userId: '7',
          accessToken: 'old',
          refreshToken: 'refresh',
        ),
      );
      expect(next.userId, '7');
      expect(next.accessToken, 'new');
      expect(adapter.requests.single.data, {'refresh_token': 'refresh'});
      expect(
        adapter.requests.single.headers.containsKey('Authorization'),
        isFalse,
      );
    },
  );

  test(
    'Offline logout clears local tokens without pretending server confirmed',
    () async {
      await auth.login('student@school.edu.vn', 'password');
      connection.change(ConnectionStatus.offline);
      await auth.logout();
      expect(session.hasSession, isFalse);
      expect(auth.message, contains('Chưa xác nhận'));
      expect(adapter.requests.length, 1);
    },
  );

  test(
    'Password change sends exact payload, no replay after timeout',
    () async {
      await auth.login('student@school.edu.vn', 'password');
      adapter.respond = (options) async => throw DioException(
        requestOptions: options,
        type: DioExceptionType.receiveTimeout,
      );
      await expectLater(
        repository.changePassword(' old ', ' new '),
        throwsA(
          isA<AppFailure>().having((e) => e.kind, 'kind', FailureKind.timeout),
        ),
      );
      expect(adapter.requests.last.data, {
        'old_password': ' old ',
        'new_password': ' new ',
      });
      expect(adapter.requests.length, 2);
    },
  );

  test(
    'Password validation does not impose an invented special-character rule',
    () {
      expect(AuthValidation.password('Pass@123'), isNull);
      expect(AuthValidation.newPassword('same', 'same'), isNotNull);
    },
  );

  testWidgets(
    'Login errors preserve fields; no overflow on small screen and large font',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      connection.change(ConnectionStatus.offline);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: LoginScreen(auth: auth),
        ),
      );
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'student@school.edu.vn');
      await tester.enterText(fields.at(1), 'password');
      final submit = find.byType(FilledButton);
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(find.text(AppFailure.offline.message), findsOneWidget);
      expect(
        tester.widget<TextFormField>(fields.at(0)).controller!.text,
        'student@school.edu.vn',
      );
      expect(
        tester.widget<TextFormField>(fields.at(1)).controller!.text,
        'password',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Mismatched confirmation prevents API call while offline', (
    tester,
  ) async {
    connection.change(ConnectionStatus.offline);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ChangePasswordScreen(repository: repository),
      ),
    );
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'old');
    await tester.enterText(fields.at(1), 'new');
    await tester.enterText(fields.at(2), 'different');
    await tester.ensureVisible(find.byType(FilledButton));
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(find.text('Mật khẩu xác nhận không khớp.'), findsOneWidget);
    expect(adapter.requests, isEmpty);
  });
}
