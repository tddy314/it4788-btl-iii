import 'package:flutter_test/flutter_test.dart';
import 'package:it4788_btl/core/storage/json_cache.dart';
import 'package:it4788_btl/features/notifications/models/notification_item.dart';

import '../../support/fakes.dart';

void main() {
  group('Notification Models & Serialization', () {
    test('NotificationItem parses JSON with actor and target correctly', () {
      final json = {
        'notification_id': 'notif_123',
        'type': 'POST_LIKE',
        'title': 'Lượt thích mới',
        'body': 'Nguyễn Văn A đã thích bài viết của bạn.',
        'icon_url': 'https://example.com/icon.png',
        'read_at': null,
        'created_at': '2026-10-22T08:30:00.000Z',
        'actor': {
          'user_id': 'user_456',
          'full_name': 'Nguyễn Văn A',
          'avatar_url': 'https://example.com/avatar.jpg',
        },
        'target': {
          'type': 'POST',
          'id': 'post_789',
          'url': '/posts/detail',
        },
      };

      final item = NotificationItem.fromJson(json);

      expect(item.notificationId, 'notif_123');
      expect(item.type, 'POST_LIKE');
      expect(item.isRead, isFalse);
      expect(item.actor?.fullName, 'Nguyễn Văn A');
      expect(item.target?.type, 'POST');
      expect(item.target?.id, 'post_789');

      final serialized = item.toJson();
      expect(serialized['notification_id'], 'notif_123');
      expect(serialized['read_at'], isNull);

      final readItem = item.copyWith(readAt: DateTime.now());
      expect(readItem.isRead, isTrue);
    });

    test('NotificationListResponse parses pagination and unreadCount', () {
      final json = {
        'items': [
          {
            'notification_id': 'n1',
            'type': 'CHAT',
            'title': 'Tin nhắn mới',
            'body': 'Chào bạn!',
            'created_at': '2026-10-22T08:00:00Z',
          },
        ],
        'unread_count': '5',
        'pagination': {'after': 'cursor_abc', 'has_next': true},
      };

      final response = NotificationListResponse.fromJson(json);

      expect(response.items.length, 1);
      expect(response.unreadCount, 5);
      expect(response.after, 'cursor_abc');
      expect(response.hasNext, isTrue);
    });

    test('Notification offline cache persistence roundtrip', () async {
      final memoryStore = MemoryStore();
      final cache = JsonCache(memoryStore);

      const userId = 'user_001';
      final item = NotificationItem(
        notificationId: 'notif_offline_1',
        type: 'SYSTEM',
        title: 'Bảo trì hệ thống',
        body: 'Hệ thống sẽ cập nhật lúc 00:00.',
        createdAt: DateTime.now(),
      );
      final response = NotificationListResponse(
        items: [item],
        unreadCount: 1,
      );

      await cache.write(
        userId: userId,
        resource: 'notifications',
        data: response.toJson(),
      );

      final entry = await cache.read(userId: userId, resource: 'notifications');
      expect(entry, isNotNull);

      final recovered = NotificationListResponse.fromJson(entry!.data);
      expect(recovered.items.length, 1);
      expect(recovered.items.first.notificationId, 'notif_offline_1');
      expect(recovered.unreadCount, 1);
    });
  });
}
