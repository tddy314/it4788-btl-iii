import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/errors/app_failure.dart';
import '../../core/storage/cached_resource_controller.dart';
import '../../core/widgets/app_states.dart';
import 'question_bank_repository.dart';
import 'question_bank_routes.dart';
import 'question_bank_widgets.dart';
import 'question_models.dart';

/// Chi tiết phiên đề xuất của chính mình và kết quả duyệt từng câu.
class SubmissionDetailScreen extends StatefulWidget {
  const SubmissionDetailScreen({super.key, required this.sessionId});
  final int sessionId;
  @override
  State<SubmissionDetailScreen> createState() => _SubmissionDetailScreenState();
}

class _SubmissionDetailScreenState extends State<SubmissionDetailScreen> {
  CachedResourceController<SubmissionDetail>? _controller;
  late QuestionBankRepository _repository;
  final _cancel = CancelToken();
  bool _deleting = false;
  bool _changed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final dependencies = AppScope.of(context);
    _repository = QuestionBankRepository(dependencies.api);
    _controller = CachedResourceController<SubmissionDetail>(
      cache: dependencies.cache,
      userId: dependencies.session.tokens?.userId ?? '',
      resource: 'qb.submission.${widget.sessionId}',
      fetch: () =>
          _repository.submissionDetail(widget.sessionId, cancelToken: _cancel),
      encode: (value) => value.toJson(),
      decode: SubmissionDetail.fromJson,
    )..load();
  }

  @override
  void dispose() {
    _cancel.cancel();
    _controller?.dispose();
    super.dispose();
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _edit(SubmissionDetail detail) async {
    final changed = await Navigator.of(context)
        .pushNamed(QuestionBankRoutes.compose, arguments: detail);
    if (changed == true && mounted) {
      _changed = true;
      await _controller!.load();
    }
  }

  Future<void> _delete(SubmissionDetail detail) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa đề xuất?'),
        content: const Text(
          'Toàn bộ câu hỏi và ảnh trong phiên này sẽ bị xóa. Chỉ xóa được khi phiên còn Chờ duyệt.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _deleting) return;
    setState(() => _deleting = true);
    try {
      await _repository.deleteSubmission(
        detail.sessionId,
        cancelToken: _cancel,
      );
      if (!mounted) return;
      _snack('Đã xóa đề xuất.');
      Navigator.of(context).pop(true);
    } on AppFailure catch (error) {
      if (!mounted || error.kind == FailureKind.cancelled) return;
      if (isUncertainWrite(error)) {
        // Không gửi lại DELETE; kiểm tra phiên còn tồn tại hay không.
        await _verifyDeleted();
        return;
      }
      if (error.kind == FailureKind.forbidden ||
          error.kind == FailureKind.notFound) {
        _snack(
          error.kind == FailureKind.notFound
              ? 'Phiên đề xuất không còn tồn tại.'
              : 'Phiên đã chuyển trạng thái nên không thể xóa.',
        );
        _changed = true;
        await _controller!.load();
        return;
      }
      _snack(error.message);
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _verifyDeleted() async {
    try {
      await _repository.submissionDetail(
        widget.sessionId,
        cancelToken: _cancel,
      );
      if (!mounted) return;
      _snack(
        'Chưa xác nhận được việc xóa và phiên vẫn còn trên máy chủ. Bạn có thể thử xóa lại.',
      );
      await _controller!.load();
    } on AppFailure catch (error) {
      if (!mounted) return;
      if (error.kind == FailureKind.notFound) {
        _snack('Đã xóa đề xuất.');
        Navigator.of(context).pop(true);
      } else if (error.kind != FailureKind.cancelled) {
        _snack(
          'Chưa xác nhận được kết quả xóa. Hãy kiểm tra lại khi có mạng trước khi xóa lại.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller!;
    // Back (nút hoặc cử chỉ) trả về `_changed` để danh sách biết cần làm mới.
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_deleting) {
          _snack('Đang xóa đề xuất, vui lòng đợi.');
        } else {
          Navigator.of(context).pop(_changed);
        }
      },
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final detail = controller.data;
          // Chỉ cho sửa/xóa khi có dữ liệu mới nhất từ máy chủ.
          final fresh = detail != null && !controller.isFromCache;
          final canModify =
              fresh && detail.editable && !_deleting && !controller.isLoading;
          return Scaffold(
            appBar: AppBar(
              title: const Text('Chi tiết đề xuất'),
              actions: [
                if (detail != null && detail.editable) ...[
                  IconButton(
                    tooltip: 'Sửa đề xuất',
                    onPressed: canModify ? () => _edit(detail) : null,
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    tooltip: 'Xóa đề xuất',
                    onPressed: canModify ? () => _delete(detail) : null,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ],
            ),
            body: SafeArea(child: _body(context, controller)),
          );
        },
      ),
    );
  }

  Widget _body(
    BuildContext context,
    CachedResourceController<SubmissionDetail> controller,
  ) {
    final detail = controller.data;
    if (detail == null) {
      if (controller.isLoading || controller.failure == null) {
        return const AppLoadingState();
      }
      return AppErrorState(
        message: controller.failure!.message,
        onRetry: controller.load,
      );
    }
    final failure = controller.failure;
    return RefreshIndicator(
      onRefresh: controller.load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (controller.isLoading || _deleting)
            const LinearProgressIndicator(),
          if (failure != null)
            QbNotice(
              message: failure.message,
              onRetry: controller.isLoading ? null : controller.load,
            ),
          if (controller.isFromCache && failure == null)
            QbNotice(message: savedAtText(controller.savedAt), isError: false),
          if (controller.isFromCache && detail.editable)
            const QbNotice(
              message:
                  'Cần tải dữ liệu mới nhất từ máy chủ trước khi sửa hoặc xóa.',
              isError: false,
            ),
          _Header(detail: detail),
          for (var i = 0; i < detail.questions.length; i++)
            _QuestionCard(index: i, question: detail.questions[i]),
          if (detail.questions.isEmpty)
            const AppEmptyState(title: 'Phiên chưa có câu hỏi nào'),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.detail});
  final SubmissionDetail detail;
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final reviewed = detail.status != SessionStatus.pending;
    final approved = detail.countWith(QuestionReviewStatus.approved);
    final rejected = detail.countWith(QuestionReviewStatus.rejected);
    final waiting = detail.questions.length - approved - rejected;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    detail.title.isEmpty
                        ? 'Bộ câu hỏi không tên'
                        : detail.title,
                    style: text.titleLarge,
                  ),
                ),
                const SizedBox(width: 8),
                QbStatusChip.session(detail.status),
              ],
            ),
            const SizedBox(height: 8),
            if (detail.subjectLabel.isNotEmpty) Text(detail.subjectLabel),
            Text(
              [
                if (detail.classCode.isNotEmpty) 'Lớp ${detail.classCode}',
                if (detail.semesterName.isNotEmpty)
                  'Học kỳ ${detail.semesterName}',
              ].join(' · '),
              style: text.bodySmall,
            ),
            if (detail.sessionCode.isNotEmpty)
              SelectableText(
                'Mã phiên: ${detail.sessionCode}',
                style: text.bodySmall,
              ),
            if (detail.createdAt != null)
              Text(
                'Gửi lúc ${qbFormatDate(detail.createdAt)}',
                style: text.bodySmall,
              ),
            if (detail.content.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(detail.content),
            ],
            if (detail.sourceUrl != null && detail.sourceUrl!.isNotEmpty) ...[
              const SizedBox(height: 4),
              SelectableText(
                'Nguồn tham khảo: ${detail.sourceUrl}',
                style: text.bodySmall,
              ),
            ],
            const Divider(height: 24),
            if (!reviewed)
              const Text(
                'Phiên đang chờ giảng viên duyệt. Bạn có thể sửa hoặc xóa khi phiên còn ở trạng thái này.',
              )
            else ...[
              Text(
                'Kết quả từng câu: được chọn $approved · không được chọn $rejected'
                '${waiting > 0 ? ' · chưa có kết quả $waiting' : ''}',
              ),
              if (detail.status == SessionStatus.resolved)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '"Đã xử lý" nghĩa là giảng viên đã chốt phiên, không có nghĩa mọi câu đều được chọn.',
                    style: text.bodySmall,
                  ),
                ),
              if (detail.reviewedBy != null && detail.reviewedBy!.isNotEmpty)
                Text(
                  'Người duyệt: ${detail.reviewedBy}',
                  style: text.bodySmall,
                ),
              if (detail.reviewedAt != null)
                Text(
                  'Duyệt lúc ${qbFormatDate(detail.reviewedAt)}',
                  style: text.bodySmall,
                ),
            ],
            if (detail.status == SessionStatus.resolved) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pushNamed(
                  QuestionBankRoutes.practice,
                  arguments: detail.sessionId,
                ),
                icon: const Icon(Icons.quiz_outlined),
                label: const Text('Luyện tập bộ câu hỏi'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({required this.index, required this.question});
  final int index;
  final SubmissionQuestion question;
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final status = question.status;
    final reason = [
      rejectionLabel(question.rejectionCode),
      question.rejectionReason ?? '',
    ].where((s) => s.trim().isNotEmpty).join(': ');
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Câu ${index + 1}', style: text.titleSmall),
                ),
                if (status != null) QbStatusChip.question(status),
              ],
            ),
            const SizedBox(height: 8),
            Text(question.content),
            QbImageGrid(urls: question.imageUrls),
            const SizedBox(height: 8),
            for (final option in question.options)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      option.isCorrect == true
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 20,
                      color: option.isCorrect == true
                          ? scheme.primary
                          : scheme.outline,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text('${option.key}. ${option.text}')),
                  ],
                ),
              ),
            if (question.explanation.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Giải thích: ${question.explanation}',
                style: text.bodySmall,
              ),
            ],
            const SizedBox(height: 8),
            // Nguồn và mức tự tin chỉ hiển thị cho chính tác giả ở màn này.
            Text(
              [
                if (question.source != null) question.source!.label,
                if (question.confidence != null)
                  'Mức tự tin ${_confidence(question.confidence!)}/4',
              ].join(' · '),
              style: text.bodySmall,
            ),
            if (status == QuestionReviewStatus.rejected && reason.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Lý do: $reason',
                  style: text.bodySmall?.copyWith(color: scheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _confidence(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1);
}
