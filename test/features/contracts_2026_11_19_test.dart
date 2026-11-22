import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:it4788_btl/core/config/app_config.dart';
import 'package:it4788_btl/core/errors/app_failure.dart';
import 'package:it4788_btl/core/network/api_client.dart';
import 'package:it4788_btl/core/storage/session_store.dart';
import 'package:it4788_btl/core/storage/draft_store.dart';
import 'package:it4788_btl/core/storage/json_cache.dart';
import 'package:it4788_btl/features/auth/auth_controller.dart';
import 'package:it4788_btl/features/auth/auth_repository.dart';
import 'package:it4788_btl/features/auth/device_identity.dart';
import 'package:it4788_btl/features/notifications/presentation/widgets/session_notification_screen.dart';
import 'package:it4788_btl/features/posts/post_media_service.dart';
import 'package:it4788_btl/features/posts/post_models.dart';
import 'package:it4788_btl/features/posts/posts_repository.dart';
import 'package:it4788_btl/features/posts/composer_controller.dart';
import 'package:image_picker/image_picker.dart';

import '../support/fakes.dart';
import 'auth/auth_test.dart' show AuthAdapter, response;
import 'chat/chat_flows_test.dart' show TestChatRepository, controller, message;
import 'question_bank/qb_fakes.dart' show detailJson, practiceJson;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AuthAdapter adapter;
  late ApiClient api;
  late SessionStore session;
  late AuthRepository repository;
  late AuthController auth;
  setUp(() async {
    adapter = AuthAdapter();
    session = SessionStore(MemoryStore());
    api = ApiClient(
      config: AppConfig(),
      session: session,
      connection: FakeConnection(),
      dio: Dio()..httpClientAdapter = adapter,
    );
    repository = AuthRepository(
      api: api,
      device: DeviceIdentity(MemoryStore()),
    );
    auth = AuthController(repository: repository, session: session);
    await session.save(
      const SessionTokens(
        userId: '7',
        accessToken: 'test-access',
        refreshToken: 'test-refresh',
      ),
    );
  });
  tearDown(() {
    auth.dispose();
    api.close();
    session.dispose();
  });

  test(
    'New native login, rotating refresh and logout stay on native channel',
    () async {
      await session.clear();
      await auth.login('student@school.edu.vn', 'supplied password');
      expect(session.tokens!.nativeAuth, isTrue);
      expect(
        SessionTokens.fromJson(session.tokens!.toJson()).nativeAuth,
        isTrue,
      );
      final next = await repository.refresh(session.tokens!);
      expect(next.nativeAuth, isTrue);
      await session.save(next);
      await repository.logout();
      expect(adapter.requests.map((r) => r.path), [
        'auth/native/login',
        'auth/native/refresh',
        'auth/native/logout',
      ]);
      expect(adapter.requests[1].data, {'refresh_token': 'test-refresh'});
      expect(adapter.requests[0].data['password'], 'supplied password');
    },
  );

  test(
    'Old stored session keeps offline access and does not mix token channels',
    () async {
      final restored = SessionTokens.fromJson({
        'user_id': '7',
        'access_token': 'old-access',
        'refresh_token': 'old-refresh',
      });
      expect(restored.nativeAuth, isFalse);
      await session.save(restored);
      final next = await repository.refresh(restored);
      expect(next.nativeAuth, isFalse);
      await repository.logout();
      expect(adapter.requests.map((r) => r.path), [
        'auth/refresh',
        'auth/logout',
      ]);
    },
  );

  test(
    'ONBOARDING responses never save limited tokens as a full session',
    () async {
      await session.clear();
      for (final state in [
        'EMAIL_VERIFICATION_REQUIRED',
        'PASSWORD_CHANGE_REQUIRED',
        'UNKNOWN',
      ]) {
        adapter.respond = (_) async => response(200, {
          'user_id': 7,
          'access_token': 'limited-token',
          'token_type': 'ONBOARDING',
          'account_state': state,
        });
        await auth.login('student@school.edu.vn', 'issued-password');
        expect(session.hasSession, isFalse);
        expect(auth.message, contains('giảng viên'));
      }
    },
  );

  test(
    'A session notification opens own submission or permitted public practice',
    () async {
      adapter.respond = (_) async => response(200, detailJson(42));
      expect(await resolveNotificationSession(api, 42), isTrue);
      adapter.requests.clear();
      adapter.respond = (r) async => r.path.contains('my-submissions')
          ? response(403, null, code: '1009')
          : response(200, practiceJson(42, []));
      expect(await resolveNotificationSession(api, 42), isFalse);
      expect(adapter.requests.map((r) => r.path), [
        'sessions/my-submissions/42',
        'sessions/42/questions',
      ]);
    },
  );

  test('Notification lookup does not turn timeout or account switch into public fallback', () async {
    adapter.respond = (r) async => throw DioException(
      requestOptions: r,
      type: DioExceptionType.receiveTimeout,
    );
    await expectLater(
      resolveNotificationSession(api, 42),
      throwsA(isA<AppFailure>()),
    );
    expect(adapter.requests.length, 1);
    adapter.requests.clear();
    adapter.respond = (_) async {
      await session.save(
        const SessionTokens(
          userId: '8',
          accessToken: 'other-access',
          refreshToken: 'other-refresh',
        ),
      );
      return response(200, detailJson(42));
    };
    await expectLater(
      resolveNotificationSession(api, 42),
      throwsA(isA<AppFailure>()),
    );
    expect(adapter.requests.length, 1);
  });

  test('Session target uses account cache on timeout, never after permission rejection', () async {
    final cache = JsonCache(MemoryStore());
    await cache.write(
      userId: '7',
      resource: 'qb.submission.42',
      data: detailJson(42),
    );
    adapter.respond = (r) async => throw DioException(
      requestOptions: r,
      type: DioExceptionType.receiveTimeout,
    );
    expect(await resolveNotificationSession(api, 42, cache: cache), isTrue);
    adapter.respond = (_) async => response(403, null, code: '1009');
    await expectLater(
      resolveNotificationSession(api, 42, cache: cache),
      throwsA(isA<AppFailure>()),
    );
  });

  test(
    'Old video draft keeps text and attachment, blocks upload until removed',
    () async {
      final drafts = DraftStore(MemoryStore());
      final attachment = DraftAttachment(
        path: '/old-draft.mp4',
        type: 'VIDEO',
        mime: 'video/mp4',
        size: 100,
        width: 100,
        height: 100,
        duration: 5,
      );
      await drafts.save(
        userId: '7',
        name: 'post/new',
        data: {
          'content': 'Giữ nội dung đang soạn',
          'retained': <Object>[],
          'attachments': [attachment.toJson()],
        },
      );
      final composer = ComposerController(
        repository: PostsRepository(api),
        mediaService: PostMediaService(api),
        drafts: drafts,
        session: session,
      );
      await composer.restore();
      expect(await composer.submit(), isNull);
      expect(composer.message, contains('Bản nháp cũ có video'));
      expect(composer.content, 'Giữ nội dung đang soạn');
      expect(composer.attachments.single.path, '/old-draft.mp4');
      expect(adapter.requests, isEmpty);
      expect(
        (await drafts.read(userId: '7', name: 'post/new'))!['content'],
        'Giữ nội dung đang soạn',
      );
      composer.dispose();
    },
  );

  test('Video bytes disguised as an image are rejected before decoder, copy or network', () async {
    final directory = await Directory.systemTemp.createTemp('sqb-image-only-');
    final file = File('${directory.path}/renamed.jpg');
    await file.writeAsBytes([
      0,
      0,
      0,
      16,
      102,
      116,
      121,
      112,
      109,
      112,
      52,
      50,
      0,
      0,
      0,
      0,
    ]);
    try {
      await expectLater(
        PostMediaService(api).inspect(XFile(file.path), '7'),
        throwsA(
          isA<AppFailure>().having(
            (e) => e.message,
            'message',
            contains('ảnh tĩnh'),
          ),
        ),
      );
      await expectLater(
        Future.sync(
          () => PostsRepository(api).create('', [
            const PostMedia(
              url: 'https://example.invalid/video.mp4',
              type: 'VIDEO',
            ),
          ]),
        ),
        throwsA(isA<AppFailure>()),
      );
      expect(adapter.requests, isEmpty);
    } finally {
      await file.delete();
      await directory.delete();
    }
  });

  test(
    'An explicit selected server ID reconciles a draft without another write',
    () async {
      final repo = TestChatRepository();
      final chat = controller(repo);
      await chat.initialize();
      await chat.sendTextMessage('Hai tin có thể có cùng nội dung');
      await Future<void>.delayed(const Duration(milliseconds: 40));
      final local = chat.messages.single;
      repo.stomp.emit(message(901, content: local.content));
      repo.stomp.emit(message(902, content: local.content));
      repo.stomp.emit({...message(903), 'sender_id': 8});
      expect(chat.messages.length, 4);
      expect(
        await chat.reconcileUnconfirmed(local.clientMsgId, '903'),
        isFalse,
      );
      expect(
        await chat.reconcileUnconfirmed(local.clientMsgId, 'unknown'),
        isFalse,
      );
      expect(await chat.reconcileUnconfirmed(local.clientMsgId, '901'), isTrue);
      expect(chat.messages.length, 3);
      expect(chat.messages.where((m) => m.messageId.isEmpty), isEmpty);
      expect(repo.sends, 1);
      chat.dispose();
    },
  );
}
