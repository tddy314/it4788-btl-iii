import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:it4788_btl/core/config/app_config.dart';
import 'package:it4788_btl/core/errors/app_failure.dart';
import 'package:it4788_btl/core/network/api_client.dart';
import 'package:it4788_btl/core/storage/draft_store.dart';
import 'package:it4788_btl/core/storage/session_store.dart';
import 'package:it4788_btl/features/posts/composer_controller.dart';
import 'package:it4788_btl/features/posts/picker_recovery.dart';
import 'package:it4788_btl/features/posts/post_media_service.dart';
import 'package:it4788_btl/features/posts/post_models.dart';
import 'package:it4788_btl/features/posts/posts_repository.dart';

import '../../support/fakes.dart';
import '../auth/auth_test.dart' show AuthAdapter, response;
import 'posts_test.dart' show testSession, postJson;

class InterruptedUpload extends PostMediaService {
  InterruptedUpload(super.api);
  final uploadedPaths = <String>[];
  @override
  Future<DraftAttachment> inspect(
    XFile source,
    String userId, {
    bool copy = true,
  }) async => DraftAttachment(
    path: source.path,
    type: 'IMAGE',
    mime: 'image/png',
    size: 40,
    width: 2,
    height: 2,
  );
  @override
  Future<PostMedia> upload(
    DraftAttachment file,
    CancelToken cancel,
    void Function(int, int) progress,
  ) async {
    uploadedPaths.add(file.path);
    if (file.path == 'second.png') {
      throw const AppFailure(FailureKind.timeout, 'Mất phản hồi.');
    }
    return PostMedia(
      url: 'https://example.com/${file.path}',
      type: 'IMAGE',
      key: file.path,
    );
  }

  @override
  Future<void> removeLocal(DraftAttachment file, String userId) async {}
}

void main() {
  test(
    'A lost picker result belongs to the originating account and draft only',
    () async {
      final recovery = PickerRecovery(DraftStore(MemoryStore()));
      final old = await recovery.begin('A', Post.fromJson(postJson(21)));
      expect(await recovery.pending('B'), isNull);
      final next = await recovery.begin('B', null);
      await recovery.finish('A', old);
      expect(await recovery.pending('A'), isNull);
      expect((await recovery.pending('B'))?['nonce'], next);
      await recovery.finish('B', next);
      expect(await recovery.pending('B'), isNull);
    },
  );

  test('Partial upload survives restart, never creates an incomplete post or resends an acknowledged file', () async {
    final session = SessionStore(MemoryStore());
    await session.save(testSession);
    final transport = AuthAdapter()
      ..respond = (_) async => response(200, postJson());
    final connection = FakeConnection();
    final api = ApiClient(
      config: AppConfig(),
      session: session,
      connection: connection,
      dio: Dio()..httpClientAdapter = transport,
    );
    final drafts = DraftStore(MemoryStore());
    final media = InterruptedUpload(api);
    ComposerController open() => ComposerController(
      repository: PostsRepository(api),
      mediaService: media,
      drafts: drafts,
      session: session,
    );
    var composer = open();
    await composer.restore();
    await composer.addFiles([XFile('first.png'), XFile('second.png')]);
    await composer.submit();
    expect(transport.requests, isEmpty);
    expect(media.uploadedPaths, ['first.png', 'second.png']);
    composer.dispose();
    composer = open();
    await composer.restore();
    expect(composer.attachments.first.uploaded?.key, 'first.png');
    expect(composer.attachments.last.uncertain, isTrue);
    await composer.submit();
    expect(media.uploadedPaths.length, 2);
    await composer.removeAttachment(composer.attachments.last);
    await composer.addFiles([XFile('replacement.png')]);
    expect(await composer.submit(), 10);
    expect(media.uploadedPaths, ['first.png', 'second.png', 'replacement.png']);
    final payload = transport.requests.single.data as Map;
    expect((payload['media_urls'] as List).map((e) => e['key']), [
      'first.png',
      'replacement.png',
    ]);
    composer.dispose();
    api.close();
    session.dispose();
    connection.dispose();
  });
}
