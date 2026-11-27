import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/errors/app_failure.dart';
import '../../core/network/connection_monitor.dart';
import '../../core/widgets/app_network_image.dart';
import 'media_viewer.dart';
import 'comments_sheet.dart';
import 'post_models.dart';
import 'posts_repository.dart';

class PostCard extends StatefulWidget {
  const PostCard({
    super.key,
    required this.post,
    required this.repository,
    required this.onChanged,
    required this.onUnavailable,
    this.onOpen,
    this.onComments,
    this.expanded = false,
  });
  final Post post;
  final PostsRepository repository;
  final ValueChanged<Post> onChanged;
  final VoidCallback onUnavailable;
  final VoidCallback? onOpen, onComments;
  final bool expanded;
  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  late Post _post = widget.post;
  late bool _expanded = widget.expanded;
  bool _busy = false, _reconcile = false;
  bool? _pendingLike;
  int _likeEpoch = 0;
  PersistentBottomSheetController? _commentsSheet;
  final _cancel = CancelToken();
  @override
  void didUpdateWidget(PostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post.id != widget.post.id) {
      final sheet = _commentsSheet;
      _commentsSheet = null;
      if (sheet != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => sheet.close());
      }
      ++_likeEpoch;
      _busy = false;
      _reconcile = false;
      _pendingLike = null;
    }
    if (!identical(oldWidget.post, widget.post)) _post = widget.post;
  }

  @override
  void dispose() {
    final sheet = _commentsSheet;
    if (sheet != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => sheet.close());
    }
    _cancel.cancel();
    super.dispose();
  }

  Future<void> _like() async {
    if (_busy) return;
    if (widget.repository.api.connection.status == ConnectionStatus.offline) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(AppFailure.offline.message)));
      return;
    }
    final userId = widget.repository.api.session.tokens?.userId;
    if (userId == null) return;
    final epoch = ++_likeEpoch;
    final postId = _post.id;
    bool current() =>
        mounted &&
        epoch == _likeEpoch &&
        widget.repository.api.session.tokens?.userId == userId;
    final desiredLike = !_post.liked;
    final checking = _reconcile;
    var writeStarted = false;
    setState(() {
      _busy = true;
      _pendingLike = _reconcile ? null : desiredLike;
    });
    try {
      final fresh = await widget.repository.get(postId, cancel: _cancel);
      if (!current()) return;
      if (_reconcile) {
        setState(() {
          _post = fresh;
          _reconcile = false;
        });
        widget.onChanged(fresh);
        return;
      }
      // An old cached card may predate a successful write with a lost response.
      // Read before toggling, so another attempt cannot undo that write.
      if (fresh.liked == desiredLike) {
        setState(() => _post = fresh);
        widget.onChanged(fresh);
        return;
      }
      setState(() => _post = fresh);
      writeStarted = true;
      final reaction = await widget.repository.like(postId, cancel: _cancel);
      if (!current()) return;
      setState(() => _post = fresh.withReaction(reaction));
      widget.onChanged(_post);
    } on AppFailure catch (error) {
      if (!mounted || !current()) return;
      if (accessRevoked(error)) widget.onUnavailable();
      // A failed preflight GET has not toggled anything. Only an ambiguous
      // write needs a subsequent read before allowing another toggle.
      _reconcile = checking || (writeStarted && uncertainWrite(error));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _reconcile
                ? 'Chưa rõ kết quả. Bấm “Kiểm tra lượt thích” để lấy trạng thái từ server.'
                : error.message,
          ),
        ),
      );
    } finally {
      if (mounted && epoch == _likeEpoch) {
        setState(() {
          _busy = false;
          _pendingLike = null;
        });
      }
    }
  }

  Future<void> _comments() async {
    if (_commentsSheet != null) return;
    final postId = _post.id;
    final sheet = _commentsSheet = showPostComments(context, postId: postId);
    await sheet.closed;
    if (identical(_commentsSheet, sheet)) _commentsSheet = null;
    if (!mounted || _post.id != postId) return;
    try {
      final latest = await widget.repository.get(_post.id, cancel: _cancel);
      if (mounted) widget.onChanged(latest);
    } on AppFailure catch (error) {
      if (mounted && accessRevoked(error)) widget.onUnavailable();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final liked = _pendingLike ?? _post.liked;
    final total =
        (_post.reactCount +
                (liked == _post.liked
                    ? 0
                    : liked
                    ? 1
                    : -1))
            .clamp(0, _post.reactCount + 1);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: widget.onOpen,
              child: Row(
                children: [
                  AppAvatar(
                    imageUrl: _post.author.avatar,
                    name: _post.author.name,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _post.author.name.isEmpty
                              ? 'Người dùng'
                              : _post.author.name,
                          style: theme.textTheme.titleMedium,
                        ),
                        Text(
                          '${postTime(_post.createdAt)}${_post.visibility == 'PUBLIC' ? ' · Công khai' : ''}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (widget.onOpen != null)
                    IconButton(
                      tooltip: 'Chi tiết bài viết',
                      onPressed: widget.onOpen,
                      icon: const Icon(Icons.more_horiz),
                    ),
                ],
              ),
            ),
            if (_post.subject.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_post.subject, style: theme.textTheme.labelLarge),
              ),
            if (_post.content.isNotEmpty) ...[
              const SizedBox(height: 12),
              if (_expanded)
                Text(_post.content)
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    final measure = TextPainter(
                      text: TextSpan(
                        text: _post.content,
                        style: DefaultTextStyle.of(context).style,
                      ),
                      textDirection: Directionality.of(context),
                      textScaler: MediaQuery.textScalerOf(context),
                      maxLines: 5,
                      ellipsis: '…',
                    )..layout(maxWidth: constraints.maxWidth);
                    final clipped = measure.didExceedMaxLines;
                    measure.dispose();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _post.content,
                          maxLines: 5,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (clipped)
                          TextButton(
                            onPressed: () => setState(() => _expanded = true),
                            child: const Text('Xem thêm'),
                          ),
                      ],
                    );
                  },
                ),
            ],
            if (_post.media.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (var i = 0; i < _post.media.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            MediaViewer(media: _post.media, initial: i),
                      ),
                    ),
                    child: AspectRatio(
                      aspectRatio: 16 / 10,
                      child: _post.media[i].isVideo
                          ? Stack(
                              fit: StackFit.expand,
                              children: [
                                ColoredBox(
                                  color:
                                      theme.colorScheme.surfaceContainerHighest,
                                ),
                                if (_post.media[i].thumbnail?.isNotEmpty ==
                                    true)
                                  AppNetworkImage(
                                    url: _post.media[i].thumbnail,
                                  ),
                                const Center(
                                  child: Chip(
                                    avatar: Icon(Icons.play_arrow),
                                    label: Text('Xem video'),
                                  ),
                                ),
                              ],
                            )
                          : _post.media[i].type == 'IMAGE'
                          ? AppNetworkImage(
                              url: _post.media[i].url,
                              semanticLabel: 'Ảnh ${i + 1} trong bài viết',
                            )
                          : const Center(
                              child: Text('Loại tệp chưa được hỗ trợ'),
                            ),
                    ),
                  ),
                ),
            ],
            if (_post.lecturerNote.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('Ghi chú giảng viên: ${_post.lecturerNote}'),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              children: [
                Text('$total lượt thích'),
                Text('${_post.commentCount} bình luận'),
              ],
            ),
            const Divider(),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: _busy ? null : _like,
                  style: TextButton.styleFrom(
                    foregroundColor: liked ? theme.colorScheme.primary : null,
                    disabledForegroundColor: liked
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  icon: Icon(liked ? Icons.thumb_up : Icons.thumb_up_outlined),
                  label: Text(
                    _reconcile
                        ? 'Kiểm tra lượt thích'
                        : liked
                        ? 'Đã thích'
                        : 'Thích',
                  ),
                ),
                TextButton.icon(
                  onPressed: widget.onComments ?? _comments,
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: const Text('Bình luận'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
