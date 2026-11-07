import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/widgets/app_states.dart';
import '../controllers/notification_controller.dart';
import '../data/notification_repository.dart';
import 'widgets/notification_deep_link_handler.dart';
import 'widgets/notification_tile.dart';

class NotificationsTab extends StatefulWidget {
  const NotificationsTab({super.key});

  @override
  State<NotificationsTab> createState() => _NotificationsTabState();
}

class _NotificationsTabState extends State<NotificationsTab> {
  NotificationController? _controller;
  final _scrollController = ScrollController();
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      final deps = AppScope.of(context);
      final userId = deps.session.tokens?.userId ?? 'anonymous';
      final repository = NotificationRepository(
        api: deps.api,
        cache: deps.cache,
      );
      _controller = NotificationController(
        repository: repository,
        userId: userId,
      )..initialize();

      _scrollController.addListener(_onScroll);
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _controller?.loadMore();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const AppLoadingState(message: 'Đang mở thông báo…');
    }

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final unread = controller.unreadCount;
        final title = unread > 0 ? 'Thông báo ($unread)' : 'Thông báo';

        return Scaffold(
          appBar: AppBar(
            title: Text(title),
            actions: [
              if (unread > 0)
                IconButton(
                  tooltip: 'Đánh dấu tất cả là đã đọc',
                  icon: const Icon(Icons.done_all_rounded),
                  onPressed: controller.isMarkingAllRead
                      ? null
                      : () => controller.markAllAsRead(),
                ),
              IconButton(
                tooltip: 'Đoạn chat',
                icon: const Icon(Icons.chat_bubble_outline_rounded),
                onPressed: () {
                  Navigator.of(context).pushNamed('/conversations');
                },
              ),
              IconButton(
                tooltip: 'Cài đặt thông báo',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () {
                  Navigator.of(context).pushNamed('/settings/push');
                },
              ),
            ],
          ),
          body: _buildBody(context, controller),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, NotificationController controller) {
    if (controller.isLoading && controller.items.isEmpty) {
      return const AppLoadingState(message: 'Đang tải thông báo…');
    }

    if (controller.errorMessage != null && controller.items.isEmpty) {
      return AppErrorState(
        message: controller.errorMessage!,
        onRetry: () => controller.fetchFirstPage(),
      );
    }

    if (controller.items.isEmpty) {
      return const AppEmptyState(
        icon: Icons.notifications_none_outlined,
        title: 'Chưa có thông báo',
        message:
            'Bạn sẽ nhận được thông báo khi có bạn bè tương tác hoặc kết quả duyệt câu hỏi.',
      );
    }

    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: controller.items.length + (controller.hasNext ? 1 : 0),
        separatorBuilder: (_, __) => const Divider(height: 1, thickness: 0.5),
        itemBuilder: (context, index) {
          if (index == controller.items.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }

          final item = controller.items[index];
          return NotificationTile(
            notification: item,
            onTap: () {
              controller.markAsRead(item.notificationId);
              NotificationDeepLinkHandler.handleTap(context, item);
            },
          );
        },
      ),
    );
  }
}
