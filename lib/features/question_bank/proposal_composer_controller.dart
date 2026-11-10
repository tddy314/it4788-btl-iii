import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/errors/app_failure.dart';
import '../../core/storage/cached_resource_controller.dart';
import '../../core/storage/draft_store.dart';
import '../../core/storage/json_cache.dart';
import 'proposal_draft.dart';
import 'question_bank_repository.dart';
import 'question_image_service.dart';
import 'question_models.dart';
import 'question_validation.dart';

sealed class SubmitOutcome {
  const SubmitOutcome(this.sessionId);
  final int sessionId;
}

class ProposalCreated extends SubmitOutcome {
  const ProposalCreated(super.sessionId);
}

class ProposalUpdated extends SubmitOutcome {
  const ProposalUpdated(super.sessionId);
}

/// Lần gửi trước bị mất phản hồi nhưng server đã tạo phiên.
class ProposalFoundExisting extends SubmitOutcome {
  const ProposalFoundExisting(super.sessionId);
}

/// Quản lý bản nháp và luồng gửi đề xuất mới/sửa phiên PENDING.
///
/// Thứ tự: validate → lưu nháp → (kiểm tra lần gửi chưa xác nhận) → upload ảnh
/// còn thiếu → đánh dấu "đang chờ xác nhận" → gửi. Chỉ xóa nháp khi server xác
/// nhận. Timeout/lỗi không rõ không tự gửi lại.
class ProposalComposerController extends ChangeNotifier {
  ProposalComposerController({
    required this.repository,
    required this.drafts,
    required this.cache,
    required this.images,
    required this.userId,
    this.editing,
  }) {
    classes = CachedResourceController<List<CourseClassOption>>(
      cache: cache,
      userId: userId,
      resource: 'qb.enrolled-classes',
      fetch: () => repository.enrolledClasses(),
      encode: (value) => [for (final c in value) c.toJson()],
      decode: (value) => [
        for (final c in qbList(value)) CourseClassOption.fromJson(c),
      ],
    )..addListener(_syncSelectedClass);
  }
  final QuestionBankRepository repository;
  final DraftStore drafts;
  final JsonCache cache;
  final QuestionImageService images;
  final String userId;

  /// Chi tiết phiên đang sửa (null khi tạo mới).
  final SubmissionDetail? editing;

  late ProposalDraft draft;
  late final CachedResourceController<List<CourseClassOption>> classes;
  bool ready = false;
  bool restoredFromDraft = false;
  bool busy = false;
  bool locked = false;
  bool showErrors = false;
  bool pickingImage = false;
  Map<String, String> errors = const {};
  String? progress;
  String? message;
  bool messageIsError = true;
  String? draftStatus;
  CancelToken? _cancel;
  Timer? _saveTimer;
  bool _dirty = false;
  bool _disposed = false;

  bool get isEdit => editing != null;
  bool get hasPendingVerification => draft.pending != null;

  Future<void> init() async {
    ProposalDraft? restored;
    try {
      final saved = await drafts.read(
        userId: userId,
        name: ProposalDraft.draftNameFor(editing?.sessionId),
      );
      if (saved != null) restored = ProposalDraft.fromJson(saved);
    } catch (_) {
      // Nháp hỏng hoặc storage lỗi: bắt đầu lại, không xóa dữ liệu khác.
    }
    if (_disposed) return;
    restoredFromDraft = restored != null;
    draft =
        restored ??
        (editing != null
            ? ProposalDraft.fromSubmission(editing!)
            : ProposalDraft());
    if (restoredFromDraft) {
      draftStatus = 'Đã khôi phục bản nháp chưa gửi.';
    }
    if (draft.pending != null) {
      messageIsError = true;
      message =
          'Lần gửi trước chưa được xác nhận. Khi bấm gửi, ứng dụng sẽ kiểm tra '
          'kết quả trên máy chủ trước để tránh tạo trùng.';
    }
    ready = true;
    _notify();
    if (!isEdit) unawaited(classes.load());
  }

  void _syncSelectedClass() {
    final list = classes.data;
    final selected = draft.courseClass;
    if (list == null || selected == null || !ready) return;
    for (final option in list) {
      if (option.courseClassId == selected.courseClassId) {
        if (!identical(option, selected)) {
          draft.courseClass = option;
          _revalidate();
          _notify();
        }
        return;
      }
    }
  }

  /// Gọi sau mỗi thay đổi trên form. Lưu nháp sau một khoảng ngắn.
  void changed({bool rebuild = false}) {
    if (_disposed || locked) return;
    _dirty = true;
    _revalidate();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), () {
      unawaited(saveDraft());
    });
    if (rebuild || showErrors) _notify();
  }

  void _revalidate() {
    if (showErrors) errors = QuestionValidation.validate(draft);
  }

  Future<void> saveDraft() async {
    _saveTimer?.cancel();
    if (!ready) return;
    try {
      await drafts.save(
        userId: userId,
        name: draft.draftName,
        data: draft.toJson(),
      );
      _dirty = false;
      if (_disposed) return;
      draftStatus = 'Đã lưu bản nháp trên máy.';
    } catch (_) {
      if (_disposed) return;
      draftStatus =
          'Không lưu được bản nháp. Đừng đóng ứng dụng trước khi gửi.';
    }
    _notify();
  }

  void selectClass(CourseClassOption option) {
    draft.courseClass = option;
    changed(rebuild: true);
  }

  void addQuestion() {
    draft.questions.add(QuestionDraft());
    changed(rebuild: true);
  }

  Future<void> removeQuestion(QuestionDraft question) async {
    draft.questions.remove(question);
    changed(rebuild: true);
    for (final image in question.images) {
      if (!image.uploaded && image.localPath != null) {
        await images.discard(image.localPath!);
      }
    }
  }

  void addOption(QuestionDraft question) {
    if (question.options.length >= QuestionValidation.maxOptions) return;
    question.options.add(OptionDraft());
    changed(rebuild: true);
  }

  void removeOption(QuestionDraft question, OptionDraft option) {
    question.options.remove(option);
    changed(rebuild: true);
  }

  Future<void> addImage(QuestionDraft question, {required bool camera}) async {
    if (pickingImage || busy || locked) return;
    if (question.images.length >= QuestionValidation.maxImagesPerQuestion) {
      _setMessage(
        'Mỗi câu hỏi đính kèm tối đa '
        '${QuestionValidation.maxImagesPerQuestion} ảnh.',
      );
      return;
    }
    pickingImage = true;
    _notify();
    try {
      // Lưu nháp trước khi rời app sang camera/thư viện ảnh.
      await saveDraft();
      final path = await images.pick(camera: camera, userId: userId);
      if (path == null) return;
      if (_disposed || !draft.questions.contains(question)) {
        await images.discard(path);
        return;
      }
      question.images.add(DraftImage(localPath: path));
      message = null;
      changed(rebuild: true);
      await saveDraft();
    } on AppFailure catch (error) {
      _setMessage(error.message);
    } catch (_) {
      _setMessage('Không thể thêm ảnh. Vui lòng thử lại.');
    } finally {
      pickingImage = false;
      _notify();
    }
  }

  Future<void> removeImage(QuestionDraft question, DraftImage image) async {
    question.images.remove(image);
    changed(rebuild: true);
    if (!image.uploaded && image.localPath != null) {
      await images.discard(image.localPath!);
    }
  }

  Future<SubmitOutcome?> submit() async {
    if (busy || _disposed || locked) return null;
    showErrors = true;
    errors = QuestionValidation.validate(draft);
    if (errors.isNotEmpty) {
      _setMessage('Vui lòng kiểm tra lại các mục được đánh dấu.');
      return null;
    }
    busy = true;
    message = null;
    progress = 'Đang lưu bản nháp…';
    _cancel = CancelToken();
    _notify();
    try {
      await saveDraft();
      if (draft.pending != null) {
        progress = 'Đang kiểm tra lần gửi trước…';
        _notify();
        try {
          final existing = await _verifyPending();
          if (existing != null) return existing;
        } on AppFailure catch (error) {
          _handleVerifyFailure(error);
          return null;
        }
      }
      if (!await _uploadImages()) return null;
      progress = isEdit ? 'Đang lưu thay đổi…' : 'Đang gửi đề xuất…';
      draft.pending = PendingVerification(
        attemptedAt: DateTime.now().toUtc(),
        kind: isEdit ? 'update' : 'propose',
      );
      await saveDraft();
      _notify();
      final SubmitOutcome outcome;
      if (isEdit) {
        await repository.updateSubmission(
          draft.sessionId!,
          draft.toUpdateJson(),
          cancelToken: _cancel,
        );
        outcome = ProposalUpdated(draft.sessionId!);
      } else {
        final result = await repository.propose(
          draft.toProposeJson(),
          cancelToken: _cancel,
        );
        outcome = ProposalCreated(result.sessionId);
      }
      await _finish();
      return outcome;
    } on AppFailure catch (error) {
      await _handleSendFailure(error);
      return null;
    } catch (_) {
      _setMessage('Không thể gửi đề xuất. Bản nháp vẫn được giữ trên máy.');
      return null;
    } finally {
      busy = false;
      progress = null;
      _cancel = null;
      _notify();
    }
  }

  /// Lỗi khi kiểm tra lần gửi trước: giữ cờ chưa xác nhận, không gửi mù.
  void _handleVerifyFailure(AppFailure error) {
    if (error.kind == FailureKind.cancelled) return;
    if (isEdit &&
        (error.kind == FailureKind.forbidden ||
            error.kind == FailureKind.notFound ||
            error.code == '2002')) {
      locked = true;
      _setMessage(
        error.kind == FailureKind.notFound
            ? 'Phiên đề xuất không còn tồn tại. Nội dung bạn nhập vẫn được giữ.'
            : 'Phiên không còn ở trạng thái Chờ duyệt hoặc bạn không còn quyền '
                  'sửa. Nội dung bạn nhập vẫn được giữ để xem lại.',
      );
      return;
    }
    _setMessage(
      'Chưa kiểm tra được kết quả lần gửi trước nên chưa gửi lại. '
      '${error.message}',
    );
  }

  Future<void> _handleSendFailure(AppFailure error) async {
    // Hủy khi rời màn: giữ cờ chưa xác nhận để lần sau kiểm tra.
    if (error.kind == FailureKind.cancelled) return;
    if (isUncertainWrite(error)) {
      // Giữ cờ pending: lần sau phải kiểm tra trước khi gửi lại.
      await saveDraft();
      _setMessage(
        'Chưa xác nhận được kết quả từ máy chủ. Bản nháp vẫn được giữ; '
        'khi gửi lại ứng dụng sẽ kiểm tra trước để tránh tạo trùng.',
      );
      return;
    }
    // Server đã từ chối rõ ràng hoặc request chưa rời máy: không có gì được tạo.
    draft.pending = null;
    if (error.statusCode == 404 && !isEdit) {
      // Swagger: 404 khi ảnh tạm đã hết hạn. Upload lại ảnh còn tệp trên máy.
      for (final image in draft.allImages) {
        if (image.localPath != null) image.remoteUrl = null;
      }
    }
    if (isEdit &&
        (error.kind == FailureKind.forbidden || error.code == '2002')) {
      locked = true;
      await saveDraft();
      _setMessage(
        'Phiên không còn ở trạng thái Chờ duyệt hoặc bạn không còn quyền sửa. '
        'Nội dung bạn nhập vẫn được giữ để xem lại.',
      );
      return;
    }
    await saveDraft();
    final text = switch (error.kind) {
      FailureKind.offline =>
        'Không có kết nối mạng. Bản nháp đã được lưu, hãy gửi lại khi có mạng.',
      FailureKind.notFound when isEdit =>
        'Phiên đề xuất không còn tồn tại. Nội dung bạn nhập vẫn được giữ.',
      FailureKind.notFound =>
        'Ảnh đính kèm đã hết hạn trên máy chủ. Hãy bấm gửi lại để tải lại ảnh.',
      _ => error.message,
    };
    _setMessage(text);
  }

  /// Kiểm tra lần gửi chưa xác nhận. Trả kết quả nếu phiên đã được tạo; nếu
  /// không, gỡ cờ để gửi tiếp. Lỗi mạng thì dừng, không gửi mù.
  Future<SubmitOutcome?> _verifyPending() async {
    final pending = draft.pending!;
    if (isEdit) {
      final detail = await repository.submissionDetail(
        draft.sessionId!,
        cancelToken: _cancel,
      );
      if (!detail.editable) {
        throw const AppFailure(
          FailureKind.forbidden,
          'Phiên không còn ở trạng thái Chờ duyệt.',
        );
      }
      _adoptServerQuestionIds(detail);
      // Gửi lại PUT với ID đã biết là ghi đè cùng nội dung, không thêm câu trùng.
      draft.pending = null;
      await saveDraft();
      return null;
    }
    final page = await repository.mySubmissions(
      query: draft.title.trim(),
      limit: 20,
      cancelToken: _cancel,
    );
    final title = draft.title.trim();
    // Cho phép lệch giờ máy/server; chỉ so trong cửa sổ quanh lần gửi.
    final earliest = pending.attemptedAt.subtract(const Duration(hours: 1));
    for (final item in page.items) {
      final created = item.createdAt;
      if (item.title.trim() == title &&
          (item.questionCount == null ||
              item.questionCount == draft.questions.length) &&
          (created == null || !created.isBefore(earliest))) {
        await _finish();
        return ProposalFoundExisting(item.sessionId);
      }
    }
    draft.pending = null;
    await saveDraft();
    return null;
  }

  /// Câu mới (chưa có ID) có thể đã được thêm ở lần PUT mất phản hồi.
  void _adoptServerQuestionIds(SubmissionDetail detail) {
    final known = {
      for (final q in draft.questions)
        if (q.questionId != null) q.questionId,
    };
    final available = [
      for (final q in detail.questions)
        if (!known.contains(q.questionId)) q,
    ];
    for (final q in draft.questions.where((q) => q.questionId == null)) {
      final index = available.indexWhere(
        (s) => s.content.trim() == q.content.trim(),
      );
      if (index >= 0) q.questionId = available.removeAt(index).questionId;
    }
  }

  Future<bool> _uploadImages() async {
    final pending = [
      for (final image in draft.allImages)
        if (!image.uploaded) image,
    ];
    for (var i = 0; i < pending.length; i++) {
      progress = 'Đang tải ảnh ${i + 1}/${pending.length}…';
      _notify();
      final image = pending[i];
      try {
        image.remoteUrl = await images.upload(
          image.localPath!,
          cancelToken: _cancel,
        );
        await saveDraft();
      } on AppFailure catch (error) {
        if (error.kind == FailureKind.cancelled) return false;
        _setMessage(
          '${error.message} Đã tải $i/${pending.length} ảnh; '
          'ảnh đã tải xong sẽ không phải tải lại.',
        );
        return false;
      }
    }
    return true;
  }

  Future<void> _finish() async {
    final leftovers = [
      for (final image in draft.allImages)
        if (image.localPath != null) image.localPath!,
    ];
    draft.pending = null;
    try {
      await drafts.remove(userId: userId, name: draft.draftName);
    } catch (_) {}
    _dirty = false;
    for (final path in leftovers) {
      await images.discard(path);
    }
  }

  /// Bỏ nháp và quay về nội dung ban đầu (phiên đang sửa hoặc form trống).
  Future<void> discardDraft() async {
    if (busy) return;
    _saveTimer?.cancel();
    final local = [
      for (final image in draft.allImages)
        if (!image.uploaded && image.localPath != null) image.localPath!,
    ];
    try {
      await drafts.remove(userId: userId, name: draft.draftName);
    } catch (_) {}
    for (final path in local) {
      await images.discard(path);
    }
    if (_disposed) return;
    draft = editing != null
        ? ProposalDraft.fromSubmission(editing!)
        : ProposalDraft();
    _dirty = false;
    restoredFromDraft = false;
    showErrors = false;
    errors = const {};
    message = null;
    locked = false;
    draftStatus = 'Đã bỏ bản nháp.';
    _syncSelectedClass();
    _notify();
  }

  void _setMessage(String text, {bool error = true}) {
    message = text;
    messageIsError = error;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _saveTimer?.cancel();
    if (_dirty && ready) {
      // Lưu lần cuối khi rời màn; không chờ để tránh giữ widget.
      unawaited(
        drafts
            .save(userId: userId, name: draft.draftName, data: draft.toJson())
            .catchError((Object _) {}),
      );
    }
    _cancel?.cancel();
    classes
      ..removeListener(_syncSelectedClass)
      ..dispose();
    super.dispose();
  }
}
