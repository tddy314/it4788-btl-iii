import 'package:flutter/material.dart';

import '../../../../core/widgets/app_network_image.dart';
import '../../models/notification_item.dart';

class NotificationTile extends StatelessWidget {
  const NotificationTile({
    super.key,
    required this.notification,
    required this.onTap,
  });

  final NotificationItem notification;
  final VoidCallback onTap;

  String _formatRelativeTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inSeconds < 60) return 'Vừa xong';
    if (diff.inMinutes < 60) return '${diff.inMinutes} phút trước';
    if (diff.inHours < 24) return '${diff.inHours} giờ trước';
    if (diff.inDays < 7) return '${diff.inDays} ngày trước';
    return '${time.day}/${time.month}/${time.year}';
  }

  IconData _iconForType(String type) => switch (type.toUpperCase()) {
    'POST_LIKE' || 'LIKE' => Icons.thumb_up_alt_rounded,
    'POST_COMMENT' || 'COMMENT' => Icons.chat_bubble_outline_rounded,
    'SESSION_APPROVED' ||
    'SESSION_REJECTED' ||
    'QUESTION_SESSION' => Icons.school_outlined,
    'FRIEND_REQUEST' || 'FRIEND_ACCEPT' => Icons.person_add_outlined,
    'NEW_MESSAGE' || 'CHAT' => Icons.mail_outline_rounded,
    _ => Icons.notifications_none_rounded,
  };

  Color _iconColorForType(BuildContext context, String type) {
    final theme = Theme.of(context);
    return switch (type.toUpperCase()) {
      'POST_LIKE' || 'LIKE' => Colors.blue,
      'POST_COMMENT' || 'COMMENT' => Colors.green,
      'SESSION_APPROVED' => Colors.teal,
      'SESSION_REJECTED' => Colors.redAccent,
      'FRIEND_REQUEST' || 'FRIEND_ACCEPT' => Colors.orange,
      'NEW_MESSAGE' || 'CHAT' => theme.colorScheme.primary,
      _ => theme.colorScheme.primary,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUnread = !notification.isRead;
    final actor = notification.actor;

    return Material(
      color: isUnread
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.25)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar người gửi kèm badge icon loại thông báo
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AppAvatar(
                    imageUrl: actor?.avatarUrl ?? notification.iconUrl,
                    name: actor?.fullName ?? '',
                    size: 52,
                  ),
                  Positioned(
                    bottom: -2,
                    right: -2,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: Icon(
                        _iconForType(notification.type),
                        size: 14,
                        color: _iconColorForType(context, notification.type),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),

              // Nội dung thông báo
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      text: TextSpan(
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.textTheme.bodyLarge?.color,
                        ),
                        children: [
                          if (actor != null && actor.fullName.isNotEmpty)
                            TextSpan(
                              text: '${actor.fullName} ',
                              style: TextStyle(
                                fontWeight: isUnread
                                    ? FontWeight.bold
                                    : FontWeight.w600,
                              ),
                            ),
                          TextSpan(
                            text: notification.body.isNotEmpty
                                ? notification.body
                                : notification.title,
                            style: TextStyle(
                              fontWeight: isUnread
                                  ? FontWeight.w500
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatRelativeTime(notification.createdAt),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isUnread
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                        fontWeight: isUnread
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),

              // Chấm xanh thông báo chưa đọc
              if (isUnread) ...[
                const SizedBox(width: 8),
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
