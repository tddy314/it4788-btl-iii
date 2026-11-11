import 'package:flutter/material.dart';

import '../../core/errors/app_failure.dart';

class SocialNotice extends StatelessWidget {
  const SocialNotice({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message),
          if (onRetry != null)
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Thử lại'),
            ),
        ],
      ),
    ),
  );
}

String socialWriteError(Object error) {
  if (error is AppFailure) {
    if ([
      FailureKind.timeout,
      FailureKind.server,
      FailureKind.invalidData,
      FailureKind.unknown,
      FailureKind.cancelled,
    ].contains(error.kind)) {
      return 'Chưa xác nhận được kết quả. Hãy tải lại để kiểm tra. '
          'Ứng dụng sẽ đối soát trước khi bạn thực hiện lại.';
    }
    return error.message;
  }
  return 'Không thể hoàn tất thao tác. Vui lòng tải lại để kiểm tra.';
}

Future<bool> confirmSocialAction(
  BuildContext context,
  String title,
  String message,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$title?'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(title),
          ),
        ],
      ),
    ) ??
    false;
