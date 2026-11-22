import 'dart:convert';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../../core/storage/draft_store.dart';
import '../../../core/storage/json_cache.dart';
import '../../../core/storage/key_value_store.dart';
import '../../../core/storage/session_store.dart';
import '../../settings/models/push_settings.dart';

/// Both foreground and data-only background delivery use the same account checks.
class NotificationPresenter {
  final plugin = FlutterLocalNotificationsPlugin();
  Future<void> initialize({void Function(String?)? onTap}) => plugin.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('ic_stat_sqb'),
    ),
    onDidReceiveNotificationResponse: (response) =>
        onTap?.call(response.payload),
  );
  static int stableId(String value) {
    var id = 2166136261;
    for (final unit in value.codeUnits) {
      id = ((id ^ unit) * 16777619) & 0x7fffffff;
    }
    return id;
  }

  static Map<String, dynamic>? target(
    Map<String, dynamic> data,
    String userId,
  ) {
    final recipient = data['recipient_user_id']?.toString();
    if (recipient != null && recipient != userId) return null;
    final raw = data['target'];
    Map<String, dynamic>? nested;
    try {
      if (raw is String) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) nested = decoded;
      } else if (raw is Map<String, dynamic>) {
        nested = raw;
      }
    } on FormatException {
      return null;
    }
    final type = (nested?['type'] ?? data['target_type'])
        ?.toString()
        .toUpperCase();
    final id = (nested?['target_id'] ?? nested?['id'] ?? data['target_id'])
        ?.toString();
    if (!const [
          'POST',
          'USER',
          'CONVERSATION',
          'SESSION',
          'QUESTION',
        ].contains(type) ||
        id == null ||
        !RegExp(r'^[1-9][0-9]*$').hasMatch(id)) {
      return null;
    }
    return {'account': userId, 'type': type, 'id': id};
  }

  Future<void> show(RemoteMessage message) async {
    final secure = SecureKeyValueStore();
    final session = SessionStore(secure);
    try {
      await session.restore();
      final userId = session.tokens?.userId;
      if (userId == null) return;
      final recipient = message.data['recipient_user_id']?.toString();
      if (recipient != null && recipient != userId) return;
      final cache = JsonCache(PreferencesKeyValueStore());
      final entry = await cache.read(userId: userId, resource: 'push_settings');
      final settings = entry?.data is Map<String, dynamic>
          ? PushSettings.fromJson(entry!.data as Map<String, dynamic>)
          : PushSettings.defaults();
      final category = message.data['category']?.toString().toUpperCase();
      if (!settings.pushEnabled ||
          category == 'SOCIAL' && !settings.social.enabled ||
          category == 'ACADEMIC' && !settings.academic.enabled ||
          category == 'SYSTEM' && !settings.system.enabled) {
        return;
      }
      final drafts = DraftStore(secure);
      final sound = await drafts.read(
        userId: userId,
        name: 'notification.sound.v1',
      );
      final uri = sound?['uri'] as String?;
      final path = sound?['path'];
      final voice =
          sound?['mode'] == 'voice' &&
          uri != null &&
          path is String &&
          await File(path).exists();
      final channel =
          'sqb_${stableId('$userId/${settings.soundEnabled}/${settings.vibrationEnabled}/${voice ? uri : 'default'}')}';
      final id = stableId(message.messageId ?? jsonEncode(message.data));
      final seen = await drafts.read(userId: userId, name: 'push.seen.v1');
      final ids = (seen?['ids'] as List? ?? []).whereType<int>().toList();
      if (ids.contains(id)) return;
      // Without an explicit recipient, never expose a possibly stale account's content.
      final trustedRecipient = recipient == userId;
      final payload = target(message.data, userId);
      // Re-read the session before displaying after storage work.
      final latest = SessionStore(secure);
      try {
        await latest.restore();
        if (latest.tokens?.userId != userId) return;
      } finally {
        latest.dispose();
      }
      await plugin.show(
        id: id,
        title: trustedRecipient
            ? message.notification?.title ??
                  message.data['title']?.toString() ??
                  'SQB'
            : 'SQB',
        body: trustedRecipient
            ? message.notification?.body ??
                  message.data['body']?.toString() ??
                  'Bạn có thông báo mới.'
            : 'Bạn có thông báo mới. Mở ứng dụng để xem.',
        payload: payload == null
            ? null
            : jsonEncode({...payload, 'notification': id.toString()}),
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channel,
            'Thông báo SQB',
            importance: Importance.high,
            onlyAlertOnce: true,
            priority: Priority.high,
            playSound: settings.soundEnabled,
            enableVibration: settings.vibrationEnabled,
            sound: voice ? UriAndroidNotificationSound(uri) : null,
          ),
        ),
      );
      await drafts.save(
        userId: userId,
        name: 'push.seen.v1',
        data: {
          'ids': [id, ...ids].take(50).toList(),
        },
      );
    } finally {
      session.dispose();
    }
  }
}
