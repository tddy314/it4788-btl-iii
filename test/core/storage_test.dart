import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:it4788_btl/core/errors/app_failure.dart';
import 'package:it4788_btl/core/storage/cached_resource_controller.dart';
import 'package:it4788_btl/core/storage/json_cache.dart';
import 'package:it4788_btl/core/storage/session_store.dart';

import '../support/fakes.dart';

void main() {
  test('Cache persists across instances and isolates users', () async {
    final storage = MemoryStore();
    await JsonCache(storage)
        .write(userId: 'a', resource: 'feed', data: ['saved']);
    expect(
      (await JsonCache(storage).read(userId: 'a', resource: 'feed'))!.data,
      ['saved'],
    );
    expect(
      await JsonCache(storage).read(userId: 'b', resource: 'feed'),
      isNull,
    );
  });

  test('Corrupt cache is a miss, not an app crash', () async {
    final storage = MemoryStore();
    final cache = JsonCache(storage);
    await cache.write(userId: 'a', resource: 'feed', data: []);
    storage.values.updateAll((_, _) => '{broken');
    expect(await cache.read(userId: 'a', resource: 'feed'), isNull);
  });

  test(
    'Cold offline load shows cache; failed refresh keeps it; reconnect updates',
    () async {
      final cache = JsonCache(MemoryStore());
      await cache.write(userId: 'a', resource: 'feed', data: ['old']);
      var online = false;
      final controller = CachedResourceController<List<String>>(
        cache: cache,
        userId: 'a',
        resource: 'feed',
        fetch: () async {
          if (!online) throw AppFailure.offline;
          return ['new'];
        },
        decode: (v) => (v as List).cast<String>(),
        encode: (v) => v,
      );
      addTearDown(controller.dispose);
      await controller.load();
      expect(controller.data, ['old']);
      expect(controller.isLoading, isFalse);
      expect(controller.failure?.kind, FailureKind.offline);
      await controller.load();
      expect(controller.data, ['old']);
      online = true;
      await controller.load();
      expect(controller.data, ['new']);
      expect(controller.failure, isNull);
      expect(controller.isFromCache, isFalse);
    },
  );

  test(
    'Forbidden response must not continue displaying cached content',
    () async {
      final cache = JsonCache(MemoryStore());
      await cache.write(userId: 'a', resource: 'feed', data: ['old']);
      final controller = CachedResourceController<List<String>>(
        cache: cache,
        userId: 'a',
        resource: 'feed',
        fetch: () async =>
            throw const AppFailure(FailureKind.forbidden, 'Denied'),
        decode: (v) => (v as List).cast<String>(),
        encode: (v) => v,
      );
      addTearDown(controller.dispose);
      await controller.load();
      expect(controller.data, isNull);
    },
  );

  test('Dispose during request does not notify or overwrite cache', () async {
    final done = Completer<List<String>>();
    final cache = JsonCache(MemoryStore());
    final controller = CachedResourceController<List<String>>(
      cache: cache,
      userId: 'a',
      resource: 'feed',
      fetch: () => done.future,
      decode: (v) => (v as List).cast<String>(),
      encode: (v) => v,
    );
    final load = controller.load();
    controller.dispose();
    done.complete(['late']);
    await load;
    expect(await cache.read(userId: 'a', resource: 'feed'), isNull);
  });

  test(
    'Session restores without network and logout removes persisted tokens',
    () async {
      final storage = MemoryStore();
      final first = SessionStore(storage);
      final restored = SessionStore(storage);
      addTearDown(first.dispose);
      addTearDown(restored.dispose);
      await first.save(
        const SessionTokens(
          userId: 'a',
          accessToken: 'access',
          refreshToken: 'refresh',
        ),
      );
      await restored.restore();
      expect(restored.tokens?.userId, 'a');
      await restored.clear();
      expect(restored.hasSession, isFalse);
      expect(storage.values, isEmpty);
    },
  );

  test('Logout wins over an in-flight token save', () async {
    final storage = MemoryStore();
    final session = SessionStore(storage);
    addTearDown(session.dispose);
    final save = session.save(
      const SessionTokens(
        userId: 'a',
        accessToken: 'access',
        refreshToken: 'refresh',
      ),
    );
    final clear = session.clear();
    await Future.wait([save, clear]);
    expect(session.hasSession, isFalse);
    expect(storage.values, isEmpty);
  });
}
