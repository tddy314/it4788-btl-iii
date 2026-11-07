import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/errors/app_failure.dart';
import '../../core/network/connection_monitor.dart';
import 'post_models.dart';
import 'posts_repository.dart';

class ReportPostScreen extends StatefulWidget {
  const ReportPostScreen({super.key, required this.postId});
  final int postId;
  @override
  State<ReportPostScreen> createState() => _ReportPostScreenState();
}

class _ReportPostScreenState extends State<ReportPostScreen> {
  final _text = TextEditingController();
  final _cancel = CancelToken();
  String _reason = 'SPAM';
  String? _message;
  bool _busy = false, _ready = false, _uncertain = false;
  bool _durable = true;
  Future<void> _writes = Future.value();
  String? _user;
  String get _key => 'report/post/${widget.postId}';
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_user != null) return;
    _user = AppScope.of(context).session.tokens!.userId;
    unawaited(_restore());
  }

  Future<void> _restore() async {
    try {
      final draft = await AppScope.of(context).drafts
          .read(userId: _user!, name: _key);
      if (!mounted) return;
      _text.text = textValue(draft?['description']);
      _reason = draft?['reason'] as String? ?? 'SPAM';
      _uncertain = draft?['uncertain'] == true;
    } catch (_) {
      _message = 'Không đọc được bản nháp báo cáo.';
    }
    if (mounted) setState(() => _ready = true);
  }

  Future<void> _save() {
    final drafts = AppScope.of(context).drafts;
    final data = {
      'description': _text.text,
      'reason': _reason,
      'uncertain': _uncertain,
    };
    _writes = _writes
        .then((_) async {
          await drafts.save(userId: _user!, name: _key, data: data);
          _durable = true;
        })
        .catchError((Object _) {
          _durable = false;
          if (mounted) {
            setState(() => _message = 'Không lưu được bản nháp trên máy.');
          }
        });
    return _writes;
  }

  Future<void> _send() async {
    if (_busy || _uncertain) return;
    if (_text.text.runes.length > 500) {
      setState(() => _message = 'Mô tả không vượt quá 500 ký tự.');
      return;
    }
    final d = AppScope.of(context);
    setState(() {
      _busy = true;
    });
    try {
      await d.connection.check();
      if (d.connection.status == ConnectionStatus.offline) {
        if (mounted) setState(() => _message = AppFailure.offline.message);
        return;
      }
      if (!mounted || d.session.tokens?.userId != _user) return;
      _uncertain = true;
      await _save();
      if (!mounted || d.session.tokens?.userId != _user) return;
      if (!_durable) {
        _uncertain = false;
        throw const AppFailure(
          FailureKind.storage,
          'Không lưu được trạng thái gửi. Chưa gửi báo cáo.',
        );
      }
      await PostsRepository(d.api)
          .report(widget.postId, _reason, _text.text, cancel: _cancel);
      try {
        await d.drafts.remove(userId: _user!, name: _key);
      } catch (_) {
        /* Keep uncertainty marker; never encourage duplicate reports. */
      }
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Đã gửi báo cáo.')));
        Navigator.pop(context);
      }
    } on AppFailure catch (e) {
      _uncertain = uncertainWrite(e);
      if (mounted) await _save();
      _message = e.message;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _cancel.cancel();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Báo cáo bài viết')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButtonFormField<String>(
          initialValue: _reason,
          decoration: const InputDecoration(labelText: 'Lý do'),
          items: const [
            DropdownMenuItem(value: 'SPAM', child: Text('Spam')),
            DropdownMenuItem(value: 'HARASSMENT', child: Text('Quấy rối')),
            DropdownMenuItem(
              value: 'HATE_STATEMENT',
              child: Text('Phát ngôn thù ghét'),
            ),
            DropdownMenuItem(value: 'OTHER', child: Text('Khác')),
          ],
          onChanged: !_ready || _busy || _uncertain
              ? null
              : (v) {
                  setState(() => _reason = v!);
                  unawaited(_save());
                },
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _text,
          enabled: _ready && !_busy && !_uncertain,
          minLines: 4,
          maxLines: 8,
          onChanged: (_) => unawaited(_save()),
          decoration: const InputDecoration(
            labelText: 'Mô tả (tối đa 500 ký tự)',
          ),
        ),
        if (_message != null) Text(_message!),
        if (_uncertain && !_busy)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'Chưa rõ server đã nhận báo cáo hay chưa. Bản nháp được giữ; không gửi lặp vì API hiện không hỗ trợ kiểm tra báo cáo đã gửi.',
            ),
          ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: !_ready || _busy || _uncertain ? null : _send,
          child: Text(_busy ? 'Đang gửi…' : 'Gửi báo cáo'),
        ),
      ],
    ),
  );
}
