import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/errors/app_failure.dart';
import '../../core/widgets/app_states.dart';
import 'comments_screen.dart';
import 'post_card.dart';
import 'post_composer_screen.dart';
import 'post_models.dart';
import 'posts_repository.dart';
import 'report_post_screen.dart';

class PostDetailScreen extends StatefulWidget {
  const PostDetailScreen({
    super.key,
    required this.id,
    this.initial,
    this.onChanged,
    this.onUnavailable,
  });
  final int id;
  final Post? initial;
  final ValueChanged<Post>? onChanged;
  final VoidCallback? onUnavailable;
  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  PostsRepository? _repo;
  Post? _post;
  AppFailure? _failure;
  bool _busy = false, _deleting = false, _deleteUncertain = false;
  final _cancel = CancelToken();
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_repo != null) return;
    _repo = PostsRepository(AppScope.of(context).api);
    _post = widget.initial;
    unawaited(_load());
  }

  Future<void> _load() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      final post = await _repo!.get(widget.id, cancel: _cancel);
      if (!mounted) return;
      setState(() {
        _post = post;
        _deleteUncertain = false;
      });
      widget.onChanged?.call(post);
    } on AppFailure catch (e) {
      if (!mounted) return;
      setState(() => _failure = e);
      if (accessRevoked(e)) {
        _post = null;
        widget.onUnavailable?.call();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit() async {
    final id = await Navigator.of(context).push<int>(
      MaterialPageRoute(builder: (_) => PostComposerScreen(original: _post)),
    );
    if (id != null && mounted) await _load();
  }

  Future<void> _delete() async {
    if (_deleting) return;
    if (_deleteUncertain) {
      await _load();
      return;
    }
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Xóa bài viết?'),
        content: const Text(
          'Bài viết và media đính kèm sẽ bị xóa khỏi server.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Xóa bài'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await _repo!.delete(widget.id, cancel: _cancel);
      if (!mounted) return;
      widget.onUnavailable?.call();
      Navigator.of(context).pop();
    } on AppFailure catch (e) {
      if (!mounted) return;
      _deleteUncertain = uncertainWrite(e);
      setState(() => _failure = e);
      if (accessRevoked(e)) {
        _post = null;
        widget.onUnavailable?.call();
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _comments() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CommentsScreen(postId: widget.id),
      ),
    );
    if (mounted) await _load();
  }

  @override
  void dispose() {
    _cancel.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = _post;
    final owner =
        p?.author.id?.toString() == AppScope.of(context).session.tokens?.userId;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bài viết'),
        actions: [
          if (p != null)
            PopupMenuButton<String>(
              enabled: !_deleting && !_busy,
              onSelected: (action) {
                if (action == 'edit') _edit();
                if (action == 'delete') _delete();
                if (action == 'report') {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ReportPostScreen(postId: widget.id),
                    ),
                  );
                }
              },
              itemBuilder: (_) => [
                if (owner && p.type == 'SOCIAL_POST')
                  const PopupMenuItem(
                    value: 'edit',
                    child: Text('Sửa bài viết'),
                  ),
                if (owner)
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(
                      _deleteUncertain
                          ? 'Kiểm tra kết quả xóa'
                          : 'Xóa bài viết',
                    ),
                  ),
                if (!owner)
                  const PopupMenuItem(
                    value: 'report',
                    child: Text('Báo cáo bài viết'),
                  ),
              ],
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (_busy || _deleting) const LinearProgressIndicator(),
            if (_failure != null)
              AppErrorState(
                message: _deleteUncertain
                    ? 'Chưa rõ bài đã xóa hay chưa. Kiểm tra lại trước khi thực hiện tiếp.'
                    : _failure!.message,
                onRetry: _load,
              ),
            if (p != null)
              PostCard(
                post: p,
                repository: _repo!,
                expanded: true,
                onChanged: (post) {
                  setState(() => _post = post);
                  widget.onChanged?.call(post);
                },
                onUnavailable: () {
                  setState(() => _post = null);
                  widget.onUnavailable?.call();
                  unawaited(_load());
                },
                onComments: _comments,
              ),
          ],
        ),
      ),
    );
  }
}
