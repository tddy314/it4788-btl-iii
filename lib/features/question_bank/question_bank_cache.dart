import 'dart:convert';

import '../../core/storage/draft_store.dart';
import '../../core/storage/json_cache.dart';

/// Submission source, answer state and ratings belong to the signed-in user.
/// Adapt the existing JsonCache interface without putting these in preferences.
class QuestionBankCache implements JsonCache {
  QuestionBankCache({required this.drafts, required this.legacy});
  final DraftStore drafts;
  final JsonCache legacy;
  @override
  final int maxBytes = 512 * 1024;
  Future<void> _pending = Future.value();
  String _name(String resource) => 'qb.cache.v2/$resource';

  Future<T> _serial<T>(Future<T> Function() action) {
    final next = _pending.then((_) => action());
    _pending = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  @override
  Future<CacheEntry?> read({
    required String userId,
    required String resource,
  }) => _serial(() async {
    final stored = await drafts.read(userId: userId, name: _name(resource));
    if (stored != null) {
      final at = DateTime.tryParse(stored['saved_at']?.toString() ?? '');
      return stored['version'] == 1 && at != null && stored.containsKey('data')
          ? CacheEntry(data: stored['data'], savedAt: at)
          : null;
    }
    final old = await legacy.read(userId: userId, resource: resource);
    if (old != null) {
      try {
        await _save(userId, resource, old);
        await legacy.remove(userId: userId, resource: resource);
      } catch (_) {
        // Migration is best-effort: retain the valid offline record and retry
        // encryption on a later read. All new writes still use secure storage.
      }
    }
    return old;
  });

  Future<void> _save(String userId, String resource, CacheEntry entry) async {
    final value = {
      'version': 1,
      'saved_at': entry.savedAt.toUtc().toIso8601String(),
      'data': entry.data,
    };
    if (utf8.encode(jsonEncode(value)).length > maxBytes) {
      throw ArgumentError('Cache vượt quá giới hạn $maxBytes bytes.');
    }
    await drafts.save(userId: userId, name: _name(resource), data: value);
  }

  @override
  Future<void> write({
    required String userId,
    required String resource,
    required Object? data,
  }) => _serial(() async {
    await _save(
      userId,
      resource,
      CacheEntry(data: data, savedAt: DateTime.now()),
    );
    await legacy.remove(userId: userId, resource: resource);
  });

  @override
  Future<void> remove({required String userId, required String resource}) =>
      _serial(() async {
        await drafts.remove(userId: userId, name: _name(resource));
        await legacy.remove(userId: userId, resource: resource);
      });
}
