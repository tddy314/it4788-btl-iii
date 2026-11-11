import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/widgets/app_network_image.dart';
import '../../../core/widgets/app_states.dart';
import '../controllers/conversations_controller.dart';
import '../data/chat_repository.dart';
import '../models/conversation_item.dart';

class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key});

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  ConversationsController? _controller;
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  String _searchQuery = '';
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      final deps = AppScope.of(context);
      final userId = deps.session.tokens?.userId ?? 'anonymous';

      final repository = ChatRepository(
        api: deps.api,
        cache: deps.cache,
        mediaUploadService: deps.mediaUpload,
      );

      _controller = ConversationsController(
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
    _searchController.dispose();
    _controller?.dispose();
    super.dispose();
  }

  void _openNewChatDialog(BuildContext context) {
    final targetIdController = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nhắn tin với bạn học'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Nhập ID tài khoản (user_id) của người muốn trò chuyện:',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: targetIdController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                hintText: 'Ví dụ: 2 hoặc 5',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () async {
              final targetId = targetIdController.text.trim();
              final parsed = int.tryParse(targetId);
              if (parsed == null || parsed <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Vui lòng nhập ID người dùng là số nguyên dương.',
                    ),
                  ),
                );
                return;
              }
              Navigator.of(ctx).pop();
              try {
                final deps = AppScope.of(context);
                final repo = ChatRepository(
                  api: deps.api,
                  cache: deps.cache,
                  mediaUploadService: deps.mediaUpload,
                );
                final conv = await repo.createDirectConversation(
                  targetId,
                  currentUserId: deps.session.tokens?.userId,
                );
                if (context.mounted) {
                  Navigator.of(context).pushNamed(
                    '/chat',
                    arguments: {
                      'conversationId': conv.conversationId,
                      'partnerName': conv.displayName,
                      'partnerAvatarUrl': conv.displayAvatarUrl,
                    },
                  );
                }
              } on AppFailure catch (failure) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(failure.message)));
                }
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Không thể tạo cuộc trò chuyện với người này.',
                      ),
                    ),
                  );
                }
              }
            },
            child: const Text('Bắt đầu'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const Scaffold(
        body: SafeArea(
          child: AppLoadingState(message: 'Đang mở danh sách đoạn chat…'),
        ),
      );
    }

    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final filteredItems = _searchQuery.isEmpty
            ? controller.items
            : controller.items
                  .where(
                    (item) => item.displayName.toLowerCase().contains(
                      _searchQuery.toLowerCase(),
                    ),
                  )
                  .toList();

        return Scaffold(
          appBar: AppBar(
            title: const Text('Đoạn chat'),
            actions: [
              IconButton(
                tooltip: 'Cuộc trò chuyện mới',
                icon: const Icon(Icons.edit_note_rounded),
                onPressed: () => _openNewChatDialog(context),
              ),
            ],
          ),
          body: Column(
            children: [
              // Thanh tìm kiếm nhanh cuộc trò chuyện
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: (val) => setState(() => _searchQuery = val),
                  decoration: InputDecoration(
                    hintText: 'Tìm kiếm cuộc trò chuyện…',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  ),
                ),
              ),

              // Danh sách hội thoại
              Expanded(child: _buildList(context, controller, filteredItems)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildList(
    BuildContext context,
    ConversationsController controller,
    List<ConversationItem> items,
  ) {
    if (controller.isLoading && items.isEmpty) {
      return const AppLoadingState(message: 'Đang tải các cuộc trò chuyện…');
    }

    if (controller.errorMessage != null && items.isEmpty) {
      return AppErrorState(
        message: controller.errorMessage!,
        onRetry: () => controller.fetchFirstPage(),
      );
    }

    if (items.isEmpty) {
      return const AppEmptyState(
        icon: Icons.chat_bubble_outline_rounded,
        title: 'Chưa có tin nhắn',
        message:
            'Hãy bắt đầu trò chuyện với bạn bè để cùng ôn luyện ngân hàng đề.',
      );
    }

    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: items.length + (controller.hasNext ? 1 : 0),
        separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
        itemBuilder: (context, index) {
          if (index == items.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }

          final item = items[index];
          final theme = Theme.of(context);
          final hasUnread = item.unreadCount > 0;

          return ListTile(
            leading: AppAvatar(
              imageUrl: item.displayAvatarUrl,
              name: item.displayName,
              size: 48,
            ),
            title: Text(
              item.displayName,
              style: TextStyle(
                fontWeight: hasUnread ? FontWeight.bold : FontWeight.w600,
              ),
            ),
            subtitle: Text(
              item.lastMessageContent ?? 'Bắt đầu cuộc trò chuyện',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: hasUnread
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.outline,
                fontWeight: hasUnread ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            trailing: hasUnread
                ? Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      item.unreadCount.toString(),
                      style: TextStyle(
                        color: theme.colorScheme.onPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                : null,
            onTap: () {
              Navigator.of(context).pushNamed(
                '/chat',
                arguments: {
                  'conversationId': item.conversationId,
                  'partnerName': item.displayName,
                  'partnerAvatarUrl': item.displayAvatarUrl,
                },
              );
            },
          );
        },
      ),
    );
  }
}
