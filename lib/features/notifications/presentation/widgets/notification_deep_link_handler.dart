import 'package:flutter/material.dart';

import '../../../profile/profile_models.dart';
import '../../../question_bank/question_bank_tab.dart';
import '../../models/notification_item.dart';
import 'session_notification_screen.dart';

class NotificationDeepLinkHandler {
  static final _opening = Expando<bool>();
  static Future<void> handleTap(
    BuildContext context,
    NotificationItem item,
  ) async {
    final target = item.target;
    if (target == null) return;
    final navigator = Navigator.of(context);
    if (_opening[navigator] == true) return;
    if (!RegExp(r'^[1-9][0-9]*$').hasMatch(target.id)) {
      _unavailable(context);
      return;
    }
    _opening[navigator] = true;
    try {
      switch (target.type.toUpperCase()) {
        case 'CHAT':
        case 'MESSAGE':
        case 'CONVERSATION':
          await navigator.pushNamed(
            '/chat',
            arguments: {'conversationId': target.id},
          );
        case 'POST':
          await navigator.pushNamed(
            '/posts/detail',
            arguments: {'postId': target.id},
          );
        case 'QUESTION_SESSION':
        case 'SESSION':
          await navigator.push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  SessionNotificationScreen(sessionId: int.parse(target.id)),
            ),
          );
        case 'FRIEND_REQUEST':
        case 'PROFILE':
        case 'USER':
          await navigator.pushNamed(ProfileRoutes.user, arguments: target.id);
        case 'QUESTION':
          // The server exposes questions through practice sessions, not GET by ID.
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Mở bộ câu hỏi liên quan trong Ngân hàng câu hỏi để xem nội dung này.',
              ),
            ),
          );
          await navigator.push(
            MaterialPageRoute<void>(builder: (_) => const QuestionBankTab()),
          );
        default:
          _unavailable(context);
      }
    } catch (_) {
      if (context.mounted) _unavailable(context);
    } finally {
      _opening[navigator] = false;
    }
  }

  static void _unavailable(BuildContext context) =>
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nội dung này không còn tồn tại hoặc chưa có trang tương ứng.',
          ),
        ),
      );
}
