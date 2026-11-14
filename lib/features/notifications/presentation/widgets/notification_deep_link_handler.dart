import 'package:flutter/material.dart';

import '../../../profile/profile_models.dart';
import '../../../question_bank/question_bank_routes.dart';
import '../../models/notification_item.dart';

class NotificationDeepLinkHandler {
  static void handleTap(BuildContext context, NotificationItem item) {
    final target = item.target;
    if (target == null || target.id.isEmpty) return;

    final targetType = target.type.toUpperCase();

    try {
      switch (targetType) {
        case 'CHAT':
        case 'MESSAGE':
        case 'CONVERSATION':
          Navigator.of(context)
              .pushNamed('/chat', arguments: {'conversationId': target.id});
          break;

        case 'POST':
          Navigator.of(context)
              .pushNamed('/posts/detail', arguments: {'postId': target.id});
          break;

        case 'QUESTION_SESSION':
        case 'SESSION':
          final sessionId = int.tryParse(target.id);
          if (sessionId != null) {
            Navigator.of(context)
                .pushNamed(QuestionBankRoutes.submission, arguments: sessionId);
          }
          break;

        case 'FRIEND_REQUEST':
        case 'PROFILE':
        case 'USER':
          Navigator.of(context)
              .pushNamed(ProfileRoutes.user, arguments: target.id);
          break;

        default:
          if (target.url != null && target.url!.isNotEmpty) {
            Navigator.of(context).pushNamed(target.url!);
          }
          break;
      }
    } catch (_) {
      // Bắt ngoại lệ điều hướng nếu route chưa đăng ký hoặc nội dung đích bị xóa
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Nội dung này không còn tồn tại hoặc bạn không có quyền truy cập.',
            ),
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }
}
