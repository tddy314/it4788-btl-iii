import 'dart:math';

import '../../core/storage/key_value_store.dart';

/// UUID cài đặt ngẫu nhiên, không thu thập IMEI/Android ID.
class DeviceIdentity {
  DeviceIdentity(this._storage);
  final KeyValueStore _storage;
  Future<String>? _pending;
  Future<String> getId() => _pending ??= _load().catchError((Object error) {
    _pending = null;
    throw error;
  });

  Future<String> _load() async {
    const key = 'sqb.auth.installation.v1';
    final saved = await _storage.read(key);
    if (saved != null && saved.isNotEmpty) return saved;
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final uuid =
        '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
    await _storage.write(key, uuid);
    return uuid;
  }
}
