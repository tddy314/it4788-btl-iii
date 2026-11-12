import 'package:flutter/material.dart';

import '../../../../core/errors/app_failure.dart';
import '../../../../core/widgets/app_network_image.dart';
import '../../data/chat_repository.dart';
import '../../models/conversation_item.dart';

class CreateGroupSheet extends StatefulWidget {
  const CreateGroupSheet({
    super.key,
    required this.repository,
    required this.currentUserId,
  });

  final ChatRepository repository;
  final String currentUserId;

  @override
  State<CreateGroupSheet> createState() => _CreateGroupSheetState();
}

class _CreateGroupSheetState extends State<CreateGroupSheet> {
  final _nameController = TextEditingController();
  final _searchController = TextEditingController();

  List<ChatPartnerSummary> _friends = [];
  final Set<String> _selectedMemberIds = {};
  bool _isLoadingFriends = true;
  bool _isCreating = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    try {
      final list = await widget.repository.fetchFriendsForChat(limit: 50);
      if (mounted) {
        setState(() {
          _friends = list
              .where((f) => f.userId != widget.currentUserId)
              .toList();
          _isLoadingFriends = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingFriends = false);
      }
    }
  }

  Future<void> _handleCreateGroup() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập tên nhóm chat.')),
      );
      return;
    }

    if (_selectedMemberIds.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cần chọn tối thiểu 2 thành viên để tạo nhóm.'),
        ),
      );
      return;
    }

    setState(() => _isCreating = true);

    try {
      final conv = await widget.repository.createGroupConversation(
        name: name,
        memberIds: _selectedMemberIds.toList(),
        currentUserId: widget.currentUserId,
      );

      if (mounted) {
        Navigator.of(context).pop(conv);
      }
    } on AppFailure catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failure.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không thể tạo nhóm trò chuyện.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);

    final q = _searchQuery.trim().toLowerCase();
    final filtered = q.isEmpty
        ? _friends
        : _friends
              .where(
                (f) =>
                    f.fullName.toLowerCase().contains(q) ||
                    (f.studentCode?.toLowerCase().contains(q) ?? false),
              )
              .toList();

    final canCreate =
        _nameController.text.trim().isNotEmpty &&
        _selectedMemberIds.length >= 2 &&
        !_isCreating;

    return Padding(
      padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
      child: SafeArea(
        child: SizedBox(
          height: mediaQuery.size.height * 0.8,
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Tạo nhóm chat mới',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    FilledButton(
                      onPressed: canCreate ? _handleCreateGroup : null,
                      child: _isCreating
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Tạo nhóm'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // Ô nhập tên nhóm
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: TextField(
                  controller: _nameController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.group_outlined),
                    hintText: 'Đặt tên nhóm trò chuyện…',
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),

              // Thông tin số lượng thành viên đã chọn
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Thành viên đã chọn (${_selectedMemberIds.length}/2 tối thiểu):',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: _selectedMemberIds.length >= 2
                            ? Colors.green.shade700
                            : theme.colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (_selectedMemberIds.isNotEmpty)
                      TextButton(
                        onPressed: () =>
                            setState(() => _selectedMemberIds.clear()),
                        child: const Text('Bỏ chọn tất cả'),
                      ),
                  ],
                ),
              ),

              // Thanh tìm kiếm bạn bè
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: (val) => setState(() => _searchQuery = val),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search, size: 20),
                    hintText: 'Tìm theo tên hoặc MSSV…',
                    isDense: true,
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),

              // Danh sách bạn bè chọn nhiều
              Expanded(
                child: _isLoadingFriends
                    ? const Center(child: CircularProgressIndicator())
                    : filtered.isEmpty
                    ? Center(
                        child: Text(
                          _friends.isEmpty
                              ? 'Bạn chưa có bạn bè để thêm vào nhóm.'
                              : 'Không tìm thấy người phù hợp.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, indent: 68),
                        itemBuilder: (context, index) {
                          final friend = filtered[index];
                          final isSelected = _selectedMemberIds.contains(
                            friend.userId,
                          );

                          return CheckboxListTile(
                            value: isSelected,
                            onChanged: (checked) {
                              setState(() {
                                if (checked == true) {
                                  _selectedMemberIds.add(friend.userId);
                                } else {
                                  _selectedMemberIds.remove(friend.userId);
                                }
                              });
                            },
                            secondary: Stack(
                              children: [
                                AppAvatar(
                                  imageUrl: friend.avatarUrl,
                                  name: friend.fullName,
                                  size: 44,
                                ),
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    width: 11,
                                    height: 11,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF31A24C),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: theme.colorScheme.surface,
                                        width: 1.8,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            title: Text(
                              friend.fullName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: friend.studentCode != null
                                ? Text('MSSV: ${friend.studentCode}')
                                : Text('ID: ${friend.userId}'),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
