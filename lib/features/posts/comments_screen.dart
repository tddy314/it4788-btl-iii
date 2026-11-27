import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/text/emote_converter.dart';

import '../../app/app_scope.dart';
import '../../core/errors/app_failure.dart';
import '../../core/network/connection_monitor.dart';
import '../../core/storage/draft_store.dart';
import '../../core/validation/validators.dart';
import '../../core/widgets/app_network_image.dart';
import '../../core/widgets/app_states.dart';
import 'paged_controller.dart';
import 'post_models.dart';
import 'posts_repository.dart';

/// Reusable comments/replies UI. Only authors can delete; there is no edit/like.
class CommentsScreen extends StatefulWidget {
  const CommentsScreen({
    super.key,
    required this.postId,
    this.parentId,
    this.embedded = false,
    this.scrollController,
    this.onClose,
  });
  final int postId;
  final int? parentId;
  final bool embedded;
  final ScrollController? scrollController;
  final VoidCallback? onClose;
  @override
  State<CommentsScreen> createState() => _CommentsScreenState();
}

class _CommentsScreenState extends State<CommentsScreen> {
  PagedController<PostComment>? _list;
  late PostsRepository _repo;
  late DraftStore _drafts;
  late String _user;
  PostComment? _replyTarget;
  final _inputFocus = FocusNode();
  final _replies = <int, PagedController<PostComment>>{};
  final _confirmedReplies = <int, Map<int, PostComment>>{};
  final _replyCounts = <int, int>{};

  Iterable<PostComment> get _knownComments sync* {
    yield* _list?.items ?? <PostComment>[];
    yield* _confirmedComments.values;
    for (final list in _replies.values) {
      yield* list.items;
    }
    for (final items in _confirmedReplies.values) {
      yield* items.values;
    }
  }

  int _replyCount(PostComment parent) {
    final list = _replies[parent.id];
    // A complete fetched thread is more precise than a stale parent snapshot.
    // Never treat the first page (or the controller's memory cap) as the total.
    if (list != null &&
        list.savedAt != null &&
        !list.hasNext &&
        list.items.length < 200) {
      return <int>{
        for (final c in list.items)
          if (!c.deleted) c.id,
        for (final c in _confirmedReplies[parent.id]?.values ?? <PostComment>[])
          if (!c.deleted) c.id,
      }.length;
    }
    return _replyCounts[parent.id] ?? parent.replyCount;
  }

  void _adjustReplyCount(int parentId, int delta) {
    for (final parent in _knownComments) {
      if (parent.id == parentId) {
        _replyCounts[parentId] = (_replyCount(parent) + delta).clamp(
          0,
          1 << 31,
        );
        return;
      }
    }
  }

  String get _name =>
      'comment/${widget.postId}/${_replyTarget?.id ?? widget.parentId ?? 'root'}';
  final _text = TextEditingController();
  final _cancel = CancelToken();
  bool _sending = false, _uncertain = false, _ready = false, _reviewed = false;
  bool _durable = true;
  String? _pendingContent;
  final _confirmedComments = <int, PostComment>{};
  final _deleting = <int>{};
  final _deleteUnknown = <int>{};
  String? _message;
  Future<void> _writes = Future.value();
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_list != null) return;
    final d = AppScope.of(context);
    _repo = PostsRepository(d.api);
    _drafts = d.drafts;
    _user = d.session.tokens!.userId;
    _list = PagedController(
      session: d.session,
      id: (PostComment c) => c.id,
      fetch: (after, cancel) => _repo.comments(
        widget.postId,
        parent: widget.parentId,
        after: after,
        cancel: cancel,
      ),
    );
    _list!.addListener(_changed);
    unawaited(_list!.start());
    unawaited(_restore());
  }

  void _changed() {
    if (_list != null) {
      final received = _list!.items.map((c) => c.id).toSet();
      _confirmedComments.removeWhere((id, _) => received.contains(id));
      if (_list!.failure != null && accessRevoked(_list!.failure!)) {
        _confirmedComments.clear();
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _restore() async {
    try {
      final name = _name;
      final draft = await _drafts.read(userId: _user, name: name);
      if (!mounted || !_list!.active || name != _name) return;
      _text.text = textValue(draft?['content']);
      _uncertain = draft?['uncertain'] == true;
      _pendingContent = draft?['pending_content'] as String?;
      if (_uncertain && _pendingContent == null) {
        _pendingContent = EmoteConverter.convert(_text.text.trim());
      }
    } catch (_) {
      _message = 'Không đọc được bản nháp bình luận.';
    }
    if (mounted) setState(() => _ready = true);
  }

  Future<void> _save() {
    final name = _name;
    final data = {
      'content': _text.text,
      'uncertain': _uncertain,
      'pending_content': _pendingContent,
    };
    _writes = _writes
        .then((_) async {
          await _drafts.save(userId: _user, name: name, data: data);
          _durable = true;
        })
        .catchError((Object _) {
          _durable = false;
          if (mounted) {
            setState(
              () => _message = 'Không lưu được bản nháp bình luận trên máy.',
            );
          }
        });
    return _writes;
  }

  Future<void> _send() async {
    if (!_ready || _sending || _uncertain || !_list!.active) return;
    final invalid =
        Validators.requiredText(_text.text) ??
        Validators.maxWords(_text.text, 500);
    if (invalid != null) {
      setState(() => _message = invalid);
      return;
    }
    if (_repo.api.connection.status == ConnectionStatus.offline) {
      setState(() => _message = AppFailure.offline.message);
      return;
    }
    final content = _text.text;
    final parentId = _replyTarget?.id ?? widget.parentId;
    var writeStarted = false;
    setState(() {
      _sending = true;
      _pendingContent = EmoteConverter.convert(content.trim());
      _message = null;
      _reviewed = false;
    });
    try {
      await _repo.api.connection.check();
      if (_repo.api.connection.status == ConnectionStatus.offline) {
        if (mounted && _list!.active) {
          setState(() => _message = AppFailure.offline.message);
        }
        return;
      }
      if (!mounted || !_list!.active) return;
      _uncertain = true;
      await _save();
      if (!mounted || !_list!.active) return;
      if (!_durable) {
        _uncertain = false;
        throw const AppFailure(
          FailureKind.storage,
          'Không lưu được trạng thái gửi. Chưa gửi bình luận.',
        );
      }
      writeStarted = true;
      final confirmed = await _repo.comment(
        widget.postId,
        content,
        parent: parentId,
        cancel: _cancel,
      );
      if (!mounted || !_list!.active) return;
      _text.clear();
      _uncertain = false;
      setState(() {
        _pendingContent = null;
        if (_replyTarget != null) _adjustReplyCount(parentId!, 1);
        final confirmedItems = _replyTarget == null
            ? _confirmedComments
            : _confirmedReplies.putIfAbsent(parentId!, () => {});
        confirmedItems[confirmed.id] = confirmed;
        while (confirmedItems.length > 200) {
          confirmedItems.remove(confirmedItems.keys.first);
        }
      });
      await _save();
      _message = 'Đã gửi bình luận.';
      if (_replyTarget != null) await _replies[parentId]?.refresh();
      await _list!.refresh();
    } on AppFailure catch (e) {
      if (!mounted || !_list!.active) return;
      _uncertain = writeStarted && uncertainWrite(e);
      await _save();
      _message = _uncertain
          ? 'Chưa rõ bình luận đã gửi hay chưa. Tải lại và kiểm tra trước khi gửi lại.'
          : e.message;
      if (accessRevoked(e)) await _list!.invalidate(e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _review() async {
    final list = _replyTarget == null ? _list! : _replies[_replyTarget!.id]!;
    if (list.busy) return;
    await list.refresh();
    if (mounted && _list!.active) {
      setState(() => _reviewed = list.failure == null);
    }
  }

  Future<void> _refresh() async {
    if (_list!.busy) return;
    await _list!.refresh();
    if (!mounted || !_list!.active || _list!.failure != null) return;
    setState(() => _confirmedComments.clear());
    for (final list in _replies.values.toList()) {
      if (!mounted || !_list!.active) return;
      await list.refresh();
    }
  }

  Future<void> _selectReply(PostComment? target) async {
    if (!_ready || _sending || !_list!.active) return;
    if (_uncertain) {
      setState(
        () => _message =
            'Hãy kiểm tra kết quả gửi trước khi đổi bình luận đang trả lời.',
      );
      return;
    }
    if (_replyTarget?.id == target?.id) {
      _inputFocus.requestFocus();
      return;
    }
    setState(() => _ready = false);
    await _save();
    if (!mounted || !_list!.active) return;
    if (!_durable) {
      setState(() => _ready = true);
      return;
    }
    setState(() {
      _replyTarget = target;
      _text.clear();
      _pendingContent = null;
      _message = null;
      _reviewed = false;
    });
    if (target != null && !_replies.containsKey(target.id)) {
      final id = target.id;
      final list = PagedController<PostComment>(
        session: _repo.api.session,
        id: (comment) => comment.id,
        fetch: (after, cancel) => _repo.comments(
          widget.postId,
          parent: id,
          after: after,
          cancel: cancel,
        ),
      );
      _replies[id] = list;
      list.addListener(() {
        if (!mounted) return;
        final received = list.items.map((c) => c.id).toSet();
        _confirmedReplies[id]?.removeWhere((id, _) => received.contains(id));
        if (list.failure != null && accessRevoked(list.failure!)) {
          _confirmedReplies.remove(id);
        }
        setState(() {});
      });
      unawaited(list.start());
    }
    await _restore();
    if (mounted && _list!.active) _inputFocus.requestFocus();
  }

  Future<void> _allowRetry() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Đã kiểm tra bình luận?'),
        content: const Text(
          'Chỉ gửi lại nếu bình luận trước chưa xuất hiện. Bạn có thể tải thêm các trang để kiểm tra; server có thể xử lý chậm.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Chưa có, cho gửi lại'),
          ),
        ],
      ),
    );
    if (yes == true && mounted && _list!.active) {
      setState(() {
        _uncertain = false;
        _pendingContent = null;
      });
      await _save();
    }
  }

  Future<void> _delete(
    PostComment comment, {
    PagedController<PostComment>? thread,
  }) async {
    final list = thread ?? _list!;
    if (_deleting.contains(comment.id)) return;
    if (_deleteUnknown.contains(comment.id)) {
      if (list.busy) return;
      await list.refresh();
      if (!mounted || list.failure != null) return;
      _deleteUnknown.remove(comment.id);
      return;
    }
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Xóa bình luận của bạn?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _deleting.add(comment.id));
    try {
      await _repo.deleteComment(comment.id, cancel: _cancel);
      if (mounted && _list!.active) {
        if (thread != null) {
          for (final entry in _replies.entries) {
            if (identical(entry.value, thread)) {
              _adjustReplyCount(entry.key, -1);
              break;
            }
          }
        }
        _confirmedComments.remove(comment.id);
        for (final items in _confirmedReplies.values) {
          items.remove(comment.id);
        }
        list.removeWhere((c) => c.id == comment.id);
      }
    } on AppFailure catch (e) {
      if (uncertainWrite(e)) _deleteUnknown.add(comment.id);
      _message = e.message;
      if (accessRevoked(e)) await list.refresh();
    } finally {
      if (mounted) setState(() => _deleting.remove(comment.id));
    }
  }

  @override
  void dispose() {
    _cancel.cancel();
    _list?.removeListener(_changed);
    _list?.dispose();
    _text.dispose();
    _inputFocus.dispose();
    for (final list in _replies.values) {
      list.dispose();
    }
    super.dispose();
  }

  Widget _pendingTile() => Card(
    key: const ValueKey('pending-comment'),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Bạn', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Text(_pendingContent!),
          const SizedBox(height: 4),
          Text(
            _sending
                ? 'Đang gửi…'
                : _uncertain
                ? 'Chưa xác nhận được'
                : 'Gửi thất bại',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );

  Widget _commentSection(
    PostComment comment, {
    PagedController<PostComment>? thread,
    Set<int> ancestors = const {},
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AppAvatar(
                    name: comment.author.name,
                    imageUrl: comment.author.avatar,
                    size: 36,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      comment.author.name,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  if (!comment.deleted &&
                      comment.author.id?.toString() == _user)
                    IconButton(
                      tooltip: _deleteUnknown.contains(comment.id)
                          ? 'Kiểm tra kết quả xóa'
                          : 'Xóa bình luận',
                      onPressed: _deleting.contains(comment.id)
                          ? null
                          : () => _delete(comment, thread: thread),
                      icon: const Icon(Icons.delete_outline),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                comment.deleted
                    ? 'Bình luận không còn hiển thị.'
                    : comment.content,
              ),
              Text(
                postTime(comment.createdAt),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (!comment.deleted)
                TextButton(
                  key: ValueKey('reply-${comment.id}'),
                  onPressed: !_ready || _sending
                      ? null
                      : () => _selectReply(comment),
                  child: Text('Phản hồi (${_replyCount(comment)})'),
                ),
            ],
          ),
        ),
      ),
      if (!comment.deleted &&
          !ancestors.contains(comment.id) &&
          _replies.containsKey(comment.id))
        Padding(
          padding: EdgeInsets.only(left: ancestors.length < 2 ? 16 : 0),
          child: _replyThread(comment, {...ancestors, comment.id}),
        ),
    ],
  );

  Widget _replyThread(PostComment parent, Set<int> ancestors) {
    final list = _replies[parent.id]!;
    final allowed =
        _list!.active &&
        !(list.failure != null && accessRevoked(list.failure!));
    final replies = <PostComment>[
      if (allowed)
        for (final c
            in (_confirmedReplies[parent.id]?.values.toList() ??
                    <PostComment>[])
                .reversed)
          if (!list.items.any((item) => item.id == c.id)) c,
      ...list.items,
    ];
    return Column(
      key: ValueKey('replies-${parent.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (list.busy) const LinearProgressIndicator(),
        if (list.failure != null)
          AppErrorState(message: list.failure!.message, onRetry: list.refresh),
        if (allowed && _pendingContent != null && _replyTarget?.id == parent.id)
          _pendingTile(),
        for (final reply in replies)
          _commentSection(reply, thread: list, ancestors: ancestors),
        if (list.hasNext)
          TextButton(
            onPressed: list.busy ? null : list.more,
            child: const Text('Tải thêm phản hồi'),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    final reviewList = _replyTarget == null ? list : _replies[_replyTarget!.id];
    final canShowContent =
        list?.active == true &&
        !(list!.failure != null && accessRevoked(list.failure!));
    final comments = <PostComment>[
      if (canShowContent)
        for (final confirmed in _confirmedComments.values.toList().reversed)
          if (!list.items.any((c) => c.id == confirmed.id)) confirmed,
      ...?list?.items,
    ];
    final body = SafeArea(
      child: list == null
          ? const AppLoadingState()
          : LayoutBuilder(
              builder: (context, bounds) => Column(
                children: [
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _refresh,
                      child: ListView(
                        controller: widget.scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        children: [
                          if (list.failure != null)
                            AppErrorState(
                              message: list.failure!.message,
                              onRetry: _refresh,
                            ),
                          if (list.busy) const LinearProgressIndicator(),
                          if (_pendingContent != null &&
                              canShowContent &&
                              _replyTarget == null)
                            _pendingTile(),
                          if (list.initialized &&
                              comments.isEmpty &&
                              _pendingContent == null &&
                              !list.busy &&
                              list.failure == null)
                            const AppEmptyState(
                              title: 'Chưa có bình luận',
                              message: 'Hãy bắt đầu cuộc thảo luận.',
                            ),
                          for (final comment in comments)
                            _commentSection(comment),
                          if (list.hasNext)
                            TextButton(
                              onPressed: list.busy ? null : list.more,
                              child: const Text('Tải thêm bình luận'),
                            ),
                        ],
                      ),
                    ),
                  ),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: bounds.maxHeight * .72,
                    ),
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_message != null &&
                                _message != list.failure?.message)
                              Text(_message!),
                            if (_uncertain)
                              Wrap(
                                children: [
                                  TextButton(
                                    onPressed: _sending ? null : _review,
                                    child: const Text('Tải lại để kiểm tra'),
                                  ),
                                  if (_reviewed)
                                    if (reviewList!.items.any(
                                      (entry) =>
                                          !entry.deleted &&
                                          entry.author.id?.toString() ==
                                              _user &&
                                          entry.content ==
                                              EmoteConverter.convert(
                                                _text.text.trim(),
                                              ),
                                    ))
                                      TextButton(
                                        onPressed: () async {
                                          _text.clear();
                                          setState(() {
                                            _uncertain = false;
                                            _pendingContent = null;
                                            _reviewed = false;
                                            _message = null;
                                          });
                                          await _save();
                                        },
                                        child: const Text(
                                          'Đã thấy bình luận, đóng bản nháp',
                                        ),
                                      ),
                                  if (_reviewed)
                                    TextButton(
                                      onPressed: _allowRetry,
                                      child: const Text(
                                        'Tôi đã kiểm tra, cho gửi lại',
                                      ),
                                    ),
                                ],
                              ),
                            if (_replyTarget != null && canShowContent)
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Đang trả lời ${_replyTarget!.author.name}',
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Hủy trả lời',
                                    onPressed: !_ready || _sending
                                        ? null
                                        : () => _selectReply(null),
                                    icon: const Icon(Icons.close),
                                  ),
                                ],
                              ),
                            TextField(
                              controller: _text,
                              focusNode: _inputFocus,
                              enabled: _ready && !_sending && !_uncertain,
                              minLines: 1,
                              maxLines: 4,
                              onChanged: (_) {
                                if (_durable) _message = null;
                                _pendingContent = null;
                                unawaited(_save());
                                setState(() {});
                              },
                              decoration: InputDecoration(
                                labelText: 'Viết bình luận…',
                                counterText:
                                    '${Validators.wordCount(_text.text)}/500 từ',
                              ),
                            ),
                            FilledButton.icon(
                              onPressed:
                                  !_ready ||
                                      _sending ||
                                      _uncertain ||
                                      (list.failure != null &&
                                          accessRevoked(list.failure!))
                                  ? null
                                  : _send,
                              icon: const Icon(Icons.send_outlined),
                              label: Text(
                                _sending ? 'Đang gửi…' : 'Gửi bình luận',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
    if (widget.embedded) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Bình luận',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Đóng bình luận',
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Expanded(child: body),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.parentId == null ? 'Bình luận' : 'Phản hồi'),
      ),
      body: body,
    );
  }
}
