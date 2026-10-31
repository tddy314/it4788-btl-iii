import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:it4788_btl/core/config/app_config.dart';
import 'package:it4788_btl/core/errors/app_failure.dart';
import 'package:it4788_btl/core/network/api_client.dart';
import 'package:it4788_btl/core/network/connection_monitor.dart';
import 'package:it4788_btl/core/storage/session_store.dart';

import '../support/fakes.dart';

class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.respond);
  final Future<ResponseBody> Function(RequestOptions) respond;
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requests.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody reply(int status, Object? data, {String code = '1000'}) =>
    ResponseBody.fromString(
      jsonEncode({'code': code, 'message': '', 'data': data}),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

void main() {
  late SessionStore session;
  late FakeConnection connection;
  final clients = <ApiClient>[];
  setUp(() async {
    session = SessionStore(MemoryStore());
    connection = FakeConnection();
    await session.save(
      const SessionTokens(
        userId: 'a',
        accessToken: 'old',
        refreshToken: 'refresh',
      ),
    );
  });
  tearDown(() {
    for (final client in clients) {
      client.close();
    }
    clients.clear();
    session.dispose();
    connection.dispose();
  });
  ApiClient clientFor(FakeAdapter adapter) {
    final dio = Dio()..httpClientAdapter = adapter;
    final api = ApiClient(
      config: AppConfig(),
      session: session,
      connection: connection,
      dio: dio,
    );
    clients.add(api);
    return api;
  }

  test(
    'Live backend success code 1000 is accepted; unrelated code is rejected',
    () async {
      final adapter = FakeAdapter(
        (_) async => reply(200, {'ok': true}, code: '1000'),
      );
      final api = clientFor(adapter);
      expect(await api.get('items', decode: (v) => v), {'ok': true});
      final outdated = clientFor(
        FakeAdapter((_) async => reply(200, null, code: '0000')),
      );
      await expectLater(
        outdated.get('items', decode: (v) => v),
        throwsA(isA<AppFailure>().having((e) => e.code, 'code', '0000')),
      );
    },
  );

  test(
    'Uses API prefix and Bearer token without treating data as raw response',
    () async {
      final adapter = FakeAdapter((_) async => reply(200, ['one']));
      final api = clientFor(adapter);
      expect(await api.get('/items', decode: (v) => v), ['one']);
      expect(adapter.requests.single.uri.path, '/api/v1/items');
      expect(adapter.requests.single.headers['Authorization'], 'Bearer old');
    },
  );

  test(
    'Offline fails promptly and never deletes session or calls adapter',
    () async {
      final adapter = FakeAdapter((_) async => reply(200, []));
      final api = clientFor(adapter);
      connection.change(ConnectionStatus.offline);
      await expectLater(
        api.get('items', decode: (v) => v),
        throwsA(
          isA<AppFailure>().having((e) => e.kind, 'kind', FailureKind.offline),
        ),
      );
      expect(adapter.requests, isEmpty);
      expect(session.hasSession, isTrue);
    },
  );

  test('Wi-Fi without Internet still maps transport failure', () async {
    final adapter = FakeAdapter(
      (options) async => throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      ),
    );
    final api = clientFor(adapter);
    await expectLater(
      api.get('items', decode: (v) => v),
      throwsA(
        isA<AppFailure>().having((e) => e.kind, 'kind', FailureKind.offline),
      ),
    );
    expect(adapter.requests.length, 1);
    expect(session.hasSession, isTrue);
  });

  test(
    'Malformed response and business error are not reported as success',
    () async {
      final adapter = FakeAdapter((_) async => reply(200, [], code: '2003'));
      await expectLater(
        clientFor(adapter).get('items', decode: (v) => v),
        throwsA(isA<AppFailure>().having((e) => e.code, 'code', '2003')),
      );
      final malformed = FakeAdapter(
        (_) async => ResponseBody.fromString(
          '{}',
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        ),
      );
      await expectLater(
        clientFor(malformed).get('items', decode: (v) => v),
        throwsA(
          isA<AppFailure>().having(
            (e) => e.kind,
            'kind',
            FailureKind.invalidData,
          ),
        ),
      );
    },
  );

  test('Concurrent unauthorized GETs share refresh and retry once', () async {
    final adapter = FakeAdapter(
      (options) async => options.headers['Authorization'] == 'Bearer old'
          ? reply(401, null, code: '9998')
          : reply(200, ['ok']),
    );
    final api = clientFor(adapter);
    var refreshes = 0;
    api.refreshTokens = (_) async {
      refreshes++;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      return const SessionTokens(
        userId: 'a',
        accessToken: 'new',
        refreshToken: 'next',
      );
    };
    final results = await Future.wait([
      api.get('first', decode: (v) => v),
      api.get('second', decode: (v) => v),
    ]);
    expect(results, [
      ['ok'],
      ['ok'],
    ]);
    expect(refreshes, 1);
    expect(adapter.requests.length, 4);
  });

  test('POST timeout is never automatically replayed', () async {
    final adapter = FakeAdapter(
      (options) async => throw DioException(
        requestOptions: options,
        type: DioExceptionType.receiveTimeout,
      ),
    );
    final api = clientFor(adapter);
    await expectLater(
      api.request(
        'items',
        method: 'POST',
        data: {'text': 'draft'},
        decode: (v) => v,
      ),
      throwsA(
        isA<AppFailure>().having((e) => e.kind, 'kind', FailureKind.timeout),
      ),
    );
    expect(adapter.requests.length, 1);
  });

  test('Refresh failure from network preserves session', () async {
    final adapter = FakeAdapter((_) async => reply(401, null, code: '9998'));
    final api = clientFor(adapter)
      ..refreshTokens = (_) async => throw AppFailure.offline;
    await expectLater(
      api.get('items', decode: (v) => v),
      throwsA(isA<AppFailure>()),
    );
    expect(session.hasSession, isTrue);
    expect(adapter.requests.length, 1);
  });

  test('Response received after logout is discarded', () async {
    final done = Completer<ResponseBody>();
    final started = Completer<void>();
    final api = clientFor(
      FakeAdapter((_) {
        started.complete();
        return done.future;
      }),
    );
    final request = api.get('items', decode: (v) => v);
    final check = expectLater(
      request,
      throwsA(
        isA<AppFailure>().having(
          (e) => e.kind,
          'kind',
          FailureKind.unauthorized,
        ),
      ),
    );
    await started.future;
    await session.clear();
    done.complete(reply(200, ['private']));
    await check;
  });
}
