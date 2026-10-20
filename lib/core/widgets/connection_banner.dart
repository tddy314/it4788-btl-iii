import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../network/connection_monitor.dart';

class ConnectionBanner extends StatelessWidget {
  const ConnectionBanner({super.key, required this.connection});
  final ConnectionMonitor connection;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: connection,
    builder: (context, _) {
      if (connection.status != ConnectionStatus.offline) {
        return const SizedBox.shrink();
      }
      return Semantics(
        liveRegion: true,
        child: ColoredBox(
          color: AppColors.warningSurface,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  const Icon(
                    Icons.wifi_off,
                    color: AppColors.warningText,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Không có kết nối mạng. Nội dung đã lưu vẫn có thể xem.',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: AppColors.warningText),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
