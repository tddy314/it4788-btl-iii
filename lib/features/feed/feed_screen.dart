import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/errors/app_failure.dart';
import '../../core/widgets/app_network_image.dart';
import '../../core/widgets/app_states.dart';
import '../posts/paged_controller.dart';
import '../posts/post_card.dart';
import '../posts/post_composer_screen.dart';
import '../posts/post_detail_screen.dart';
import '../posts/post_models.dart';
import '../posts/posts_list_screen.dart';
import '../posts/posts_repository.dart';
import '../posts/picker_recovery.dart';
import 'feed_repository.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});
  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> with WidgetsBindingObserver {
  PagedController<FeedItem>? _controller;
  late FeedRepository _feed;
  late PostsRepository _posts;
  final _scroll = ScrollController();
  final _countCancel = CancelToken();
  bool _counting = false;
  int _newCount = 0;
  String? _countError;
  DateTime _since = DateTime.now();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_scrolled);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final d = AppScope.of(context);
    _feed = FeedRepository(d.api, onPostUnavailable: _remove);
    _posts = PostsRepository(d.api);
    _controller = PagedController(
      session: d.session,
      fetch: _feed.fetch,
      id: (FeedItem e) => e.id,
      cache: d.cache,
      resource: 'feed/home-v1',
      encode: (e) => e.toJson(),
      decode: FeedItem.fromJson,
      cacheable: (e) => e.post == null || e.post!.visibility == 'PUBLIC',
    );
    _controller!.addListener(_changed);
    unawaited(_controller!.start());
    WidgetsBinding.instance.addPostFrameCallback((_) => _recoverPicker());
  }

  Future<void> _recoverPicker() async {
    if (!mounted || _controller?.active != true) return;
    try {
      final recovery = PickerRecovery(AppScope.of(context).drafts);
      final pending = await recovery.pending(_controller!.userId);
      if (!mounted || !_controller!.active || pending == null) return;
      final original = pending['original'] == null
          ? null
          : Post.fromJson(pending['original']);
      await Navigator.of(context).push<int>(
        MaterialPageRoute(
          builder: (_) => PostComposerScreen(original: original),
        ),
      );
      if (mounted) await _refresh();
    } catch (_) {
      if (mounted) {
        setState(
          () => _countError =
              'Không khôi phục được bộ chọn ảnh. Bản nháp vẫn có thể mở lại.',
        );
      }
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _scrolled() {
    final c = _controller;
    if (c != null && c.failure == null && _scroll.position.extentAfter < 300) {
      unawaited(c.more());
    }
  }

  Future<void> _refresh() async {
    final began = DateTime.now();
    await _controller!.refresh();
    if (mounted && _controller!.failure == null) {
      setState(() {
        _newCount = 0;
        _since = began;
        _countError = null;
      });
    }
  }

  Future<void> _checkNew({bool manual = false}) async {
    if (_counting || _controller?.active != true || _controller!.busy) return;
    setState(() {
      _counting = true;
      _countError = null;
    });
    try {
      final value = await _feed.newCount(_since, _countCancel);
      if (mounted && _controller!.active) {
        setState(() => _newCount = value);
        if (manual && value == 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Chưa có hoạt động mới.')),
          );
        }
      }
    } on AppFailure catch (e) {
      if (mounted) setState(() => _countError = e.message);
      if (accessRevoked(e)) await _controller!.refresh();
    } finally {
      if (mounted) setState(() => _counting = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_checkNew());
  }

  void _update(Post p) => _controller?.replaceWhere(
    (e) => e.post?.id == p.id,
    (e) => e.withPost(p),
  );
  void _remove(int id) => _controller?.removeWhere((e) => e.post?.id == id);
  void _open(Post p) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PostDetailScreen(
        id: p.id,
        initial: p,
        onChanged: _update,
        onUnavailable: () => _remove(p.id),
      ),
    ),
  );
  Future<void> _compose() async {
    final id = await Navigator.of(
      context,
    ).push<int>(MaterialPageRoute(builder: (_) => const PostComposerScreen()));
    if (id == null || !mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Đã lưu bài viết.')));
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PostDetailScreen(
          id: id,
          onChanged: _update,
          onUnavailable: () => _remove(id),
        ),
      ),
    );
    if (mounted) await _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scroll.dispose();
    _countCancel.cancel();
    _controller?.removeListener(_changed);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c == null) return const AppLoadingState();
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: c.items.length + 2,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OutlinedButton.icon(
                    onPressed: _compose,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Bạn muốn chia sẻ điều gì?'),
                  ),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    children: [
                      TextButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => PostsListScreen(
                              onChanged: _update,
                              onUnavailable: _remove,
                            ),
                          ),
                        ),
                        icon: const Icon(Icons.article_outlined),
                        label: const Text('Bài của tôi'),
                      ),
                      TextButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => PostsListScreen(
                              videos: true,
                              onChanged: _update,
                              onUnavailable: _remove,
                            ),
                          ),
                        ),
                        icon: const Icon(Icons.video_library_outlined),
                        label: const Text('Video bài giảng'),
                      ),
                      TextButton.icon(
                        onPressed: _counting
                            ? null
                            : () => _checkNew(manual: true),
                        icon: const Icon(Icons.update),
                        label: const Text('Kiểm tra tin mới'),
                      ),
                    ],
                  ),
                  if (_newCount > 0)
                    FilledButton(
                      onPressed: _refresh,
                      child: Text('Có $_newCount hoạt động mới · Tải lại'),
                    ),
                  if (_countError != null) Text(_countError!),
                  if (c.cached && c.savedAt != null)
                    Text('Đang xem bản lưu lúc ${postTime(c.savedAt)}'),
                  if (c.storageWarning != null) Text(c.storageWarning!),
                  if (c.failure != null)
                    if (c.items.isEmpty)
                      AppErrorState(
                        message: c.failure!.message,
                        onRetry: _refresh,
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.failure!.message),
                          TextButton(
                            onPressed: _refresh,
                            child: const Text('Thử lại'),
                          ),
                        ],
                      ),
                  if (c.busy) const LinearProgressIndicator(),
                ],
              ),
            );
          }
          if (index == c.items.length + 1) {
            if (!c.initialized) return const AppLoadingState();
            if (c.failure != null || c.cached) {
              return const SizedBox(height: 24);
            }
            if (c.items.isEmpty && !c.busy && !c.hasNext && c.failure == null) {
              return const AppEmptyState(
                title: 'Bảng tin chưa có hoạt động',
                message: 'Bạn có thể tạo bài viết đầu tiên hoặc quay lại sau.',
              );
            }
            if (c.hasNext) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: TextButton(
                  onPressed: c.busy ? null : c.more,
                  child: const Text('Tải thêm'),
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                c.items.isEmpty
                    ? ''
                    : c.items.length >= 200
                    ? 'Đã tải 200 hoạt động. Kéo xuống để làm mới.'
                    : 'Bạn đã xem hết bảng tin.',
                textAlign: TextAlign.center,
              ),
            );
          }
          final item = c.items[index - 1];
          if (item.post != null) {
            return PostCard(
              key: ValueKey('post-${item.id}'),
              post: item.post!,
              repository: _posts,
              onChanged: _update,
              onUnavailable: () => _remove(item.post!.id),
              onOpen: () => _open(item.post!),
            );
          }
          final title = item.title.isNotEmpty
              ? item.title
              : switch (item.action) {
                  'SESSION_RESOLVED_APPROVED' =>
                    'Bộ câu hỏi có câu đã được chấp nhận',
                  'EARNED_BADGE' => 'Vừa nhận huy hiệu',
                  'REACHED_MILESTONE' => 'Vừa đạt cột mốc học tập',
                  _ => 'Hoạt động học tập mới',
                };
          return Card(
            key: ValueKey(item.id),
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      AppAvatar(
                        name: item.actor.name,
                        imageUrl: item.actor.avatar,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          item.actor.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(title),
                  const SizedBox(height: 8),
                  Text(
                    postTime(item.createdAt),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
