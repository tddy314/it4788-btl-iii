import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/errors/app_failure.dart';
import '../../core/network/connection_monitor.dart';
import '../../core/storage/draft_store.dart';
import '../../core/storage/session_store.dart';
import '../../core/validation/validators.dart';
import 'post_models.dart';
import 'post_media_service.dart';
import 'posts_repository.dart';

class ComposerController extends ChangeNotifier {
  ComposerController({
    required this.repository,
    required this.mediaService,
    required this.drafts,
    required this.session,
    this.original,
  }) : userId = session.tokens!.userId {
    content = original?.content ?? '';
    retained = [...?original?.media];
    session.addListener(_sessionChanged);
  }
  final PostsRepository repository;
  final PostMediaService mediaService;
  final DraftStore drafts;
  final SessionStore session;
  final Post? original;
  final String userId;
  String get draftName => 'post/${original?.id ?? 'new'}';
  String content = '';
  List<PostMedia> retained = [];
  List<DraftAttachment> attachments = [];
  bool ready = false, busy = false, uncertain = false;
  bool reviewed = false, draftDurable = true;
  int? confirmedId;
  DateTime? attemptedAt;
  String? message;
  double? progress;
  bool _disposed = false, _invalid = false, _completed = false;
  Future<void> _writes = Future.value();
  final CancelToken cancel = CancelToken();
  bool get active =>
      !_disposed && !_invalid && session.tokens?.userId == userId;
  void _sessionChanged() {
    if (session.tokens?.userId != userId) {
      _invalid = true;
      cancel.cancel();
    }
  }

  void emit() {
    if (active) notifyListeners();
  }

  Future<void> restore() async {
    try {
      final data = await drafts.read(userId: userId, name: draftName);
      if (!active) return;
      if (data != null) {
        content = data['content'] as String;
        retained = (data['retained'] as List).map(PostMedia.fromJson).toList();
        attachments = (data['attachments'] as List)
            .map(DraftAttachment.fromJson)
            .toList();
        uncertain = data['uncertain'] == true;
        confirmedId = data['confirmed_id'] as int?;
        if (confirmedId != null) uncertain = true;
        attemptedAt = DateTime.tryParse(textValue(data['attempted_at']));
        message = 'Đã khôi phục bản nháp trên máy.';
      }
    } catch (_) {
      message = 'Không đọc được bản nháp đã lưu.';
    }
    ready = true;
    emit();
  }

  Future<void> save() {
    if (!active || !ready || _completed) return Future.value();
    final snapshot = {
      'content': content,
      'retained': retained.map((e) => e.toJson()).toList(),
      'attachments': attachments.map((e) => e.toJson()).toList(),
      'uncertain': uncertain,
      'attempted_at': attemptedAt?.toIso8601String(),
      'confirmed_id': confirmedId,
    };
    _writes = _writes
        .then((_) async {
          await drafts.save(userId: userId, name: draftName, data: snapshot);
          draftDurable = true;
        })
        .catchError((Object _) {
          draftDurable = false;
          message = 'Không lưu được bản nháp. Hãy giữ màn hình này mở.';
          emit();
        });
    return _writes;
  }

  void changeContent(String value) {
    content = value;
    if (draftDurable) message = null;
    unawaited(save());
  }

  Future<void> addFiles(List<XFile> files) async {
    if (busy || uncertain || !active) return;
    busy = true;
    message = null;
    emit();
    try {
      for (final file in files) {
        if (!active) break;
        if (retained.length + attachments.length >= 4) {
          throw const AppFailure(
            FailureKind.rejected,
            'Chỉ chọn tối đa 4 ảnh.',
          );
        }
        final picked = await mediaService.inspect(file, userId);
        if (!active) {
          await mediaService.removeLocal(picked, userId);
          break;
        }
        final types = [
          ...retained.map((m) => m.type),
          ...attachments.map((m) => m.type),
          picked.type,
        ];
        if (types.contains('VIDEO') && types.length > 1) {
          await mediaService.removeLocal(picked, userId);
          throw const AppFailure(
            FailureKind.rejected,
            'Chọn 4 ảnh hoặc 1 video, không trộn ảnh/video.',
          );
        }
        attachments.add(picked);
        await save();
      }
    } on AppFailure catch (e) {
      message = e.message;
    } catch (_) {
      message =
          'Không đọc được tệp. Hãy kiểm tra quyền truy cập hoặc chọn tệp khác.';
    } finally {
      busy = false;
      emit();
    }
  }

  Future<void> removeAttachment(DraftAttachment file) async {
    if (busy || uncertain) return;
    attachments.remove(file);
    await save();
    try {
      await mediaService.removeLocal(file, userId);
    } catch (_) {
      /* draft already updated */
    }
    emit();
  }

  void removeRetained(PostMedia file) {
    if (busy || uncertain) return;
    retained.remove(file);
    unawaited(save());
    emit();
  }

  Future<int?> submit() async {
    if (!active || busy || !ready || uncertain) return null;
    final invalid = Validators.maxWords(content, 500);
    if (invalid != null ||
        (content.trim().isEmpty && retained.isEmpty && attachments.isEmpty)) {
      message = invalid ?? 'Nhập nội dung hoặc chọn ảnh/video cho bài viết.';
      emit();
      return null;
    }
    if (attachments.any((e) => e.uncertain)) {
      message = 'Có tệp tải lên chưa rõ kết quả. Gỡ tệp đó và chọn lại nếu muốn tải lại.';
      emit();
      return null;
    }
    busy = true;
    message = null;
    emit();
    try {
      // Validation precedes connectivity. No write is sent while known offline.
      await repository.api.connection.check();
      if (repository.api.connection.status == ConnectionStatus.offline) {
        throw AppFailure.offline;
      }
      for (final file in attachments) {
        if (file.uploaded != null) continue;
        await mediaService.inspect(XFile(file.path), userId, copy: false);
        if (!active) return null;
        file.uncertain = true;
        await save();
        if (!active) return null;
        if (!draftDurable) {
          file.uncertain = false;
          throw const AppFailure(
            FailureKind.storage,
            'Không lưu được trạng thái gửi. Chưa tải tệp lên.',
          );
        }
        try {
          file.uploaded = await mediaService.upload(file, cancel, (
            sent,
            total,
          ) {
            progress = total > 0 ? sent / total : null;
            emit();
          });
          file.uncertain = false;
          await save();
        } on AppFailure catch (e) {
          file.uncertain = uncertainWrite(e);
          await save();
          rethrow;
        }
      }
      if (!active) return null;
      final media = [...retained, ...attachments.map((e) => e.uploaded!)];
      PostsRepository.validatePost(content, media);
      attemptedAt = DateTime.now().toUtc();
      uncertain = true;
      await save();
      if (!active) return null;
      if (!draftDurable) {
        uncertain = false;
        throw const AppFailure(
          FailureKind.storage,
          'Không lưu được trạng thái gửi. Chưa gửi bài viết.',
        );
      }
      int id;
      try {
        if (original == null) {
          id = (await repository.create(content, media, cancel: cancel)).id;
        } else {
          id = original!.id;
          await repository.update(id, content, media, cancel: cancel);
        }
      } on AppFailure catch (e) {
        uncertain = uncertainWrite(e);
        await save();
        rethrow;
      }
      if (!active) return null;
      confirmedId = id;
      await save();
      await complete();
      return id;
    } on AppFailure catch (e) {
      message = uncertain
          ? 'Chưa xác định bài đã được lưu hay chưa. Kiểm tra kết quả trước khi gửi lại.'
          : e.message;
    } catch (_) {
      message = 'Không thể hoàn tất. Bản nháp vẫn được giữ; kiểm tra kết quả trước khi gửi lại.';
    } finally {
      busy = false;
      progress = null;
      emit();
    }
    return null;
  }

  Future<void> complete() async {
    _completed = true;
    await _writes;
    try {
      await drafts.remove(userId: userId, name: draftName);
      for (final file in attachments) {
        await mediaService.removeLocal(file, userId);
      }
    } catch (_) {
      message =
          'Bài đã lưu trên server nhưng không dọn được bản nháp trên máy.';
    }
  }

  Future<Post?> reconcile() async {
    if (busy || !active) return null;
    busy = true;
    message = null;
    reviewed = false;
    emit();
    try {
      final candidates = confirmedId != null
          ? [await repository.get(confirmedId!, cancel: cancel)]
          : original != null
          ? [await repository.get(original!.id, cancel: cancel)]
          : (await repository.mine(cancel: cancel)).items;
      if (!active) return null;
      reviewed = true;
      final urls = [
        ...retained.map((e) => e.url),
        ...attachments.map((e) => e.uploaded?.url),
      ];
      for (final post in candidates) {
        // A matching newly-created post is only a candidate; identical content
        // alone cannot prove which POST created it. Let the user inspect it.
        if ((original != null || confirmedId == post.id) &&
            post.content == content.trim() &&
            listEquals(post.media.map((e) => e.url).toList(), urls)) {
          await complete();
          return post;
        }
      }
      message = 'Kiểm tra “Bài của tôi”. Nếu bài đã xuất hiện, chọn bài đó để đóng bản nháp.';
    } on AppFailure catch (e) {
      message = e.message;
    } catch (_) {
      message = 'Chưa kiểm tra được kết quả. Hãy thử lại khi có mạng.';
    } finally {
      busy = false;
      emit();
    }
    return null;
  }

  void allowRetryAfterReview() {
    if (!reviewed || confirmedId != null) return;
    uncertain = false;
    unawaited(save());
    emit();
  }

  bool matchesReviewedPost(Post post) {
    if (!active ||
        !reviewed ||
        !uncertain ||
        original != null ||
        post.author.id?.toString() != userId ||
        post.content != content.trim()) {
      return false;
    }
    final urls = [
      ...retained.map((m) => m.url),
      ...attachments.map((m) => m.uploaded?.url),
    ];
    return listEquals(post.media.map((m) => m.url).toList(), urls);
  }

  @override
  void dispose() {
    _disposed = true;
    cancel.cancel();
    session.removeListener(_sessionChanged);
    super.dispose();
  }
}
