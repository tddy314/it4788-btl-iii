import '../../../core/network/api_client.dart';
import '../../../core/storage/json_cache.dart';
import '../models/push_settings.dart';

class PushSettingsRepository {
  PushSettingsRepository({
    required ApiClient api,
    required JsonCache cache,
  }) : _api = api,
       _cache = cache;

  final ApiClient _api;
  final JsonCache _cache;
  static const _cacheResource = 'push_settings';

  Future<PushSettings> fetchSettings() async {
    return _api.get(
      'settings/push',
      decode: (data) =>
          PushSettings.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<PushSettings> updateSettings(PushSettings settings) async {
    return _api.request(
      'settings/push',
      method: 'PUT',
      data: settings.toJson(),
      decode: (data) =>
          PushSettings.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<void> registerDevice({
    required String fcmToken,
    required String deviceName,
  }) async {
    await _api.request(
      'devices/register',
      method: 'POST',
      data: {
        'fcm_token': fcmToken,
        'platform': 'ANDROID',
        'device_name': deviceName,
        'app_version': '1.0.0',
      },
      decode: (_) => null,
    );
  }

  Future<void> unregisterDevice(String fcmToken) async {
    await _api.request(
      'devices/register',
      method: 'DELETE',
      data: {'fcm_token': fcmToken},
      decode: (_) => null,
    );
  }

  Future<PushSettings?> loadCached(String userId) async {
    final entry = await _cache.read(userId: userId, resource: _cacheResource);
    if (entry == null || entry.data == null) return null;
    try {
      return PushSettings.fromJson(entry.data as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveToCache(String userId, PushSettings settings) async {
    await _cache.write(
      userId: userId,
      resource: _cacheResource,
      data: settings.toJson(),
    );
  }
}
