import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:it4788_btl/app/app_dependencies.dart';
import 'package:it4788_btl/app/app_scope.dart';
import 'package:it4788_btl/app/theme/app_theme.dart';
import 'package:it4788_btl/core/config/app_config.dart';
import 'package:it4788_btl/core/errors/app_failure.dart';
import 'package:it4788_btl/core/network/api_client.dart';
import 'package:it4788_btl/core/network/connection_monitor.dart';
import 'package:it4788_btl/core/storage/draft_store.dart';
import 'package:it4788_btl/core/storage/json_cache.dart';
import 'package:it4788_btl/core/storage/session_store.dart';
import 'package:it4788_btl/features/auth/auth_application.dart';
import 'package:it4788_btl/features/relationships/friend_finder_controller.dart';
import 'package:it4788_btl/features/relationships/friend_finder_repository.dart';
import 'package:it4788_btl/features/relationships/friend_finder_screen.dart';
import 'package:it4788_btl/features/relationships/social_state.dart';

import '../../support/fakes.dart';
import '../auth/auth_test.dart' show AuthAdapter, response;
import '../profile/profile_relationships_test.dart'
    show user7, profileJson, statsJson;

Map<String, dynamic> personHit(int id, [String name = 'Nguyễn Bình']) => {
  'type': 'USER',
  'user': {
    'user_id': id,
    'full_name': name,
    'email': 'private@school.edu.vn',
    'student_lecturer_code': 'private-code',
  },
};
Map<String, dynamic> peoplePage(
  List<Object?> items, {
  int? after,
  bool next = false,
}) => {
  'items': items,
  'pagination': {'has_next': next, 'after': after},
};

void main() {
  late AuthAdapter adapter;
  late SessionStore session;
  late FakeConnection connection;
  late ApiClient api;
  late SocialChanges changes;
  late FriendFinderRepository repository;
  late FriendFinderController controller;
  late AppDependencies dependencies;
  late MemoryStore drafts;
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    session = SessionStore(MemoryStore());
    await session.save(user7);
    connection = FakeConnection();
    adapter = AuthAdapter();
    final config = AppConfig();
    api = ApiClient(
      config: config,
      session: session,
      connection: connection,
      dio: Dio()..httpClientAdapter = adapter,
    );
    drafts = MemoryStore();
    dependencies = AppDependencies(
      config: config,
      session: session,
      connection: connection,
      api: api,
      cache: JsonCache(MemoryStore()),
      drafts: DraftStore(drafts),
    );
    changes = SocialChanges(session);
    repository = FriendFinderRepository(api: api, lease: changes.lease());
    controller = FriendFinderController(repository: repository);
    adapter.respond = (_) async => response(200, peoplePage([personHit(8)]));
  });
  tearDown(() {
    controller.dispose();
    changes.dispose();
    dependencies.dispose();
  });
  Future<void> flush() async {
    for (var i = 0; i < 12; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test(
    'Validates before network, always uses USER and never writes history',
    () async {
      connection.change(ConnectionStatus.offline);
      for (final query in ['', '  ', 'a' * 201]) {
        await expectLater(
          repository.find(query, cancelToken: CancelToken()),
          throwsA(
            isA<AppFailure>().having(
              (e) => e.kind,
              'kind',
              FailureKind.rejected,
            ),
          ),
        );
      }
      expect(adapter.requests, isEmpty);
      connection.change(ConnectionStatus.available);
      final page = await repository.find(' Ý ', cancelToken: CancelToken());
      expect(page.items.single.id, '8');
      expect(adapter.requests.single.queryParameters, {
        'query': 'Ý',
        'type': 'USER',
        'limit': 20,
      });
      expect(
        adapter.requests.single.headers['Authorization'],
        'Bearer test-access',
      );
      expect(adapter.requests.single.method, 'GET');
      expect(drafts.values, isEmpty);
    },
  );

  test('Wrong entity type and non-advancing offset are invalid data', () async {
    adapter.respond = (_) async => response(
      200,
      peoplePage([
        {
          'type': 'POST',
          'post': {'post_id': 1},
        },
      ]),
    );
    await expectLater(
      repository.find('An', cancelToken: CancelToken()),
      throwsA(isA<AppFailure>()),
    );
    adapter.respond = (_) async =>
        response(200, peoplePage([personHit(8)], after: 20, next: true));
    await expectLater(
      repository.find('An', offset: 20, cancelToken: CancelToken()),
      throwsA(isA<AppFailure>()),
    );
  });

  testWidgets(
    'Debounce suppresses intermediate input and clearing cancels scheduled GET',
    (tester) async {
      controller.setQuery('Ng');
      await tester.pump(const Duration(milliseconds: 100));
      controller.setQuery('Nguyễn');
      await tester.pump(const Duration(milliseconds: 349));
      expect(adapter.requests, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();
      expect(adapter.requests, hasLength(1));
      controller.setQuery('Bình');
      controller.setQuery('');
      await tester.pump(const Duration(milliseconds: 500));
      expect(controller.people, isEmpty);
      expect(adapter.requests, hasLength(1));
    },
  );

  test('Old responses cannot overwrite a newer query', () async {
    final old = Completer<ResponseBody>();
    adapter.respond = (request) => request.queryParameters['query'] == 'cũ'
        ? old.future
        : Future.value(response(200, peoplePage([personHit(9, 'Mới')])));
    controller.setQuery('cũ');
    final pending = controller.refresh();
    await flush();
    controller.setQuery('mới');
    await controller.refresh();
    old.complete(response(200, peoplePage([personHit(8, 'Cũ')])));
    await pending;
    expect(controller.people.single.name, 'Mới');
    expect(controller.loading, isFalse);
  });

  test(
    'Pages merge by user ID and a repeated offset stops load-more',
    () async {
      adapter.respond = (request) async => response(
        200,
        request.queryParameters['after'] == null
            ? peoplePage([personHit(8)], after: 20, next: true)
            : peoplePage([personHit(8), personHit(9)], after: 40, next: true),
      );
      controller.setQuery('An');
      await controller.refresh();
      await controller.loadMore();
      expect(controller.people.map((person) => person.id), ['8', '9']);
      expect(adapter.requests.last.queryParameters['after'], 20);
      adapter.respond = (_) async =>
          response(200, peoplePage([personHit(10)], after: 40, next: true));
      await controller.loadMore();
      expect(controller.hasNext, isFalse);
      expect(controller.people.map((person) => person.id), ['8', '9']);
    },
  );

  test('Offline refresh retains existing people; new query and permission denial clear them', () async {
    controller.setQuery('An');
    await controller.refresh();
    connection.change(ConnectionStatus.offline);
    await controller.refresh();
    expect(controller.people.single.id, '8');
    expect(controller.loading, isFalse);
    expect(session.hasSession, isTrue);
    connection.change(ConnectionStatus.available);
    adapter.respond = (_) async => response(403, null, code: '9999');
    await controller.refresh();
    expect(controller.people, isEmpty);
    controller.setQuery('Bình');
    expect(controller.people, isEmpty);
  });

  test('Logout/relogin with the same user invalidates old requests', () async {
    final delayed = Completer<ResponseBody>();
    adapter.respond = (_) => delayed.future;
    controller.setQuery('An');
    final pending = controller.refresh();
    await flush();
    await session.clear();
    await session.save(user7);
    delayed.complete(response(200, peoplePage([personHit(8)])));
    await pending;
    expect(repository.active, isFalse);
    expect(controller.people, isEmpty);
  });

  test('Relationship invalidation hides existing people and dispose drops late responses', () async {
    controller.setQuery('An');
    await controller.refresh();
    final delayed = Completer<ResponseBody>();
    adapter.respond = (_) => delayed.future;
    changes.invalidate(blockedUserId: '8');
    expect(controller.people, isEmpty);
    final old = controller;
    old.dispose();
    controller = FriendFinderController(
      repository: FriendFinderRepository(api: api, lease: changes.lease()),
    );
    delayed.complete(response(200, peoplePage([personHit(8)])));
    await flush();
    expect(old.people, isEmpty);
  });

  Widget host(Widget child, {double scale = 1}) => AppScope(
    dependencies: dependencies,
    child: MaterialApp(
      theme: AppTheme.light,
      home: child,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
    ),
  );

  testWidgets(
    'Finder starts without API calls, offers only people and keeps private fields hidden',
    (tester) async {
      await tester.pumpWidget(host(FriendFinderScreen(changes: changes)));
      await tester.pumpAndSettle();
      expect(adapter.requests, isEmpty);
      expect(find.text('Tìm kiếm gần đây'), findsNothing);
      expect(find.text('Bài viết'), findsNothing);
      await tester.enterText(find.byType(TextField), 'Nguyễn');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('Nguyễn Bình'), findsOneWidget);
      expect(find.textContaining('private@'), findsNothing);
      expect(
        adapter.requests.every(
          (r) =>
              r.path == 'search' &&
              r.method == 'GET' &&
              r.queryParameters['type'] == 'USER',
        ),
        isTrue,
      );
      expect(drafts.values, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Small screen/large font keeps the finder scrollable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    adapter.respond = (_) async =>
        response(200, peoplePage([personHit(8, 'Tên rất dài ' * 30)]));
    await tester.pumpWidget(
      host(FriendFinderScreen(changes: changes), scale: 2),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'An');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Friends → find person → profile → request friend uses the existing protected routes',
    (tester) async {
      var friends = false;
      adapter.respond = (request) async {
        if (request.path == 'search') {
          return response(200, peoplePage([personHit(8)]));
        }
        if (request.path == 'friendships') return response(200, peoplePage([]));
        if (request.path == 'users/me') return response(200, profileJson());
        if (request.path == 'users/8') {
          return response(200, profileJson(8)..['full_name'] = 'Nguyễn Bình');
        }
        if (request.path.endsWith('relationship-stats')) {
          return response(200, statsJson(8, friends));
        }
        if (request.path == 'friendships/request') {
          friends = true;
          return response(200, {
            'requester_id': 7,
            'addressee_id': 8,
            'status': 'ACCEPTED',
          });
        }
        throw StateError('Unexpected test endpoint ${request.path}');
      };
      await tester.pumpWidget(AuthApplication(dependencies: dependencies));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bạn bè'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tìm bạn bè'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Nguyễn');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nguyễn Bình'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Kết bạn'));
      await tester.tap(find.text('Kết bạn'));
      await tester.pumpAndSettle();
      expect(
        adapter.requests.where((r) => r.path == 'friendships/request'),
        hasLength(1),
      );
      expect(find.text('Hủy kết bạn'), findsOneWidget);
      expect(adapter.requests.any((r) => r.path == 'search/saved'), isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
