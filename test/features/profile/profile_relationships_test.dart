import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
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
import 'package:it4788_btl/features/profile/edit_profile_screen.dart';
import 'package:it4788_btl/features/profile/profile_controller.dart';
import 'package:it4788_btl/features/profile/profile_models.dart';
import 'package:it4788_btl/features/profile/profile_repository.dart';
import 'package:it4788_btl/features/profile/profile_screen.dart';
import 'package:it4788_btl/features/relationships/relationships_screen.dart';
import 'package:it4788_btl/features/relationships/social_models.dart';
import 'package:it4788_btl/features/relationships/social_repository.dart';
import 'package:it4788_btl/features/relationships/social_state.dart';

import '../../support/fakes.dart';
import '../auth/auth_test.dart' show AuthAdapter, response;

const user7 = SessionTokens(
  userId: '7',
  accessToken: 'test-access',
  refreshToken: 'test-refresh',
);
Map<String, dynamic> profileJson([int id = 7]) => {
  'user_id': id,
  'full_name': 'Nguyễn Văn An',
  'bio': 'Sinh viên',
  'role': 'STUDENT',
  'email': 'private@school.edu.vn',
  'date_of_birth': '2004-08-05',
  'student_lecturer_code': 'private-code',
  'timezone': 'Asia/Ho_Chi_Minh',
};
Map<String, dynamic> statsJson([int id = 8, bool friend = false]) => {
  'user_id': id,
  'counts': {'friends_count': 1, 'followers_count': 2, 'following_count': 0},
  'relationship_with_me': {
    'friend': friend,
    'following': false,
    'blocked': false,
    'followed_by': false,
    'friend_request_status': friend ? 'ACCEPTED' : 'NONE',
  },
};
Map<String, dynamic> pageJson(
  List<Object?> items, {
  int? after,
  bool next = false,
}) => {
  'items': items,
  'pagination': {'after': after, 'has_next': next},
};

void main() {
  late AuthAdapter adapter;
  late SessionStore session;
  late FakeConnection connection;
  late ApiClient api;
  late SocialChanges changes;
  late SocialRepository social;
  late ProfileRepository profile;
  late MemoryStore cacheStore;
  late MemoryStore draftStore;
  late AppDependencies dependencies;

  setUp(() async {
    adapter = AuthAdapter();
    session = SessionStore(MemoryStore());
    await session.save(user7);
    connection = FakeConnection();
    final config = AppConfig();
    api = ApiClient(
      config: config,
      session: session,
      connection: connection,
      dio: Dio()..httpClientAdapter = adapter,
    );
    changes = SocialChanges(session);
    social = SocialRepository(api: api, lease: changes.lease());
    profile = ProfileRepository(social);
    cacheStore = MemoryStore();
    draftStore = MemoryStore();
    dependencies = AppDependencies(
      config: config,
      session: session,
      connection: connection,
      api: api,
      cache: JsonCache(cacheStore),
      drafts: DraftStore(draftStore),
    );
    adapter.respond = (request) async {
      if (request.path.endsWith('relationship-stats')) {
        return response(200, statsJson(request.path.contains('/7/') ? 7 : 8));
      }
      if (request.path == 'users/me') return response(200, profileJson());
      if (request.path == 'users/8') return response(200, profileJson(8));
      return response(200, pageJson([]));
    };
  });
  tearDown(() {
    social.dispose();
    changes.dispose();
    dependencies.dispose();
  });

  test('Request DTOs preserve received/sent direction; malformed pages fail closed', () {
    expect(
      RelationshipList.received.decode({
        'requester': {'user_id': 8},
      }).id,
      '8',
    );
    expect(
      RelationshipList.sent.decode({
        'receiver': {'user_id': 9},
      }).id,
      '9',
    );
    expect(
      () => RelationshipList.received.decode({
        'receiver': {'user_id': 9},
      }),
      throwsA(isA<AppFailure>()),
    );
    expect(
      () => SocialPage<SocialPerson>.decode(
        pageJson([], next: true),
        SocialPerson.fromJson,
      ),
      throwsA(isA<AppFailure>()),
    );
    final unknown = statsJson();
    (unknown['relationship_with_me'] as Map).remove('following');
    expect(RelationshipStats.fromJson(unknown).isFollowing, isNull);
  });

  test('Validation happens before network; 100/500 Unicode code points and invalid dates', () async {
    connection.change(ConnectionStatus.offline);
    await expectLater(
      profile.update(const ProfileInput({'full_name': '  '})),
      throwsA(
        isA<AppFailure>().having((e) => e.kind, 'kind', FailureKind.rejected),
      ),
    );
    expect(adapter.requests, isEmpty);
    expect(
      ProfileInput({'full_name': '😀' * 100, 'bio': 'a' * 500}).validate(),
      isNull,
    );
    expect(ProfileInput({'full_name': 'a' * 101}).validate(), isNotNull);
    expect(
      ProfileInput({'full_name': 'An', 'bio': 'a' * 501}).validate(),
      isNotNull,
    );
    expect(
      const ProfileInput({'full_name': 'An', 'date_of_birth': '2004-02-30'})
          .validate(),
      isNotNull,
    );
  });

  test('PUT only edited permitted fields; does not overwrite concurrent unrelated changes', () async {
    adapter.respond = (request) async {
      final current = profileJson()..['bio'] = 'Tiểu sử cập nhật từ máy khác';
      if (request.method == 'PUT') {
        expect(request.data, {'full_name': 'Tên mới'});
        return response(200, current..['full_name'] = 'Tên mới');
      }
      return response(200, current);
    };
    final result = await profile.update(
      const ProfileInput(
        {
          'full_name': 'Tên mới',
          'bio': 'Sinh viên',
          'email': 'cannot-edit@x.vn',
        },
        changedKeys: {'full_name', 'email'},
      ),
    );
    expect(result.name, 'Tên mới');
    expect(result.text('bio'), 'Tiểu sử cập nhật từ máy khác');
    expect(adapter.requests.map((r) => r.method), ['GET', 'PUT']);
  });

  test(
    'A lost PUT response is reconciled by GET before user tries again',
    () async {
      var current = profileJson();
      adapter.respond = (request) async {
        if (request.method == 'PUT') {
          current = {...current, ...request.data as Map<String, dynamic>};
          throw DioException(
            requestOptions: request,
            type: DioExceptionType.receiveTimeout,
          );
        }
        return response(200, current);
      };
      const input = ProfileInput(
        {'full_name': 'Tên mới'},
        changedKeys: {'full_name'},
      );
      await expectLater(profile.update(input), throwsA(isA<AppFailure>()));
      expect((await profile.update(input)).name, 'Tên mới');
      expect(adapter.requests.where((r) => r.method == 'PUT'), hasLength(1));
    },
  );

  test('Friend request accepts server ACCEPTED and rejects cross-role requests before POST', () async {
    adapter.respond = (request) async {
      if (request.path.endsWith('relationship-stats')) {
        return response(200, statsJson());
      }
      if (request.path == 'users/me') return response(200, profileJson());
      if (request.path == 'users/8') return response(200, profileJson(8));
      expect(request.data, {'addressee_id': 8});
      return response(200, {
        'requester_id': 8,
        'addressee_id': 7,
        'status': 'ACCEPTED',
      });
    };
    await social.change(SocialAction.request, '8');
    final before = adapter.requests.length;
    adapter.respond = (request) async {
      if (request.path.endsWith('relationship-stats')) {
        return response(200, statsJson());
      }
      return response(
        200,
        profileJson(request.path == 'users/me' ? 7 : 8)
          ..['role'] = request.path == 'users/me' ? 'STUDENT' : 'LECTURER',
      );
    };
    await expectLater(
      social.change(SocialAction.request, '8'),
      throwsA(isA<AppFailure>()),
    );
    expect(
      adapter.requests.skip(before).any((r) => r.method == 'POST'),
      isFalse,
    );
  });

  test('Accept checks received list using requester ID; second attempt does not repeat POST', () async {
    var accepted = false;
    adapter.respond = (request) async {
      if (request.path.endsWith('relationship-stats')) {
        return response(200, statsJson(8, accepted));
      }
      if (request.path.endsWith('/received')) {
        return response(
          200,
          pageJson([
            {
              'requester': {'user_id': 8, 'full_name': 'Bình'},
            },
          ]),
        );
      }
      expect(request.path, 'friendships/accept');
      expect(request.data, {'requester_id': 8});
      accepted = true;
      throw DioException(
        requestOptions: request,
        type: DioExceptionType.receiveTimeout,
      );
    };
    await expectLater(
      social.change(SocialAction.accept, '8'),
      throwsA(isA<AppFailure>()),
    );
    await social.change(SocialAction.accept, '8');
    expect(adapter.requests.where((r) => r.method == 'POST'), hasLength(1));
  });

  test(
    'Self-interaction and unknown permissions never cause a write',
    () async {
      await expectLater(
        social.change(SocialAction.follow, '7'),
        throwsA(isA<AppFailure>()),
      );
      expect(adapter.requests, isEmpty);
      adapter.respond = (_) async => response(
        200,
        statsJson()..['relationship_with_me'] = {'following': null},
      );
      await expectLater(
        social.change(SocialAction.follow, '8'),
        throwsA(isA<AppFailure>()),
      );
      expect(adapter.requests.every((r) => r.method == 'GET'), isTrue);
    },
  );

  test('Block uses own blocked list, validates confirmation and does not restore friendship on unblock', () async {
    var blocked = false;
    adapter.respond = (request) async {
      if (request.path == 'blocks') {
        return response(
          200,
          pageJson(
            blocked
                ? [
                    {'user_id': 8},
                  ]
                : [],
          ),
        );
      }
      expect(request.path, 'blocks/8');
      blocked = request.method == 'POST';
      return response(200, {
        blocked ? 'blocked_user_id' : 'unblocked_user_id': 8,
        'blocked': blocked,
      });
    };
    await social.change(SocialAction.block, '8');
    await social.change(SocialAction.block, '8');
    await social.change(SocialAction.unblock, '8');
    expect(
      adapter.requests.where((r) => r.method != 'GET').map((r) => r.method),
      ['POST', 'DELETE'],
    );
  });

  test('Account switch, including logout/login same ID, invalidates old feature lease', () async {
    final delayed = Completer<ResponseBody>();
    adapter.respond = (_) => delayed.future;
    final pending = profile.profile('7');
    final rejected = expectLater(pending, throwsA(isA<AppFailure>()));
    await Future<void>.delayed(Duration.zero);
    await session.clear();
    await session.save(user7);
    delayed.complete(response(200, profileJson()));
    await rejected;
    expect(social.lease.active, isFalse);
    expect(social.cancel.isCancelled, isTrue);
  });

  test(
    'Mutation lock prevents double taps and releases after errors',
    () async {
      final pending = Completer<void>();
      final first = changes.mutate(() => pending.future);
      var called = false;
      expect(
        await changes.mutate(() async {
          called = true;
        }),
        isFalse,
      );
      expect(called, isFalse);
      pending.completeError(AppFailure.offline);
      await expectLater(first, throwsA(isA<AppFailure>()));
      expect(changes.busy, isFalse);
      expect(changes.lastMutationConfirmed, isFalse);
    },
  );

  test('Profile cache is public-only, restores offline, and hides on permission denial', () async {
    final controller = ProfileController(
      repository: profile,
      cache: dependencies.cache,
      id: '7',
    );
    await controller.load();
    final stored = cacheStore.values.values.single;
    expect(stored, isNot(contains('private@')));
    expect(stored, isNot(contains('private-code')));
    expect(stored, isNot(contains('date_of_birth')));
    controller.dispose();
    connection.change(ConnectionStatus.offline);
    final offline = ProfileController(
      repository: profile,
      cache: dependencies.cache,
      id: '7',
    );
    await offline.load();
    expect(offline.profile!.name, 'Nguyễn Văn An');
    expect(offline.fromCache, isTrue);
    expect(offline.writable, isFalse);
    connection.change(ConnectionStatus.available);
    adapter.respond = (_) async => response(403, null, code: '9999');
    await offline.load();
    expect(offline.profile, isNull);
    expect(cacheStore.values, isEmpty);
    expect(session.hasSession, isTrue);
    offline.dispose();
  });

  test('Pagination deduplicates, keeps rows offline and rejects non-advancing cursor', () async {
    var calls = 0;
    final controller = SocialListController<String>(
      lease: changes.lease(),
      idOf: (x) => x,
      fetch: (_) async => ++calls == 1
          ? const SocialPage(items: ['a', 'b'], hasNext: true, after: 10)
          : const SocialPage(items: ['b', 'c'], hasNext: true, after: 10),
    );
    await controller.load();
    await controller.load(more: true);
    expect(controller.hasNext, isFalse);
    expect(controller.items, ['a', 'b']);
    expect(controller.failure, isNotNull);
    controller.dispose();
    var offline = false;
    final stable = SocialListController<String>(
      lease: changes.lease(),
      idOf: (x) => x,
      fetch: (_) async {
        if (offline) throw AppFailure.offline;
        return const SocialPage(items: ['a'], hasNext: false);
      },
    );
    await stable.load();
    offline = true;
    await stable.load();
    expect(stable.items, ['a']);
    expect(stable.loading, isFalse);
    stable.dispose();
  });

  test('Invalidation drops an older page even when it finishes after a new refresh', () async {
    final delayed = Completer<SocialPage<String>>();
    var calls = 0;
    final controller = SocialListController<String>(
      lease: changes.lease(),
      idOf: (x) => x,
      fetch: (_) => ++calls == 1
          ? delayed.future
          : Future.value(const SocialPage(items: ['new'], hasNext: false)),
    );
    final old = controller.load();
    controller.clear();
    await controller.load();
    delayed.complete(const SocialPage(items: ['old'], hasNext: false));
    await old;
    expect(controller.items, ['new']);
    controller.dispose();
  });

  test('Disposing controllers drops late responses', () async {
    final delayed = Completer<SocialPage<String>>();
    final controller = SocialListController<String>(
      lease: changes.lease(),
      idOf: (x) => x,
      fetch: (_) => delayed.future,
    );
    final pending = controller.load();
    controller.dispose();
    delayed.complete(const SocialPage(items: ['late'], hasNext: false));
    await pending;
    expect(controller.items, isEmpty);
  });

  Widget host(Widget child, {double scale = 1}) => AppScope(
    dependencies: dependencies,
    child: MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: child,
    ),
  );

  testWidgets(
    'Other profile never displays private fields, including malformed backend disclosure',
    (tester) async {
      await tester.pumpWidget(
        host(ProfileScreen(changes: changes, userId: '8')),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('private@'), findsNothing);
      expect(find.textContaining('private-code'), findsNothing);
      expect(find.text('Kết bạn'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Profile on small screen with large font stays scrollable and opens editor',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(host(ProfileScreen(changes: changes), scale: 2));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Chỉnh sửa hồ sơ'),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chỉnh sửa hồ sơ'));
      await tester.pumpAndSettle();
      expect(find.byType(EditProfileScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Editor persists account-scoped draft on leave and keeps input when save fails',
    (tester) async {
      await tester.pumpWidget(
        host(
          EditProfileScreen(
            profile: UserProfile.fromJson(profileJson()),
            changes: changes,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final nameController = tester
          .widget<TextField>(find.byType(TextField).first)
          .controller!;
      await tester.enterText(find.byType(TextField).first, 'Bản nháp của An');
      await tester.pump(const Duration(milliseconds: 600));
      connection.change(ConnectionStatus.offline);
      await tester.scrollUntilVisible(
        find.text('Lưu hồ sơ'),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lưu hồ sơ'));
      await tester.pumpAndSettle();
      expect(nameController.text, 'Bản nháp của An');
      expect(find.textContaining('Không thể kết nối mạng'), findsOneWidget);
      expect(adapter.requests, isEmpty);
      expect(draftStore.values.keys.single, contains('/7/'));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        host(
          EditProfileScreen(
            profile: UserProfile.fromJson(profileJson()),
            changes: changes,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Bản nháp của An'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Received invitation actions render and refresh failure keeps the list',
    (tester) async {
      adapter.respond = (_) async => response(
        200,
        pageJson([
          {
            'requester': {'user_id': 8, 'full_name': 'Bình'},
          },
        ]),
      );
      await tester.pumpWidget(
        host(
          RelationshipsScreen(
            changes: changes,
            initial: RelationshipList.received,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Bình'), findsOneWidget);
      connection.change(ConnectionStatus.offline);
      await tester.tap(find.text('Chấp nhận'));
      await tester.pumpAndSettle();
      expect(find.text('Bình'), findsOneWidget);
      expect(find.textContaining('Không thể kết nối mạng'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
