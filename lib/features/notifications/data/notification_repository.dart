import '../../../core/network/api_client.dart';
import '../../../core/storage/json_cache.dart';
import '../models/notification_item.dart';

class NotificationRepository {
  NotificationRepository({required ApiClient api, required JsonCache cache})
    : _api = api,
      _cache = cache;

  final ApiClient _api;
  final JsonCache _cache;
  static const _cacheResource = 'notifications';

  Future<NotificationListResponse> fetchNotifications({
    String? after,
    int limit = 20,
  }) async {
    final query = <String, dynamic>{
      'limit': limit,
      if (after != null && after.isNotEmpty) 'after': after,
    };

    return _api.get(
      'notifications',
      query: query,
      decode: NotificationListResponse.fromJson,
    );
  }

  Future<void> markAsRead(String notificationId) async {
    await _api.request(
      'notifications/$notificationId/read',
      method: 'POST',
      decode: (_) => null,
    );
  }

  Future<void> markAllAsRead() async {
    await _api.request(
      'notifications/read-all',
      method: 'POST',
      decode: (_) => null,
    );
  }

  Future<NotificationListResponse?> loadCached(String userId) async {
    final entry = await _cache.read(userId: userId, resource: _cacheResource);
    if (entry == null || entry.data == null) return null;
    try {
      return NotificationListResponse.fromJson(entry.data);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveToCache(
    String userId,
    NotificationListResponse response,
  ) async {
    // Chỉ cache tối đa 30 item để tiết kiệm bộ nhớ theo quy chuẩn core (512 KiB limit)
    final itemsToCache = response.items.take(30).toList();
    final cachePayload = NotificationListResponse(
      items: itemsToCache,
      unreadCount: response.unreadCount,
      after: response.after,
      hasNext: response.hasNext,
    ).toJson();

    await _cache.write(
      userId: userId,
      resource: _cacheResource,
      data: cachePayload,
    );
  }
}
