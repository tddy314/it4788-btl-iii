import '../../../core/network/api_client.dart';
import '../../../core/storage/json_cache.dart';
import '../models/push_settings.dart';

class PushSettingsRepository {
  PushSettingsRepository({required this.api, required this.cache});

  final ApiClient api;
  final JsonCache cache;
  static const _cacheResource = 'push_settings';

  Future<PushSettings> fetchSettings() async {
    return api.get(
      'settings/push',
      decode: (data) => PushSettings.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<PushSettings> updateSettings(PushSettings settings) async {
    return api.request(
      'settings/push',
      method: 'PUT',
      data: settings.toJson(),
      decode: (data) => PushSettings.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<void> registerDevice({required String fid}) async {
    await api.request(
      'devices/fid',
      method: 'POST',
      data: {'fid': fid},
      decode: (_) => null,
    );
  }

  Future<void> unregisterDevice(String fid) async {
    await api.request(
      'devices/fid/unregister',
      method: 'POST',
      data: {'fid': fid},
      decode: (_) => null,
    );
  }

  Future<PushSettings?> loadCached(String userId) async {
    final entry = await cache.read(userId: userId, resource: _cacheResource);
    if (entry == null || entry.data == null) return null;
    try {
      return PushSettings.fromJson(entry.data as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveToCache(String userId, PushSettings settings) async {
    await cache.write(
      userId: userId,
      resource: _cacheResource,
      data: settings.toJson(),
    );
  }
}
