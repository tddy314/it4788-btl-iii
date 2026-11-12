import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../../core/errors/app_failure.dart';
import '../../../../core/widgets/app_network_image.dart';
import '../../../../core/widgets/app_states.dart';
import '../../data/chat_repository.dart';
import '../../models/conversation_item.dart';

class NewChatSheet extends StatefulWidget {
  const NewChatSheet({
    super.key,
    required this.repository,
    required this.currentUserId,
  });

  final ChatRepository repository;
  final String currentUserId;

  @override
  State<NewChatSheet> createState() => _NewChatSheetState();
}

class _NewChatSheetState extends State<NewChatSheet> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  CancelToken? _cancelToken;

  List<ChatPartnerSummary> _friends = [];
  List<ChatPartnerSummary> _searchResults = [];
  bool _loadingFriends = true;
  bool _searching = false;
  bool _creating = false;
  String? _errorMessage;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    try {
      final list = await widget.repository.fetchFriendsForChat();
      if (!mounted) return;
      setState(() {
        _friends = list.where((p) => p.userId != widget.currentUserId).toList();
        _loadingFriends = false;
        _errorMessage = null;
      });
    } on AppFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _loadingFriends = false;
        _errorMessage = failure.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingFriends = false;
        _errorMessage = 'Không thể tải danh sách bạn bè.';
      });
    }
  }

  void _onQueryChanged(String value) {
    final trimmed = value.trim();
    setState(() {
      _query = trimmed;
      _errorMessage = null;
    });
    _debounce?.cancel();
    _cancelToken?.cancel();

    if (trimmed.isEmpty) {
      setState(() {
        _searchResults = [];
        _searching = false;
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 350), () {
      _performSearch(trimmed);
    });
  }

  Future<void> _performSearch(String query) async {
    final token = CancelToken();
    _cancelToken = token;
    setState(() {
      _searching = true;
      _errorMessage = null;
    });

    try {
      final results = await widget.repository.searchUsersForChat(
        query,
        cancelToken: token,
      );
      if (!mounted || token.isCancelled || _query != query) return;
      setState(() {
        _searchResults = results
            .where((p) => p.userId != widget.currentUserId)
            .toList();
        _searching = false;
      });
    } on AppFailure catch (failure) {
      if (!mounted || token.isCancelled || _query != query) return;
      setState(() {
        _searching = false;
        _errorMessage = failure.message;
      });
    } catch (_) {
      if (!mounted || token.isCancelled || _query != query) return;
      setState(() {
        _searching = false;
        _errorMessage = 'Không thể tìm kiếm người dùng lúc này.';
      });
    }
  }

  Future<void> _startChatWith(String targetUserId) async {
    if (_creating) return;
    if (targetUserId == widget.currentUserId) {
      setState(() {
        _errorMessage = 'Không thể tạo cuộc trò chuyện với chính mình.';
      });
      return;
    }

    setState(() {
      _creating = true;
      _errorMessage = null;
    });

    try {
      final conv = await widget.repository.createDirectConversation(
        targetUserId,
        currentUserId: widget.currentUserId,
      );
      if (!mounted) return;
      Navigator.of(context).pop(conv);
    } on AppFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _creating = false;
        _errorMessage = failure.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _creating = false;
        _errorMessage = 'Không thể tạo cuộc trò chuyện với người này.';
      });
    }
  }

  Future<void> _openByIdDialog() async {
    final idController = TextEditingController();
    final chosenId = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nhập user_id trực tiếp'),
        content: TextField(
          controller: idController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            hintText: 'Nhập số user_id (không phải MSSV), vd: 2',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () {
              final raw = idController.text.trim();
              final parsed = int.tryParse(raw);
              if (parsed == null || parsed <= 0) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                    content: Text('Vui lòng nhập user_id là số nguyên dương.'),
                  ),
                );
                return;
              }
              Navigator.of(ctx).pop(raw);
            },
            child: const Text('Bắt đầu'),
          ),
        ],
      ),
    );
    idController.dispose();
    if (chosenId != null && mounted) {
      await _startChatWith(chosenId);
    }
  }

  String _subtitleFor(ChatPartnerSummary person) {
    final parts = <String>[
      if (person.studentCode != null && person.studentCode!.isNotEmpty)
        'MSSV: ${person.studentCode}',
      if (person.subtitle != null && person.subtitle!.isNotEmpty)
        person.subtitle!,
      'ID: ${person.userId}',
    ];
    return parts.join(' • ');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _cancelToken?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = _query.isEmpty ? _friends : _searchResults;
    final isLoading = _query.isEmpty ? _loadingFriends : _searching;

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Cuộc trò chuyện mới',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _creating ? null : _openByIdDialog,
                    icon: const Icon(Icons.dialpad, size: 18),
                    label: const Text('Nhập ID'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                controller: _searchController,
                onChanged: _onQueryChanged,
                decoration: InputDecoration(
                  hintText: 'Tìm bạn học theo tên hoặc MSSV…',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            _onQueryChanged('');
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
            if (_creating) const LinearProgressIndicator(),
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Material(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: theme.colorScheme.onErrorContainer,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(
                              color: theme.colorScheme.onErrorContainer,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _query.isEmpty ? 'Bạn bè của bạn' : 'Kết quả tìm kiếm',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.outline,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            Expanded(
              child: isLoading
                  ? const AppLoadingState(message: 'Đang tải danh sách…')
                  : items.isEmpty
                  ? AppEmptyState(
                      icon: Icons.people_outline,
                      title: _query.isEmpty
                          ? 'Chưa có bạn bè'
                          : 'Không tìm thấy người dùng',
                      message: _query.isEmpty
                          ? 'Gõ tên hoặc MSSV bạn học vào ô tìm kiếm phía trên để bắt đầu nhắn tin.'
                          : 'Hãy thử tìm bằng tên hoặc MSSV khác.',
                    )
                  : ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, indent: 72),
                      itemBuilder: (context, index) {
                        final person = items[index];
                        return ListTile(
                          enabled: !_creating,
                          leading: AppAvatar(
                            imageUrl: person.avatarUrl,
                            name: person.fullName,
                            size: 44,
                          ),
                          title: Text(
                            person.fullName,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(_subtitleFor(person)),
                          trailing: const Icon(Icons.chat_outlined, size: 20),
                          onTap: () => _startChatWith(person.userId),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
