import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/widgets/app_network_image.dart';
import '../../../core/widgets/app_states.dart';
import '../controllers/conversations_controller.dart';
import '../data/chat_repository.dart';
import '../models/conversation_item.dart';
import 'widgets/create_group_sheet.dart';
import 'widgets/new_chat_sheet.dart';

class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key});

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  ConversationsController? _controller;
  ChatRepository? _repository;
  String _currentUserId = 'anonymous';
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  String _searchQuery = '';
  bool _initialized = false;
  bool _isOpeningChat = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      final deps = AppScope.of(context);
      _currentUserId = deps.session.tokens?.userId ?? 'anonymous';

      final repository = ChatRepository(
        api: deps.api,
        cache: deps.cache,
        mediaUploadService: deps.mediaUpload,
      );
      _repository = repository;

      _controller = ConversationsController(
        repository: repository,
        userId: _currentUserId,
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

  Future<void> _navigateToConversation(ConversationItem conv) async {
    await Navigator.of(context).pushNamed(
      '/chat',
      arguments: {
        'conversationId': conv.conversationId,
        'partnerName': conv.displayName,
        'partnerAvatarUrl': conv.displayAvatarUrl,
      },
    );
    if (mounted) {
      await _controller?.refresh();
    }
  }

  Future<void> _openCreateGroupSheet(BuildContext context) async {
    final repo = _repository;
    if (repo == null) return;
    final conv = await showModalBottomSheet<ConversationItem>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          CreateGroupSheet(repository: repo, currentUserId: _currentUserId),
    );
    if (conv != null && mounted) {
      await _navigateToConversation(conv);
    }
  }

  Future<void> _openNewChatSheet(BuildContext context) async {
    final repo = _repository;
    if (repo == null) return;
    final conv = await showModalBottomSheet<ConversationItem>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          NewChatSheet(repository: repo, currentUserId: _currentUserId),
    );
    if (conv != null && mounted) {
      await _navigateToConversation(conv);
    }
  }

  Future<void> _startDirectChatWithFriend(ChatPartnerSummary friend) async {
    final repo = _repository;
    if (repo == null || _isOpeningChat) return;
    setState(() => _isOpeningChat = true);
    try {
      final conv = await repo.createDirectConversation(
        friend.userId,
        currentUserId: _currentUserId,
      );
      if (mounted) {
        await _navigateToConversation(conv);
      }
    } on AppFailure catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failure.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Không thể mở cuộc trò chuyện với bạn bè này.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isOpeningChat = false);
      }
    }
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
        final query = _searchQuery.trim().toLowerCase();
        final filteredItems = query.isEmpty
            ? controller.items
            : controller.items
                  .where(
                    (item) => item.displayName.toLowerCase().contains(query),
                  )
                  .toList();
        final filteredFriends = query.isEmpty
            ? controller.friends
            : controller.friends
                  .where(
                    (friend) =>
                        friend.fullName.toLowerCase().contains(query) ||
                        (friend.studentCode?.toLowerCase().contains(query) ??
                            false),
                  )
                  .toList();

        return Scaffold(
          appBar: AppBar(
            title: const Text('Đoạn chat'),
            actions: [
              IconButton(
                tooltip: 'Tạo nhóm chat mới',
                icon: const Icon(Icons.group_add_outlined),
                onPressed: () => _openCreateGroupSheet(context),
              ),
              IconButton(
                tooltip: 'Cuộc trò chuyện mới',
                icon: const Icon(Icons.edit_note_rounded),
                onPressed: () => _openNewChatSheet(context),
              ),
            ],
          ),
          body: Column(
            children: [
              if (_isOpeningChat) const LinearProgressIndicator(minHeight: 2),
              // Thanh tìm kiếm nhanh bạn bè và cuộc trò chuyện
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: (val) => setState(() => _searchQuery = val),
                  decoration: InputDecoration(
                    hintText: 'Tìm bạn bè hoặc cuộc trò chuyện…',
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

              if (filteredFriends.isNotEmpty)
                _buildFriendsStrip(context, filteredFriends),

              // Danh sách hội thoại
              Expanded(
                child: _buildList(
                  context,
                  controller,
                  filteredItems,
                  hasFriends: filteredFriends.isNotEmpty,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFriendsStrip(
    BuildContext context,
    List<ChatPartnerSummary> friends,
  ) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
          child: Text(
            'Bạn bè (${friends.length})',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        SizedBox(
          height: 86,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: friends.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final friend = friends[index];
              return SizedBox(
                width: 64,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _isOpeningChat
                      ? null
                      : () => _startDirectChatWithFriend(friend),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          AppAvatar(
                            imageUrl: friend.avatarUrl,
                            name: friend.fullName,
                            size: 48,
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              width: 13,
                              height: 13,
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF31A24C,
                                ), // Messenger online green
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: theme.colorScheme.surface,
                                  width: 2.2,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        friend.fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }

  Widget _buildList(
    BuildContext context,
    ConversationsController controller,
    List<ConversationItem> items, {
    required bool hasFriends,
  }) {
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
      if (hasFriends) {
        final theme = Theme.of(context);
        return RefreshIndicator(
          onRefresh: controller.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
            children: [
              Icon(
                Icons.chat_bubble_outline_rounded,
                size: 44,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text(
                'Chưa có tin nhắn nào',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Chọn bạn bè phía trên hoặc bấm nút tạo mới ở góc trên để bắt đầu trò chuyện.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
      }
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
            onTap: () => _navigateToConversation(item),
          );
        },
      ),
    );
  }
}
