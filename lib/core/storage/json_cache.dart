import 'dart:convert';

import 'key_value_store.dart';

class CacheEntry {
  const CacheEntry({required this.data, required this.savedAt});
  final Object? data;
  final DateTime savedAt;
}

/// Cache theo tài khoản; dữ liệu cũ vẫn dùng được khi offline.
class JsonCache {
  JsonCache(this._storage, {this.maxBytes = 512 * 1024});
  final KeyValueStore _storage;
  final int maxBytes;
  String _key(String userId, String resource) {
    if (userId.isEmpty || resource.isEmpty) {
      throw ArgumentError('Empty cache key');
    }
    return 'sqb.cache.v1/${Uri.encodeComponent(userId)}/${Uri.encodeComponent(resource)}';
  }

  Future<CacheEntry?> read({
    required String userId,
    required String resource,
  }) async {
    final raw = await _storage.read(_key(userId, resource));
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      if (json['version'] != 1 || !json.containsKey('data')) return null;
      return CacheEntry(
        data: json['data'],
        savedAt: DateTime.parse(json['saved_at'] as String),
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<void> write({
    required String userId,
    required String resource,
    required Object? data,
  }) async {
    final raw = jsonEncode({
      'version': 1,
      'saved_at': DateTime.now().toUtc().toIso8601String(),
      'data': data,
    });
    if (utf8.encode(raw).length > maxBytes) {
      throw ArgumentError('Cache vượt quá giới hạn $maxBytes bytes.');
    }
    await _storage.write(_key(userId, resource), raw);
  }

  Future<void> remove({required String userId, required String resource}) =>
      _storage.remove(_key(userId, resource));
}
