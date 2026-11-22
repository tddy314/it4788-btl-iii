import '../../../core/errors/app_failure.dart';

enum MessageStatus { sending, sent, failed, unconfirmed }

enum MessageType { text, image }

class ChatMessage {
  const ChatMessage({
    required this.messageId,
    required this.clientMsgId,
    required this.conversationId,
    required this.senderId,
    required this.senderName,
    this.avatarUrl,
    required this.content,
    this.messageType = MessageType.text,
    this.mediaUrls = const [],
    required this.createdAt,
    this.status = MessageStatus.sent,
    this.isRead = false,
  });

  final String messageId;
  final String clientMsgId;
  final String conversationId;
  final String senderId;
  final String senderName;
  final String? avatarUrl;
  final String content;
  final MessageType messageType;
  final List<String> mediaUrls;
  final DateTime createdAt;
  final MessageStatus status;
  final bool isRead;

  bool isMine(String currentUserId) => senderId == currentUserId;

  ChatMessage copyWith({
    String? messageId,
    MessageStatus? status,
    bool? isRead,
    List<String>? mediaUrls,
    String? content,
  }) => ChatMessage(
    messageId: messageId ?? this.messageId,
    clientMsgId: clientMsgId,
    conversationId: conversationId,
    senderId: senderId,
    senderName: senderName,
    avatarUrl: avatarUrl,
    content: content ?? this.content,
    messageType: messageType,
    mediaUrls: mediaUrls ?? this.mediaUrls,
    createdAt: createdAt,
    status: status ?? this.status,
    isRead: isRead ?? this.isRead,
  );

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic raw) {
      if (raw == null) return DateTime.now();
      return DateTime.tryParse(raw.toString()) ?? DateTime.now();
    }

    final rawMedia = json['media_urls'];
    final mediaList = <String>[];
    if (rawMedia is List) {
      for (final m in rawMedia) {
        if (m is String && m.isNotEmpty) mediaList.add(m);
      }
    }

    final typeStr = json['message_type']?.toString().toUpperCase();
    final messageType = typeStr == 'IMAGE'
        ? MessageType.image
        : MessageType.text;

    final readBy = json['read_by'];
    final sender =
        (json['sender_id'] ??
                (json['sender'] is Map ? json['sender']['user_id'] : null))
            ?.toString();
    final isRead =
        json['is_read'] == true ||
        readBy is List &&
            readBy.any(
              (reader) =>
                  reader is Map &&
                  reader['user_id'] != null &&
                  reader['user_id'].toString() != sender,
            );

    return ChatMessage(
      messageId: json['message_id']?.toString() ?? '',
      clientMsgId:
          json['client_msg_id']?.toString() ??
          json['message_id']?.toString() ??
          '',
      conversationId: json['conversation_id']?.toString() ?? '',
      senderId:
          json['sender_id']?.toString() ??
          json['sender']?['user_id']?.toString() ??
          '',
      senderName:
          json['sender_name'] as String? ??
          json['sender']?['full_name'] as String? ??
          'Người dùng',
      avatarUrl:
          json['avatar_url'] as String? ??
          json['sender']?['avatar_url'] as String?,
      content: json['content'] as String? ?? '',
      messageType: messageType,
      mediaUrls: mediaList,
      createdAt: parseDate(json['created_at']),
      status: MessageStatus.sent,
      isRead: isRead,
    );
  }

  /// Server DTOs are confirmed; local records must preserve their send state.
  factory ChatMessage.fromCache(Map<String, dynamic> json) {
    final message = ChatMessage.fromJson(json);
    final status = MessageStatus.values
        .where((e) => e.name == json['status'])
        .firstOrNull;
    return message.copyWith(
      status: status == MessageStatus.sending
          ? MessageStatus.unconfirmed
          : status ?? MessageStatus.unconfirmed,
    );
  }

  Map<String, dynamic> toJson() => {
    'message_id': messageId,
    'client_msg_id': clientMsgId,
    'conversation_id': conversationId,
    'sender_id': senderId,
    'sender_name': senderName,
    'avatar_url': avatarUrl,
    'content': content,
    'message_type': messageType == MessageType.image ? 'IMAGE' : 'TEXT',
    'media_urls': mediaUrls,
    'created_at': createdAt.toIso8601String(),
    'status': status.name,
    'is_read': isRead,
  };
}

class ChatMessagesResponse {
  const ChatMessagesResponse({
    required this.conversationId,
    required this.messages,
    this.after,
    this.hasNext = false,
    this.conversationType = 'DIRECT',
  });

  final String conversationId;
  final List<ChatMessage> messages;
  final String conversationType;
  final String? after;
  final bool hasNext;

  factory ChatMessagesResponse.fromJson(Object? raw) {
    if (raw is! Map<String, dynamic> ||
        raw['messages'] is! List ||
        raw['conversation_id'] == null) {
      throw AppFailure.invalidData;
    }

    final convId = raw['conversation_id']?.toString() ?? '';
    final rawMsgs = raw['messages'];
    final list = <ChatMessage>[];
    if (rawMsgs is List) {
      for (final m in rawMsgs) {
        if (m is Map<String, dynamic>) {
          list.add(
            ChatMessage.fromJson({
              ...m,
              'conversation_id': m['conversation_id'] ?? convId,
            }),
          );
        }
      }
    }

    final pagination = raw['pagination'] as Map<String, dynamic>?;

    return ChatMessagesResponse(
      conversationId: convId,
      conversationType: raw['conversation_type']?.toString() ?? 'DIRECT',
      messages: list,
      after: pagination?['after']?.toString(),
      hasNext: pagination?['has_next'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'conversation_id': conversationId,
    'messages': messages.map((e) => e.toJson()).toList(),
    'conversation_type': conversationType,
    'pagination': {'after': after, 'has_next': hasNext},
  };
}
