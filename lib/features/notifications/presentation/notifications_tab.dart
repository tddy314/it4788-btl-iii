import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/widgets/app_states.dart';
import '../controllers/notification_controller.dart';
import '../data/notification_repository.dart';
import 'widgets/notification_deep_link_handler.dart';
import 'widgets/notification_tile.dart';

enum NotificationFilter { all, unread, academic }

class NotificationsTab extends StatefulWidget {
  const NotificationsTab({super.key});

  @override
  State<NotificationsTab> createState() => _NotificationsTabState();
}

class _NotificationsTabState extends State<NotificationsTab> {
  NotificationController? _controller;
  final _scrollController = ScrollController();
  NotificationFilter _selectedFilter = NotificationFilter.all;
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
          body: Column(
            children: [
              // Thanh lọc danh mục thông báo
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    FilterChip(
                      label: const Text('Tất cả'),
                      selected: _selectedFilter == NotificationFilter.all,
                      onSelected: (_) => setState(
                        () => _selectedFilter = NotificationFilter.all,
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: Text(
                        unread > 0 ? 'Chưa đọc ($unread)' : 'Chưa đọc',
                      ),
                      selected: _selectedFilter == NotificationFilter.unread,
                      onSelected: (_) => setState(
                        () => _selectedFilter = NotificationFilter.unread,
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      avatar: const Icon(Icons.school_outlined, size: 16),
                      label: const Text('Ngân hàng đề'),
                      selected: _selectedFilter == NotificationFilter.academic,
                      onSelected: (_) => setState(
                        () => _selectedFilter = NotificationFilter.academic,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // Danh sách thông báo
              Expanded(child: _buildBody(context, controller)),
            ],
          ),
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

    var displayItems = controller.items;
    if (_selectedFilter == NotificationFilter.unread) {
      displayItems = displayItems.where((e) => !e.isRead).toList();
    } else if (_selectedFilter == NotificationFilter.academic) {
      displayItems = displayItems.where((e) {
        final t = e.type.toUpperCase();
        return t.contains('SESSION') || t.contains('QUESTION');
      }).toList();
    }

    if (displayItems.isEmpty) {
      final emptyMsg = switch (_selectedFilter) {
        NotificationFilter.unread => 'Không có thông báo chưa đọc nào.',
        NotificationFilter.academic =>
          'Chưa có thông báo liên quan đến ngân hàng câu hỏi.',
        NotificationFilter.all => 'Bạn sẽ nhận được thông báo khi có bạn bè tương tác hoặc kết quả duyệt câu hỏi.',
      };
      return AppEmptyState(
        icon: Icons.notifications_none_outlined,
        title: 'Chưa có thông báo',
        message: emptyMsg,
      );
    }

    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: displayItems.length + (controller.hasNext ? 1 : 0),
        separatorBuilder: (_, _) => const Divider(height: 1, thickness: 0.5),
        itemBuilder: (context, index) {
          if (index == displayItems.length) {
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

          final item = displayItems[index];
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
