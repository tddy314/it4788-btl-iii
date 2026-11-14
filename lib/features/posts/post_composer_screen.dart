import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/app_scope.dart';
import '../../core/validation/validators.dart';
import '../../core/widgets/app_network_image.dart';
import '../../core/widgets/app_states.dart';
import 'composer_controller.dart';
import 'post_media_service.dart';
import 'post_models.dart';
import 'posts_repository.dart';
import 'posts_list_screen.dart';
import 'picker_recovery.dart';

class PostComposerScreen extends StatefulWidget {
  const PostComposerScreen({super.key, this.original});
  final Post? original;
  @override
  State<PostComposerScreen> createState() => _PostComposerScreenState();
}

class _PostComposerScreenState extends State<PostComposerScreen>
    with WidgetsBindingObserver {
  ComposerController? _controller;
  final _text = TextEditingController();
  final _picker = ImagePicker();
  bool _picking = false, _canRetry = false;
  PickerRecovery? _recovery;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final d = AppScope.of(context);
    _recovery = PickerRecovery(d.drafts);
    final controller = ComposerController(
      repository: PostsRepository(d.api),
      mediaService: PostMediaService(d.api),
      drafts: d.drafts,
      session: d.session,
      original: widget.original,
    );
    _controller = controller;
    controller.addListener(_changed);
    unawaited(_restore());
  }

  Future<void> _restore() async {
    await _controller!.restore();
    if (!mounted) return;
    _text.text = _controller!.content;
    try {
      final pending = await _recovery!.pending(_controller!.userId);
      if (!mounted || !_controller!.active || pending == null) return;
      final original = pending['original'] == null
          ? null
          : Post.fromJson(pending['original']);
      if (original?.id != widget.original?.id) return;
      final lost = await _picker.retrieveLostData();
      if (!mounted) return;
      if (lost.files != null) await _controller!.addFiles(lost.files!);
      await _recovery!.finish(_controller!.userId, pending['nonce'] as String);
      if (lost.exception != null) {
        _notice(
          'Không khôi phục được tệp vừa chọn. Nội dung bản nháp vẫn còn.',
        );
      }
    } catch (_) {
      /* Text draft can still be used when picker is unavailable. */
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _notice(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_controller?.save());
  }

  Future<void> _pick(String kind) async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      await _controller!.save();
      if (!_controller!.draftDurable || !mounted) return;
      final nonce = await _recovery!.begin(
        _controller!.userId,
        widget.original,
      );
      final List<XFile> files;
      if (kind == 'images') {
        files = await _picker.pickMultiImage();
      } else {
        final file = kind == 'camera'
            ? await _picker.pickImage(source: ImageSource.camera)
            : await _picker.pickVideo(
                source: kind == 'record'
                    ? ImageSource.camera
                    : ImageSource.gallery,
                maxDuration: const Duration(seconds: 10),
              );
        files = file == null ? [] : [file];
      }
      if (mounted) await _controller!.addFiles(files);
      await _recovery!.finish(_controller!.userId, nonce);
    } on PlatformException {
      _notice(
        'Không mở được ảnh/camera. Hãy kiểm tra quyền của ứng dụng trong Cài đặt điện thoại.',
      );
    } catch (_) {
      _notice(
        'Không chọn được tệp. Bạn có thể thử lại; bản nháp vẫn được giữ.',
      );
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final id = await _controller!.submit();
    if (mounted && id != null) Navigator.of(context).pop(id);
  }

  Future<void> _check() async {
    final post = await _controller!.reconcile();
    if (!mounted) return;
    if (post != null) {
      Navigator.of(context).pop(post.id);
      return;
    }
    if (!_controller!.reviewed) return;
    // A successful explicit review is still required before unlocking a repeat.
    final controller = _controller!;
    final chosen = await Navigator.of(context).push<Post>(
      MaterialPageRoute(
        builder: (_) =>
            PostsListScreen(canConfirm: controller.matchesReviewedPost),
      ),
    );
    if (!mounted) return;
    if (chosen != null && controller.matchesReviewedPost(chosen)) {
      await controller.complete();
      if (mounted) Navigator.of(context).pop(chosen.id);
      return;
    }
    if (mounted) setState(() => _canRetry = true);
  }

  Future<void> _retryConfirmed() async {
    final answer = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gửi lại bài viết?'),
        content: const Text(
          'Chỉ tiếp tục nếu bạn đã kiểm tra bài của mình và xác nhận thao tác trước chưa được lưu. Gửi lại có thể tạo bài trùng nếu server xử lý chậm.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Đã kiểm tra, cho gửi lại'),
          ),
        ],
      ),
    );
    if (answer == true && mounted) _controller!.allowRetryAfterReview();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.removeListener(_changed);
    _controller?.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c == null || !c.ready) {
      return const Scaffold(
        body: AppLoadingState(message: 'Đang mở bản nháp…'),
      );
    }
    final locked = c.busy || c.uncertain || _picking;
    return PopScope(
      canPop: !c.busy && !_picking,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.original == null ? 'Tạo bài viết' : 'Sửa bài viết',
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.public),
                title: Text('Công khai'),
                subtitle: Text('Tối đa 500 từ · 4 ảnh hoặc 1 video'),
              ),
              TextField(
                controller: _text,
                enabled: !locked,
                minLines: 5,
                maxLines: 14,
                decoration: const InputDecoration(
                  hintText: 'Bạn muốn chia sẻ điều gì?',
                  labelText: 'Nội dung bài viết',
                ),
                onChanged: (value) {
                  c.changeContent(value);
                  setState(() {});
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('${Validators.wordCount(_text.text)}/500 từ'),
              ),
              for (final media in c.retained)
                ListTile(
                  leading: media.isVideo
                      ? const Icon(Icons.videocam)
                      : AppNetworkImage(url: media.url, width: 48, height: 48),
                  title: Text(media.isVideo ? 'Video hiện có' : 'Ảnh hiện có'),
                  trailing: IconButton(
                    tooltip: 'Gỡ tệp',
                    onPressed: locked ? null : () => c.removeRetained(media),
                    icon: const Icon(Icons.close),
                  ),
                ),
              for (final media in c.attachments)
                ListTile(
                  leading: media.type == 'VIDEO'
                      ? const Icon(Icons.videocam)
                      : Image.file(
                          File(media.path),
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              const Icon(Icons.broken_image_outlined),
                        ),
                  title: Text(
                    media.type == 'VIDEO'
                        ? 'Video ${media.duration ?? 0} giây'
                        : 'Ảnh đã chọn',
                  ),
                  subtitle: Text(
                    media.uncertain
                        ? 'Chưa rõ kết quả tải lên'
                        : media.uploaded != null
                        ? 'Đã tải lên'
                        : '${(media.size / 1024).ceil()} KB',
                  ),
                  trailing: IconButton(
                    tooltip: 'Gỡ tệp',
                    onPressed: locked ? null : () => c.removeAttachment(media),
                    icon: const Icon(Icons.close),
                  ),
                ),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: locked ? null : () => _pick('images'),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Chọn ảnh'),
                  ),
                  OutlinedButton.icon(
                    onPressed: locked ? null : () => _pick('camera'),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Chụp ảnh'),
                  ),
                  OutlinedButton.icon(
                    onPressed: locked ? null : () => _pick('video'),
                    icon: const Icon(Icons.video_library_outlined),
                    label: const Text('Chọn video'),
                  ),
                  OutlinedButton.icon(
                    onPressed: locked ? null : () => _pick('record'),
                    icon: const Icon(Icons.videocam_outlined),
                    label: const Text('Quay video'),
                  ),
                ],
              ),
              const Text(
                'Ảnh tĩnh tối đa 4 MB/tệp. Video tối đa 10 MB, dài 1–10 giây.',
              ),
              if (c.message != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(c.message!),
                ),
              if (c.busy || _picking) ...[
                LinearProgressIndicator(value: c.progress),
                const SizedBox(height: 8),
                const Text('Đang xử lý, vui lòng chờ…'),
              ],
              const SizedBox(height: 16),
              if (c.uncertain) ...[
                FilledButton(
                  onPressed: c.busy ? null : _check,
                  child: const Text('Kiểm tra kết quả đã gửi'),
                ),
                if (_canRetry)
                  TextButton(
                    onPressed: c.busy ? null : _retryConfirmed,
                    child: const Text('Tôi đã kiểm tra, cho phép gửi lại'),
                  ),
              ] else
                FilledButton.icon(
                  onPressed: locked ? null : _submit,
                  icon: const Icon(Icons.send_outlined),
                  label: Text(
                    widget.original == null ? 'Đăng bài' : 'Lưu thay đổi',
                  ),
                ),
              const SizedBox(height: 16),
              const Text(
                'Nội dung được lưu thành bản nháp trên máy theo tài khoản.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
