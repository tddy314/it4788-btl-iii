enum ChatEventType { message, typing, read, revoked, accessChanged, unknown }

/// The private queue carries several event DTOs, not only message DTOs.
class ChatEvent {
  ChatEvent(this.type, this.data);
  final ChatEventType type;
  final Map<String, dynamic> data;
  String get conversationId => data['conversation_id']?.toString() ?? '';
  factory ChatEvent.parse(Map<String, dynamic> raw) {
    var data = raw['data'] is Map<String, dynamic>
        ? raw['data'] as Map<String, dynamic>
        : raw;
    if (data['message'] is Map<String, dynamic>) {
      data = {...data, ...data['message'] as Map<String, dynamic>};
    }
    final discriminator =
        (raw['event_type'] ?? raw['event'] ?? raw['type'] ?? '')
            .toString()
            .toUpperCase();
    final type = switch (discriminator) {
      'NEW_MESSAGE' || 'MESSAGE' => ChatEventType.message,
      'TYPING' || 'TYPING_STATUS' => ChatEventType.typing,
      'READ_RECEIPT' || 'MESSAGE_READ' => ChatEventType.read,
      'MESSAGE_REVOKED' => ChatEventType.revoked,
      'GROUP_MEMBER_REMOVED' ||
      'GROUP_ROLES_CHANGED' => ChatEventType.accessChanged,
      _ =>
        data.containsKey('typing') || data.containsKey('is_typing')
            ? ChatEventType.typing
            : data.containsKey('reader_id') ||
                  data.containsKey('reader') ||
                  data.containsKey('read_by') && !data.containsKey('content')
            ? ChatEventType.read
            : data.containsKey('message_id') &&
                  (data.containsKey('sender_id') ||
                      data.containsKey('sender')) &&
                  data.containsKey('content')
            ? ChatEventType.message
            : ChatEventType.unknown,
    };
    return ChatEvent(type, data);
  }
}
