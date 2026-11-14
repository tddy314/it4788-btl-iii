import 'package:flutter/material.dart';

import '../../core/widgets/app_states.dart';
import 'post_detail_screen.dart';

/// Shared entry point for notifications and other features opening a post.
abstract final class PostRoutes {
  static const detail = '/posts/detail';

  static Map<String, WidgetBuilder> get routes => {
    detail: (context) {
      final args = ModalRoute.of(context)?.settings.arguments;
      final value = args is Map ? args['postId'] : args;
      final id = value is int
          ? value
          : value is String && RegExp(r'^[1-9][0-9]*$').hasMatch(value)
          ? int.tryParse(value)
          : null;
      if (id == null || id <= 0) {
        return Scaffold(
          appBar: AppBar(title: const Text('Bài viết')),
          body: const AppErrorState(message: 'Bài viết không hợp lệ.'),
        );
      }
      return PostDetailScreen(id: id);
    },
  };
}
