import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/app_scope.dart';
import '../../core/errors/app_failure.dart';
import '../../core/media/media_upload_service.dart';
import '../../core/storage/draft_store.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_network_image.dart';
import '../../core/widgets/app_states.dart';
import '../relationships/social_repository.dart';
import '../relationships/social_state.dart';
import '../relationships/social_widgets.dart';
import 'profile_models.dart';
import 'profile_repository.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({
    super.key,
    required this.profile,
    required this.changes,
  });
  final UserProfile profile;
  final SocialChanges changes;
  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen>
    with WidgetsBindingObserver {
  static const _draftName = 'profile.edit.v1';
  final _name = TextEditingController();
  final _bio = TextEditingController();
  final _birth = TextEditingController();
  final _timezone = TextEditingController();
  final _picker = ImagePicker();
  final _scroll = ScrollController();
  SocialRepository? _social;
  late DraftStore _drafts;
  late Map<String, String> _original;
  String _gender = '';
  String _avatar = '';
  String _cover = '';
  bool _restoring = true;
  bool _busy = false;
  bool _picking = false;
  bool _uploading = false;
  bool _saved = false;
  bool _leaving = false;
  String? _message;
  double? _progress;
  XFile? _pendingImage;
  Timer? _timer;
  Future<void> _writes = Future.value();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _original = {
      for (final key in ProfileInput.editable)
        key: widget.profile.text(key) ?? '',
    };
    _assign(_original);
    for (final field in [_name, _bio, _birth, _timezone]) {
      field.addListener(_edited);
    }
  }

  void _assign(Map<String, String> fields) {
    _name.text = fields['full_name'] ?? '';
    _bio.text = fields['bio'] ?? '';
    _birth.text = fields['date_of_birth'] ?? '';
    _timezone.text = fields['timezone'] ?? '';
    _gender = ['MALE', 'FEMALE'].contains(fields['gender'])
        ? fields['gender']!
        : '';
    _avatar = fields['avatar_url'] ?? '';
    _cover = fields['cover_url'] ?? '';
  }

  Map<String, String> _fields() => {
    'full_name': _name.text.trim(),
    'bio': _bio.text,
    'date_of_birth': _birth.text,
    'timezone': _timezone.text.trim(),
    'gender': _gender,
    'avatar_url': _avatar,
    'cover_url': _cover,
  };
  Set<String> _dirty(Map<String, String> fields) =>
      fields.keys.where((key) => fields[key] != _original[key]).toSet();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_social != null) return;
    final dependencies = AppScope.of(context);
    _drafts = dependencies.drafts;
    _social = SocialRepository(
      api: dependencies.api,
      lease: widget.changes.lease(),
    );
    unawaited(_restore());
  }

  Future<void> _restore() async {
    try {
      final draft = await _drafts.read(
        userId: _social!.lease.userId,
        name: _draftName,
      );
      if (!mounted || !_social!.lease.active) return;
      final fields = draft?['fields'];
      final dirty = draft?['dirty'];
      if (fields is Map && dirty is List) {
        final restored = Map<String, String>.from(_original);
        for (final key in dirty) {
          if (key is String &&
              ProfileInput.editable.contains(key) &&
              fields[key] is String) {
            restored[key] = fields[key] as String;
          }
        }
        _assign(restored);
        _message =
            'Đã khôi phục bản nháp trên máy. Bạn có thể kiểm tra rồi lưu.';
      }
    } catch (_) {
      if (mounted) _message = 'Không đọc được bản nháp. Các thay đổi mới vẫn có thể nhập tại đây.';
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  void _edited() {
    if (_restoring || _saved || _leaving) return;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 500), () {
      unawaited(
        _saveDraft().catchError((Object _) {
          if (mounted && !_leaving) {
            setState(
              () => _message = 'Chưa lưu được bản nháp trên máy. Hãy giữ màn hình này để tránh mất nội dung.',
            );
          }
        }),
      );
    });
  }

  Future<void> _saveDraft() {
    if (_saved || _social == null || !_social!.lease.active) {
      return Future.value();
    }
    final fields = _fields();
    final snapshot = {'fields': fields, 'dirty': _dirty(fields).toList()};
    final next = _writes.then((_) async {
      _social!.lease.check();
      await _drafts.save(
        userId: _social!.lease.userId,
        name: _draftName,
        data: snapshot,
      );
    });
    _writes = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<void> _choose(MediaPurpose purpose) async {
    if (_picking || _uploading || _busy || widget.changes.busy) return;
    if (_pendingImage != null) {
      final yes = await confirmSocialAction(
        context,
        'Chọn ảnh khác',
        'Ảnh trước chưa được xác nhận tải lên. Ảnh đó chưa được gắn vào hồ sơ. '
            'Bạn có muốn chọn lại?',
      );
      if (!yes || !mounted) return;
    }
    setState(() {
      _picking = true;
      _message = null;
    });
    try {
      await _saveDraft();
      final image = await _picker.pickImage(source: ImageSource.gallery);
      if (image == null || !mounted || !_social!.lease.active) return;
      final length = await image.length();
      if (length == 0 || length > 4 * 1024 * 1024) {
        throw const AppFailure(
          FailureKind.rejected,
          'Ảnh phải có dung lượng từ 1 byte đến 4 MB.',
        );
      }
      final bytes = await image.readAsBytes();
      if (bytes.isEmpty || bytes.length > 4 * 1024 * 1024) {
        throw const AppFailure(
          FailureKind.rejected,
          'Ảnh phải có dung lượng từ 1 byte đến 4 MB.',
        );
      }
      // Decode the actual file rather than trusting its suffix or MIME hint.
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 512,
        targetHeight: 512,
      );
      try {
        final frame = await codec.getNextFrame();
        frame.image.dispose();
      } finally {
        codec.dispose();
      }
      if (!mounted || !_social!.lease.active) return;
      setState(() {
        _pendingImage = image;
        _uploading = true;
        _progress = null;
      });
      final uploaded = await AppScope.of(context).mediaUpload.upload(
        filePath: image.path,
        purpose: purpose,
        maxBytes: 4 * 1024 * 1024,
        cancelToken: _social!.cancel,
        onProgress: (sent, total) {
          if (mounted && _social!.lease.active) {
            setState(() => _progress = total > 0 ? sent / total : null);
          }
        },
      );
      _social!.lease.check();
      if (!mounted) return;
      if (uploaded.mediaType != 'IMAGE' ||
          !uploaded.contentType.startsWith('image/')) {
        throw const AppFailure(
          FailureKind.invalidData,
          'Máy chủ không xác nhận đây là tệp ảnh.',
        );
      }
      setState(() {
        if (purpose == MediaPurpose.avatar) {
          _avatar = uploaded.url;
        } else {
          _cover = uploaded.url;
        }
        _pendingImage = null;
        _message = 'Ảnh đã tải lên. Nhấn Lưu hồ sơ để áp dụng.';
      });
      try {
        await _saveDraft();
      } catch (_) {
        if (mounted) {
          setState(
            () => _message =
                'Ảnh đã tải lên nhưng chưa lưu được bản nháp trên máy. '
                'Hãy giữ màn hình này và lưu hồ sơ khi có thể.',
          );
        }
      }
    } on PlatformException catch (_) {
      if (mounted) {
        setState(
          () => _message = 'Không thể mở thư viện ảnh. Hãy kiểm tra quyền truy cập ảnh trong Cài đặt của thiết bị.',
        );
      }
    } on AppFailure catch (error) {
      if (mounted) setState(() => _message = socialWriteError(error));
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'Không thể đọc hoặc tải ảnh. Nội dung đang nhập vẫn được giữ; hãy kiểm tra ảnh và kết nối.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _picking = false;
          _uploading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    if (_busy || _picking || _uploading || widget.changes.busy) return;
    final fields = _fields();
    final input = ProfileInput(fields, changedKeys: _dirty(fields));
    final error = input.validate();
    if (error != null) {
      _showError(error);
      return;
    }
    if (_pendingImage != null) {
      _showError(
        'Ảnh đang chọn chưa tải lên thành công. '
        'Hãy chọn lại hoặc bỏ lựa chọn ảnh trước khi lưu hồ sơ.',
      );
      return;
    }
    FocusScope.of(context).unfocus();
    _timer?.cancel();
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await _saveDraft();
      final done = await widget.changes.mutate(() async {
        await ProfileRepository(_social!).update(input);
      });
      if (!done || !mounted || !_social!.lease.active) return;
      _saved = true;
      await _writes;
      try {
        await _drafts.remove(userId: _social!.lease.userId, name: _draftName);
      } catch (_) {
        /* A confirmed server update remains successful. */
      }
      if (mounted && _social!.lease.active) Navigator.pop(context, true);
    } catch (error) {
      if (mounted && _social!.lease.active) {
        _showError(socialWriteError(error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String message) {
    setState(() => _message = message);
    if (_scroll.hasClients) {
      unawaited(
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        ),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((state == AppLifecycleState.inactive ||
            state == AppLifecycleState.paused) &&
        !_restoring &&
        !_saved) {
      _timer?.cancel();
      unawaited(_saveDraft().catchError((Object _) {}));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _leaving = true;
    _timer?.cancel();
    if (!_restoring && !_saved) {
      unawaited(_saveDraft().catchError((Object _) {}));
    }
    _social?.dispose();
    _scroll.dispose();
    for (final field in [_name, _bio, _birth, _timezone]) {
      field.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = !_busy && !_picking && !_uploading && !widget.changes.busy;
    return Scaffold(
      appBar: AppBar(title: const Text('Chỉnh sửa hồ sơ')),
      body: SafeArea(
        child: _restoring
            ? const AppLoadingState()
            : ListView(
                controller: _scroll,
                padding: const EdgeInsets.all(16),
                children: [
                  if (_message != null) SocialNotice(message: _message!),
                  TextField(
                    controller: _name,
                    enabled: enabled,
                    decoration: const InputDecoration(
                      labelText: 'Họ và tên',
                      helperText: 'Tối đa 100 ký tự',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _bio,
                    enabled: enabled,
                    minLines: 3,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: 'Tiểu sử',
                      helperText: 'Tối đa 500 ký tự',
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _gender,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Giới tính'),
                    items: const [
                      DropdownMenuItem(value: '', child: Text('Chưa chọn')),
                      DropdownMenuItem(value: 'MALE', child: Text('Nam')),
                      DropdownMenuItem(value: 'FEMALE', child: Text('Nữ')),
                    ],
                    onChanged: enabled
                        ? (value) {
                            setState(() => _gender = value ?? '');
                            _edited();
                          }
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _birth,
                    enabled: enabled,
                    keyboardType: TextInputType.datetime,
                    decoration: const InputDecoration(
                      labelText: 'Ngày sinh',
                      hintText: 'yyyy-MM-dd',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _timezone,
                    enabled: enabled,
                    decoration: const InputDecoration(
                      labelText: 'Múi giờ',
                      hintText: 'Asia/Ho_Chi_Minh',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      AppAvatar(
                        imageUrl: _avatar.isEmpty ? null : _avatar,
                        size: 64,
                      ),
                      OutlinedButton.icon(
                        onPressed: enabled
                            ? () => _choose(MediaPurpose.avatar)
                            : null,
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Chọn ảnh đại diện'),
                      ),
                      OutlinedButton.icon(
                        onPressed: enabled
                            ? () => _choose(MediaPurpose.cover)
                            : null,
                        icon: const Icon(Icons.panorama_outlined),
                        label: const Text('Chọn ảnh bìa'),
                      ),
                    ],
                  ),
                  if (_cover.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: AppNetworkImage(
                        url: _cover,
                        height: 144,
                        width: double.infinity,
                      ),
                    ),
                  if (_pendingImage != null) ...[
                    const SizedBox(height: 12),
                    Image.file(
                      File(_pendingImage!.path),
                      height: 120,
                      cacheWidth: 512,
                      cacheHeight: 512,
                      errorBuilder: (_, _, _) =>
                          const Text('Không đọc được ảnh đã chọn.'),
                    ),
                    TextButton(
                      onPressed: enabled
                          ? () => setState(() => _pendingImage = null)
                          : null,
                      child: const Text('Bỏ lựa chọn ảnh chưa tải lên'),
                    ),
                  ],
                  if (_uploading) ...[
                    const SizedBox(height: 12),
                    LinearProgressIndicator(value: _progress),
                    const Text('Đang tải ảnh lên…'),
                  ],
                  const SizedBox(height: 24),
                  AppButton(
                    label: 'Lưu hồ sơ',
                    isLoading: _busy,
                    onPressed: enabled ? _save : null,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Nội dung chỉnh sửa được lưu thành bản nháp riêng trên máy. '
                    'Ảnh chỉ được giữ qua lần mở lại sau khi tải lên thành công.',
                  ),
                ],
              ),
      ),
    );
  }
}
