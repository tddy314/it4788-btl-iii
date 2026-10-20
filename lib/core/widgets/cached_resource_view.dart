import 'package:flutter/material.dart';

import '../storage/cached_resource_controller.dart';
import 'app_states.dart';

/// Không thay nội dung cũ bằng màn hình lỗi khi refresh thất bại do mạng.
class CachedResourceView<T> extends StatelessWidget {
  const CachedResourceView({
    super.key,
    required this.controller,
    required this.builder,
    required this.isEmpty,
  });
  final CachedResourceController<T> controller;
  final Widget Function(BuildContext, T) builder;
  final bool Function(T) isEmpty;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final data = controller.data;
      if (data == null) {
        if (controller.isLoading) return const AppLoadingState();
        if (controller.failure != null) {
          return AppErrorState(
            message: controller.failure!.message,
            onRetry: controller.load,
          );
        }
        return const AppEmptyState();
      }
      return Column(
        children: [
          if (controller.isLoading) const LinearProgressIndicator(),
          if (controller.failure != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(child: Text(controller.failure!.message)),
                  TextButton(
                    onPressed: controller.isLoading ? null : controller.load,
                    child: const Text('Thử lại'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: isEmpty(data)
                ? const AppEmptyState()
                : builder(context, data),
          ),
        ],
      );
    },
  );
}
