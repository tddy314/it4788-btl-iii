import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class KeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
}

/// Dành cho token và dữ liệu nhạy cảm.
class SecureKeyValueStore implements KeyValueStore {
  SecureKeyValueStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;
  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
  @override
  Future<void> remove(String key) => _storage.delete(key: key);
}

/// Cache nhỏ, không nhạy cảm; không dùng để lưu token hoặc file media.
class PreferencesKeyValueStore implements KeyValueStore {
  PreferencesKeyValueStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();
  final SharedPreferencesAsync _preferences;
  @override
  Future<String?> read(String key) => _preferences.getString(key);
  @override
  Future<void> write(String key, String value) =>
      _preferences.setString(key, value);
  @override
  Future<void> remove(String key) => _preferences.remove(key);
}
