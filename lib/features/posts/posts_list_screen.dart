import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/widgets/app_states.dart';
import 'paged_controller.dart';
import 'post_card.dart';
import 'post_detail_screen.dart';
import 'post_models.dart';
import 'posts_repository.dart';

class PostsListScreen extends StatefulWidget {
  const PostsListScreen({
    super.key,
    this.videos = false,
    this.onChanged,
    this.onUnavailable,
    this.canConfirm,
  });
  final bool videos;
  final ValueChanged<Post>? onChanged;
  final ValueChanged<int>? onUnavailable;
  final bool Function(Post)? canConfirm;
  @override
  State<PostsListScreen> createState() => _PostsListScreenState();
}

class _PostsListScreenState extends State<PostsListScreen> {
  PagedController<Post>? _controller;
  late PostsRepository _repo;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final d = AppScope.of(context);
    _repo = PostsRepository(d.api);
    _controller = PagedController(
      session: d.session,
      id: (Post p) => p.id,
      fetch: (after, cancel) => widget.videos
          ? _repo.videos(after: after, cancel: cancel)
          : _repo.mine(after: after, cancel: cancel),
    );
    _controller!.addListener(_changed);
    unawaited(_controller!.start());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _updatePost(Post next) {
    _controller?.replaceWhere((item) => item.id == next.id, (_) => next);
    widget.onChanged?.call(next);
  }

  void _removePost(int id) {
    _controller?.removeWhere((item) => item.id == id);
    widget.onUnavailable?.call(id);
  }

  void _open(Post p) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PostDetailScreen(
        id: p.id,
        initial: p,
        onChanged: _updatePost,
        onUnavailable: () => _removePost(p.id),
      ),
    ),
  );
  @override
  void dispose() {
    _controller?.removeListener(_changed);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.videos ? 'Video bài giảng' : 'Bài của tôi'),
      ),
      body: c == null
          ? const AppLoadingState()
          : RefreshIndicator(
              onRefresh: c.refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  if (c.busy) const LinearProgressIndicator(),
                  if (c.failure != null)
                    AppErrorState(
                      message: c.failure!.message,
                      onRetry: c.refresh,
                    ),
                  if (c.initialized &&
                      !c.busy &&
                      c.items.isEmpty &&
                      c.failure == null)
                    AppEmptyState(
                      title: widget.videos
                          ? 'Chưa có video bài giảng'
                          : 'Bạn chưa có bài viết',
                    ),
                  for (final p in c.items) ...[
                    PostCard(
                      key: ValueKey(p.id),
                      post: p,
                      repository: _repo,
                      onChanged: _updatePost,
                      onUnavailable: () => _removePost(p.id),
                      onOpen: () => _open(p),
                    ),
                    if (widget.canConfirm?.call(p) == true)
                      TextButton.icon(
                        onPressed: () => Navigator.of(context).pop(p),
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Đây là bài đã đăng, đóng bản nháp'),
                      ),
                  ],
                  if (c.hasNext)
                    TextButton(
                      onPressed: c.busy ? null : c.more,
                      child: const Text('Tải thêm'),
                    ),
                ],
              ),
            ),
    );
  }
}
