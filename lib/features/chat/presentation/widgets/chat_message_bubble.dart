import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/widgets/app_network_image.dart';
import '../../models/chat_message.dart';

class ChatMessageBubble extends StatelessWidget {
  const ChatMessageBubble({
    super.key,
    required this.message,
    required this.currentUserId,
    required this.onRetry,
  });

  final ChatMessage message;
  final String currentUserId;
  final VoidCallback onRetry;

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final isMine = message.isMine(currentUserId);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        mainAxisAlignment:
            isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMine) ...[
            AppAvatar(
              imageUrl: message.avatarUrl,
              name: message.senderName,
              size: 28,
            ),
            const SizedBox(width: 8),
          ],

          Flexible(
            child: Column(
              crossAxisAlignment:
                  isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      message.messageType == MessageType.image
                          ? const EdgeInsets.all(4)
                          : const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                  decoration: BoxDecoration(
                    color:
                        isMine
                            ? theme.colorScheme.primary
                            : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isMine ? 16 : 4),
                      bottomRight: Radius.circular(isMine ? 4 : 16),
                    ),
                  ),
                  child:
                      message.messageType == MessageType.image
                          ? _buildImageContent(context)
                          : Text(
                            message.content,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color:
                                  isMine
                                      ? theme.colorScheme.onPrimary
                                      : theme.colorScheme.onSurface,
                            ),
                          ),
                ),
                const SizedBox(height: 2),

                // Trạng thái tin nhắn & Thời gian
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatTime(message.createdAt),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                        fontSize: 10,
                      ),
                    ),
                    if (isMine) ...[
                      const SizedBox(width: 4),
                      _buildStatusIcon(context),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageContent(BuildContext context) {
    final mediaUrl =
        message.mediaUrls.isNotEmpty ? message.mediaUrls.first : '';
    final isLocal =
        mediaUrl.isNotEmpty &&
        !mediaUrl.startsWith('http://') &&
        !mediaUrl.startsWith('https://');

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220, maxHeight: 220),
        child:
            isLocal
                ? Image.file(
                  File(mediaUrl),
                  fit: BoxFit.cover,
                  errorBuilder:
                      (_, __, ___) => const Icon(Icons.broken_image, size: 48),
                )
                : AppNetworkImage(
                  url: mediaUrl,
                  fit: BoxFit.cover,
                  width: 220,
                  height: 180,
                ),
      ),
    );
  }

  Widget _buildStatusIcon(BuildContext context) {
    return switch (message.status) {
      MessageStatus.sending => const SizedBox(
        width: 10,
        height: 10,
        child: CircularProgressIndicator(strokeWidth: 1.5),
      ),
      MessageStatus.sent => Icon(
        message.isRead ? Icons.done_all_rounded : Icons.done_rounded,
        size: 13,
        color:
            message.isRead
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline,
      ),
      MessageStatus.failed => GestureDetector(
        onTap: onRetry,
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 13, color: Colors.red),
            SizedBox(width: 2),
            Text(
              'Thử lại',
              style: TextStyle(
                color: Colors.red,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    };
  }
}
