class NotificationActor {
  const NotificationActor({
    required this.userId,
    required this.fullName,
    this.avatarUrl,
    this.frameUrl,
  });

  final String userId;
  final String fullName;
  final String? avatarUrl;
  final String? frameUrl;

  factory NotificationActor.fromJson(Map<String, dynamic> json) =>
      NotificationActor(
        userId: json['user_id']?.toString() ?? '',
        fullName: json['full_name'] as String? ?? 'Người dùng',
        avatarUrl: json['avatar_url'] as String?,
        frameUrl: json['frame_url'] as String?,
      );

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'full_name': fullName,
    'avatar_url': avatarUrl,
    'frame_url': frameUrl,
  };
}

class NotificationTarget {
  const NotificationTarget({required this.type, required this.id, this.url});

  final String type;
  final String id;
  final String? url;

  factory NotificationTarget.fromJson(Map<String, dynamic> json) =>
      NotificationTarget(
        type: json['type'] as String? ?? '',
        id: json['target_id']?.toString() ?? json['id']?.toString() ?? '',
        url: json['url'] as String?,
      );

  Map<String, dynamic> toJson() => {'type': type, 'id': id, 'url': url};
}

class NotificationItem {
  const NotificationItem({
    required this.notificationId,
    required this.type,
    required this.title,
    required this.body,
    this.iconUrl,
    this.readAt,
    required this.createdAt,
    this.actor,
    this.target,
  });

  final String notificationId;
  final String type;
  final String title;
  final String body;
  final String? iconUrl;
  final DateTime? readAt;
  final DateTime createdAt;
  final NotificationActor? actor;
  final NotificationTarget? target;

  bool get isRead => readAt != null;

  NotificationItem copyWith({DateTime? readAt}) => NotificationItem(
    notificationId: notificationId,
    type: type,
    title: title,
    body: body,
    iconUrl: iconUrl,
    readAt: readAt ?? this.readAt,
    createdAt: createdAt,
    actor: actor,
    target: target,
  );

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic raw) {
      if (raw == null) return DateTime.now();
      return DateTime.tryParse(raw.toString()) ?? DateTime.now();
    }

    return NotificationItem(
      notificationId: json['notification_id']?.toString() ?? '',
      type: json['type'] as String? ?? 'SYSTEM',
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      iconUrl: json['icon_url'] as String?,
      readAt: json['read_at'] != null ? parseDate(json['read_at']) : null,
      createdAt: parseDate(json['created_at']),
      actor: json['actor'] is Map<String, dynamic>
          ? NotificationActor.fromJson(json['actor'] as Map<String, dynamic>)
          : null,
      target: json['target'] is Map<String, dynamic>
          ? NotificationTarget.fromJson(json['target'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'notification_id': notificationId,
    'type': type,
    'title': title,
    'body': body,
    'icon_url': iconUrl,
    'read_at': readAt?.toIso8601String(),
    'created_at': createdAt.toIso8601String(),
    'actor': actor?.toJson(),
    'target': target?.toJson(),
  };
}

class NotificationListResponse {
  const NotificationListResponse({
    required this.items,
    required this.unreadCount,
    this.after,
    this.hasNext = false,
  });

  final List<NotificationItem> items;
  final int unreadCount;
  final String? after;
  final bool hasNext;

  factory NotificationListResponse.fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) {
      return const NotificationListResponse(items: [], unreadCount: 0);
    }

    final rawItems = raw['items'];
    final itemsList = <NotificationItem>[];
    if (rawItems is List) {
      for (final item in rawItems) {
        if (item is Map<String, dynamic>) {
          itemsList.add(NotificationItem.fromJson(item));
        }
      }
    }

    final pagination = raw['pagination'] as Map<String, dynamic>?;
    final unreadRaw = raw['unread_count'];
    final unread = unreadRaw is num
        ? unreadRaw.toInt()
        : int.tryParse(unreadRaw?.toString() ?? '0') ?? 0;

    return NotificationListResponse(
      items: itemsList,
      unreadCount: unread,
      after: pagination?['after']?.toString(),
      hasNext: pagination?['has_next'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'items': items.map((e) => e.toJson()).toList(),
    'unread_count': unreadCount,
    'pagination': {'after': after, 'has_next': hasNext},
  };
}
