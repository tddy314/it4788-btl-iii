import 'dart:convert';

import '../../../core/network/api_client.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/storage/json_cache.dart';
import '../../../core/storage/draft_store.dart';
import '../../../core/storage/key_value_store.dart';
import '../models/notification_item.dart';

class NotificationRepository {
  NotificationRepository({
    required this.api,
    required this.cache,
    DraftStore? privateStore,
  }) : _privateStore = privateStore ?? DraftStore(SecureKeyValueStore());

  final ApiClient api;
  final JsonCache cache;
  final DraftStore _privateStore;
  static const _cacheResource = 'notifications';
  static const _secureResource = 'notifications.cache.v2';

  Future<void> clearCache(String userId) async {
    await _privateStore.remove(userId: userId, name: _secureResource);
    await cache.remove(userId: userId, resource: _cacheResource);
  }

  Future<NotificationListResponse> fetchNotifications({
    String? after,
    int limit = 20,
  }) async {
    final query = <String, dynamic>{
      'limit': limit,
      if (after != null && after.isNotEmpty) 'after': after,
    };

    return api.get(
      'notifications',
      query: query,
      decode: NotificationListResponse.fromJson,
    );
  }

  Future<NotificationReadResult> markAsRead(String notificationId) async {
    if ((int.tryParse(notificationId) ?? 0) <= 0) {
      throw AppFailure.invalidData;
    }
    final result = await api.request(
      'notifications/$notificationId/read',
      method: 'POST',
      decode: NotificationReadResult.fromJson,
    );
    if (result.notificationId != notificationId || !result.read) {
      throw AppFailure.invalidData;
    }
    return result;
  }

  Future<void> markAllAsRead() async {
    await api.request(
      'notifications/read-all',
      method: 'POST',
      decode: (_) => null,
    );
  }

  Future<NotificationListResponse?> loadCached(String userId) async {
    final stored = await _privateStore.read(
      userId: userId,
      name: _secureResource,
    );
    if (stored != null) {
      try {
        return NotificationListResponse.fromJson(stored);
      } catch (_) {
        return null;
      }
    }
    // One-time migration. Do not keep writing personal notification bodies to
    // preferences; PDF p.35 requires privacy-related data to be encrypted.
    final entry = await cache.read(userId: userId, resource: _cacheResource);
    if (entry?.data == null) return null;
    final NotificationListResponse migrated;
    try {
      migrated = NotificationListResponse.fromJson(entry!.data);
    } catch (_) {
      return null;
    }
    try {
      await saveToCache(userId, migrated);
    } catch (_) {
      // Keep the previously valid copy when migration cannot write secure
      // storage. Never erase the only offline copy to repair a storage error.
    }
    return migrated;
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

    if (utf8.encode(jsonEncode(cachePayload)).length > 512 * 1024) {
      throw const AppFailure(
        FailureKind.storage,
        'Dữ liệu thông báo vượt giới hạn lưu trên máy.',
      );
    }
    await _privateStore.save(
      userId: userId,
      name: _secureResource,
      data: cachePayload,
    );
    await cache.remove(userId: userId, resource: _cacheResource);
  }
}
