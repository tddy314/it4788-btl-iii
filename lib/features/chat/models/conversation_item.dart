class ConversationItem {
  const ConversationItem({
    required this.conversationId,
    required this.type,
    required this.displayName,
    this.displayAvatarUrl,
    this.lastMessageContent,
    this.lastMessageId,
    this.unreadCount = 0,
    this.updatedAt,
    this.partnerId,
  });

  final String conversationId;
  final String type;
  final String displayName;
  final String? displayAvatarUrl;
  final String? lastMessageContent;
  final String? lastMessageId;
  final int unreadCount;
  final DateTime? updatedAt;
  final String? partnerId;

  ConversationItem copyWith({
    String? lastMessageContent,
    String? lastMessageId,
    int? unreadCount,
    DateTime? updatedAt,
  }) => ConversationItem(
    conversationId: conversationId,
    type: type,
    displayName: displayName,
    displayAvatarUrl: displayAvatarUrl,
    lastMessageContent: lastMessageContent ?? this.lastMessageContent,
    lastMessageId: lastMessageId ?? this.lastMessageId,
    unreadCount: unreadCount ?? this.unreadCount,
    updatedAt: updatedAt ?? this.updatedAt,
    partnerId: partnerId,
  );

  factory ConversationItem.fromJson(Map<String, dynamic> json) {
    final lastMsg = json['last_message'] as Map<String, dynamic>?;
    final unreadRaw = json['unread_count'];
    final unread = unreadRaw is num
        ? unreadRaw.toInt()
        : int.tryParse(unreadRaw?.toString() ?? '0') ?? 0;

    DateTime? parseDate(dynamic raw) {
      if (raw == null) return null;
      return DateTime.tryParse(raw.toString());
    }

    return ConversationItem(
      conversationId: json['conversation_id']?.toString() ?? '',
      type: json['type'] as String? ?? 'DIRECT',
      displayName: json['display_name'] as String? ?? 'Cuộc trò chuyện',
      displayAvatarUrl: json['display_avatar_url'] as String?,
      lastMessageContent: lastMsg?['content'] as String?,
      lastMessageId: lastMsg?['id']?.toString(),
      unreadCount: unread,
      updatedAt: parseDate(json['updated_at'] ?? lastMsg?['created_at']),
      partnerId: json['partner_id']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'conversation_id': conversationId,
    'type': type,
    'display_name': displayName,
    'display_avatar_url': displayAvatarUrl,
    'last_message': {
      if (lastMessageId != null) 'id': lastMessageId,
      if (lastMessageContent != null) 'content': lastMessageContent,
    },
    'unread_count': unreadCount,
    'updated_at': updatedAt?.toIso8601String(),
    if (partnerId != null) 'partner_id': partnerId,
  };
}

class ConversationListResponse {
  const ConversationListResponse({
    required this.items,
    this.after,
    this.hasNext = false,
  });

  final List<ConversationItem> items;
  final String? after;
  final bool hasNext;

  factory ConversationListResponse.fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) {
      return const ConversationListResponse(items: []);
    }

    final rawItems = raw['items'];
    final list = <ConversationItem>[];
    if (rawItems is List) {
      for (final item in rawItems) {
        if (item is Map<String, dynamic>) {
          list.add(ConversationItem.fromJson(item));
        }
      }
    }

    final pagination = raw['pagination'] as Map<String, dynamic>?;

    return ConversationListResponse(
      items: list,
      after: pagination?['after'] as String?,
      hasNext: pagination?['has_next'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'items': items.map((e) => e.toJson()).toList(),
    'pagination': {'after': after, 'has_next': hasNext},
  };
}
