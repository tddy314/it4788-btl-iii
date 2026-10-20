import 'dart:convert';

import 'key_value_store.dart';

/// Inject SecureKeyValueStore vì bản nháp có thể chứa thông tin riêng tư.
/// Feature chủ động lưu khi sửa, phục hồi khi mở lại, xóa sau khi server xác nhận.
class DraftStore {
  DraftStore(this._secureStorage);
  final KeyValueStore _secureStorage;
  String _key(String userId, String name) {
    if (userId.isEmpty || name.isEmpty) throw ArgumentError('Empty draft key');
    return 'sqb.draft.v1/${Uri.encodeComponent(userId)}/${Uri.encodeComponent(name)}';
  }

  Future<void> save({
    required String userId,
    required String name,
    required Map<String, dynamic> data,
  }) => _secureStorage.write(_key(userId, name), jsonEncode(data));
  Future<Map<String, dynamic>?> read({
    required String userId,
    required String name,
  }) async {
    final raw = await _secureStorage.read(_key(userId, name));
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<void> remove({required String userId, required String name}) =>
      _secureStorage.remove(_key(userId, name));
}
