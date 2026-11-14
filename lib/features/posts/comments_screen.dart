import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

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
  const CommentsScreen({super.key, required this.postId, this.parentId});
  final int postId;
  final int? parentId;
  @override
  State<CommentsScreen> createState() => _CommentsScreenState();
}

class _CommentsScreenState extends State<CommentsScreen> {
  PagedController<PostComment>? _list;
  late PostsRepository _repo;
  late DraftStore _drafts;
  late String _user;
  String get _name => 'comment/${widget.postId}/${widget.parentId ?? 'root'}';
  final _text = TextEditingController();
  final _cancel = CancelToken();
  bool _sending = false, _uncertain = false, _ready = false, _reviewed = false;
  bool _durable = true;
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
    if (mounted) setState(() {});
  }

  Future<void> _restore() async {
    try {
      final draft = await _drafts.read(userId: _user, name: _name);
      if (!mounted) return;
      _text.text = textValue(draft?['content']);
      _uncertain = draft?['uncertain'] == true;
    } catch (_) {
      _message = 'Không đọc được bản nháp bình luận.';
    }
    if (mounted) setState(() => _ready = true);
  }

  Future<void> _save() {
    final data = {'content': _text.text, 'uncertain': _uncertain};
    _writes = _writes
        .then((_) async {
          await _drafts.save(userId: _user, name: _name, data: data);
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
    if (_sending || _uncertain || !_list!.active) return;
    final invalid =
        Validators.requiredText(_text.text) ??
        Validators.maxWords(_text.text, 500);
    if (invalid != null) {
      setState(() => _message = invalid);
      return;
    }
    setState(() {
      _sending = true;
      _message = null;
      _reviewed = false;
    });
    try {
      await _repo.api.connection.check();
      if (_repo.api.connection.status == ConnectionStatus.offline) {
        if (mounted) setState(() => _message = AppFailure.offline.message);
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
      await _repo.comment(
        widget.postId,
        _text.text,
        parent: widget.parentId,
        cancel: _cancel,
      );
      if (!mounted || !_list!.active) return;
      _text.clear();
      _uncertain = false;
      await _save();
      _message = 'Đã gửi bình luận.';
      await _list!.refresh();
    } on AppFailure catch (e) {
      _uncertain = uncertainWrite(e);
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
    if (_list!.busy) return;
    await _list!.refresh();
    if (mounted) setState(() => _reviewed = _list!.failure == null);
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
    if (yes == true && mounted) {
      setState(() => _uncertain = false);
      await _save();
    }
  }

  Future<void> _delete(PostComment comment) async {
    if (_deleting.contains(comment.id)) return;
    if (_deleteUnknown.contains(comment.id)) {
      await _review();
      if (!mounted || _list!.failure != null) return;
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
      if (mounted) _list!.removeWhere((c) => c.id == comment.id);
    } on AppFailure catch (e) {
      if (uncertainWrite(e)) _deleteUnknown.add(comment.id);
      _message = e.message;
      if (accessRevoked(e)) await _list!.refresh();
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.parentId == null ? 'Bình luận' : 'Phản hồi'),
      ),
      body: SafeArea(
        child: list == null
            ? const AppLoadingState()
            : LayoutBuilder(
                builder: (context, bounds) => Column(
                  children: [
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: list.refresh,
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                          children: [
                            if (list.failure != null)
                              AppErrorState(
                                message: list.failure!.message,
                                onRetry: list.refresh,
                              ),
                            if (list.busy) const LinearProgressIndicator(),
                            if (list.initialized &&
                                list.items.isEmpty &&
                                !list.busy &&
                                list.failure == null)
                              const AppEmptyState(
                                title: 'Chưa có bình luận',
                                message: 'Hãy bắt đầu cuộc thảo luận.',
                              ),
                            for (final comment in list.items)
                              Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleSmall,
                                            ),
                                          ),
                                          if (!comment.deleted &&
                                              comment.author.id?.toString() ==
                                                  _user)
                                            IconButton(
                                              tooltip:
                                                  _deleteUnknown.contains(
                                                    comment.id,
                                                  )
                                                  ? 'Kiểm tra kết quả xóa'
                                                  : 'Xóa bình luận',
                                              onPressed:
                                                  _deleting.contains(comment.id)
                                                  ? null
                                                  : () => _delete(comment),
                                              icon: const Icon(
                                                Icons.delete_outline,
                                              ),
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
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                      if (!comment.deleted)
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.of(context).push(
                                                MaterialPageRoute<void>(
                                                  builder: (_) =>
                                                      CommentsScreen(
                                                        postId: widget.postId,
                                                        parentId: comment.id,
                                                      ),
                                                ),
                                              ),
                                          child: Text(
                                            'Phản hồi (${comment.replyCount})',
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
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
                                      if (list.items.any(
                                        (entry) =>
                                            !entry.deleted &&
                                            entry.author.id?.toString() ==
                                                _user &&
                                            entry.content == _text.text.trim(),
                                      ))
                                        TextButton(
                                          onPressed: () async {
                                            _text.clear();
                                            setState(() {
                                              _uncertain = false;
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
                              TextField(
                                controller: _text,
                                enabled: _ready && !_sending && !_uncertain,
                                minLines: 1,
                                maxLines: 4,
                                onChanged: (_) {
                                  if (_durable) _message = null;
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
      ),
    );
  }
}
