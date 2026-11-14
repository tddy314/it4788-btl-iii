import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/errors/app_failure.dart';
import '../../core/storage/cached_resource_controller.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_states.dart';
import 'question_bank_repository.dart';
import 'question_bank_routes.dart';
import 'question_bank_widgets.dart';
import 'question_models.dart';
import 'question_validation.dart';

/// Kết quả/tương tác cục bộ sau khi server xác nhận, chờ lần tải lại kế tiếp.
class _QuestionState {
  final selected = <String>{};
  bool submitting = false;
  String? error;
  AnswerResult? result;
  int? myRating;
  bool reported = false;
}

/// Luyện tập một bộ câu hỏi: trả lời, xem kết quả do server chấm, đánh giá 0–4
/// và báo lỗi câu hỏi. Không tự chấm bằng dữ liệu cache.
class PracticeScreen extends StatefulWidget {
  const PracticeScreen({super.key, required this.sessionId});
  final int sessionId;
  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<PracticeScreen> {
  CachedResourceController<PracticeSession>? _controller;
  late QuestionBankRepository _repository;
  final _cancel = CancelToken();
  final _states = <int, _QuestionState>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final dependencies = AppScope.of(context);
    _repository = QuestionBankRepository(dependencies.api);
    _controller = CachedResourceController<PracticeSession>(
      cache: dependencies.cache,
      userId: dependencies.session.tokens?.userId ?? '',
      resource: 'qb.practice.${widget.sessionId}',
      fetch: () =>
          _repository.practiceQuestions(widget.sessionId, cancelToken: _cancel),
      encode: (value) => value.toJson(),
      decode: PracticeSession.fromJson,
    )..load();
  }

  @override
  void dispose() {
    _cancel.cancel();
    _controller?.dispose();
    super.dispose();
  }

  _QuestionState _stateOf(int id) =>
      _states.putIfAbsent(id, _QuestionState.new);

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  /// Tải lại từ server; dữ liệu server thay thế kết quả cục bộ.
  Future<void> _reload() async {
    await _controller!.load();
    if (!mounted) return;
    if (!_controller!.isFromCache && _controller!.failure == null) {
      setState(() {
        for (final state in _states.values) {
          state.result = null;
          state.myRating = null;
          state.reported = false;
        }
      });
    }
  }

  Future<void> _answer(PracticeQuestion question) async {
    final state = _stateOf(question.questionId);
    if (state.submitting) return;
    if (state.selected.isEmpty) {
      setState(() => state.error = 'Hãy chọn ít nhất một đáp án.');
      return;
    }
    setState(() {
      state.submitting = true;
      state.error = null;
    });
    final keys = [
      for (final option in question.options)
        if (state.selected.contains(option.key)) option.key,
    ];
    try {
      final result = await _repository.answer(
        question.questionId,
        keys,
        questionUpdatedAt: question.rawUpdatedAt,
        cancelToken: _cancel,
      );
      if (!mounted) return;
      setState(() => state.result = result);
    } on AppFailure catch (error) {
      if (!mounted || error.kind == FailureKind.cancelled) return;
      if (error.statusCode == 409 || error.code == '1010') {
        setState(
          () => state.error = 'Bạn đã trả lời câu này trước đó. Đang tải kết quả đã lưu trên máy chủ…',
        );
        await _reload();
      } else if (error.statusCode == 412) {
        setState(() {
          state.selected.clear();
          state.error = 'Câu hỏi vừa được cập nhật. Đã tải nội dung mới, hãy đọc lại trước khi trả lời.';
        });
        await _reload();
      } else if (isUncertainWrite(error)) {
        // Không gửi lại; kiểm tra server đã ghi nhận câu trả lời chưa.
        setState(
          () => state.error =
              'Chưa xác nhận được câu trả lời. Đang kiểm tra lại với máy chủ…',
        );
        await _reload();
        if (!mounted) return;
        final latest = _find(question.questionId);
        setState(
          () => state.error = latest?.answered == true ? null : 'Máy chủ chưa ghi nhận câu trả lời. Bạn có thể bấm Trả lời lần nữa.',
        );
      } else {
        setState(() => state.error = error.message);
      }
    } finally {
      if (mounted) setState(() => state.submitting = false);
    }
  }

  PracticeQuestion? _find(int id) {
    for (final q
        in _controller!.data?.questions ?? const <PracticeQuestion>[]) {
      if (q.questionId == id) return q;
    }
    return null;
  }

  Future<void> _rate(PracticeQuestion question) async {
    final state = _stateOf(question.questionId);
    final initial = state.myRating ?? question.myRating?.round();
    final saved = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _RatingSheet(
        initialRating: initial,
        initialComment: question.ratingComment ?? '',
        submit: (rating, comment) async {
          try {
            await _repository.rate(
              question.questionId,
              rating,
              comment: comment,
              cancelToken: _cancel,
            );
            return null;
          } on AppFailure catch (error) {
            return isUncertainWrite(error)
                ? 'Chưa xác nhận được đánh giá. Gửi lại sẽ cập nhật đánh giá của bạn, không tạo bản trùng.'
                : error.message;
          }
        },
      ),
    );
    if (saved != null && mounted) {
      setState(() => state.myRating = saved);
      _snack('Đã lưu đánh giá.');
    }
  }

  Future<void> _report(PracticeQuestion question) async {
    final state = _stateOf(question.questionId);
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _ReportSheet(
        submit: (description) async {
          try {
            await _repository.report(
              question.questionId,
              description,
              cancelToken: _cancel,
            );
            return null;
          } on AppFailure catch (error) {
            return isUncertainWrite(error)
                ? 'Chưa xác nhận được báo lỗi. Gửi lại sẽ cập nhật báo lỗi của bạn, không tạo bản trùng.'
                : error.message;
          }
        },
      ),
    );
    if (sent == true && mounted) {
      setState(() => state.reported = true);
      _snack('Đã gửi báo lỗi. Cảm ơn bạn đã góp ý.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller!;
    return Scaffold(
      appBar: AppBar(title: const Text('Luyện tập')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final data = controller.data;
            if (data == null) {
              if (controller.isLoading || controller.failure == null) {
                return const AppLoadingState();
              }
              return AppErrorState(
                message: controller.failure!.message,
                onRetry: controller.load,
              );
            }
            final failure = controller.failure;
            final answered = data.questions
                .where(
                  (q) => q.answered || _states[q.questionId]?.result != null,
                )
                .length;
            return RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  if (controller.isLoading) const LinearProgressIndicator(),
                  if (failure != null)
                    QbNotice(
                      message: failure.message,
                      onRetry: controller.isLoading ? null : _reload,
                    ),
                  if (controller.isFromCache && failure == null)
                    QbNotice(
                      message: savedAtText(controller.savedAt),
                      isError: false,
                    ),
                  _header(context, data, answered),
                  if (data.questions.isEmpty)
                    const AppEmptyState(
                      title: 'Bộ câu hỏi chưa có câu hỏi nào',
                    ),
                  for (var i = 0; i < data.questions.length; i++)
                    _questionCard(
                      context,
                      i,
                      data.questions.length,
                      data.questions[i],
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _header(BuildContext context, PracticeSession data, int answered) {
    final text = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              data.title.isEmpty ? 'Bộ câu hỏi không tên' : data.title,
              style: text.titleLarge,
            ),
            if (data.subjectLabel.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(data.subjectLabel),
            ],
            if (data.content.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(data.content),
            ],
            const SizedBox(height: 8),
            Text(
              'Đã trả lời $answered/${data.questions.length} câu',
              style: text.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _questionCard(
    BuildContext context,
    int index,
    int total,
    PracticeQuestion question,
  ) {
    final state = _stateOf(question.questionId);
    final result = state.result;
    final answered = question.answered || result != null;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final correctKeys = {
      ...parseAnswerKeys(result?.correctAnswer ?? question.correctAnswer),
      for (final o in question.options)
        if (o.isCorrect == true) o.key.toUpperCase(),
    };
    final selectedKeys = result != null
        ? {for (final k in state.selected) k.toUpperCase()}
        : {for (final k in question.selectedKeys) k.toUpperCase()};
    final isCorrect = result != null ? result.isCorrect : question.wasCorrect;
    final explanation = result?.explanation ?? question.explanation;
    final rating = state.myRating ?? question.myRating?.round();
    final reported = state.reported || question.reported;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Câu ${index + 1}/$total',
                    style: text.titleSmall,
                  ),
                ),
                if (answered && isCorrect != null)
                  QbStatusChip(
                    label: isCorrect ? 'Đúng' : 'Chưa đúng',
                    tone: isCorrect ? QbTone.positive : QbTone.negative,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(question.content),
            QbImageGrid(urls: question.imageUrls),
            const SizedBox(height: 8),
            for (final option in question.options)
              answered
                  ? _AnsweredOption(
                      option: option,
                      correct: correctKeys.contains(option.key.toUpperCase()),
                      selected: selectedKeys.contains(option.key.toUpperCase()),
                    )
                  : CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                      value: state.selected.contains(option.key),
                      title: Text('${option.key}. ${option.text}'),
                      onChanged: state.submitting
                          ? null
                          : (value) => setState(() {
                              state.error = null;
                              if (value == true) {
                                state.selected.add(option.key);
                              } else {
                                state.selected.remove(option.key);
                              }
                            }),
                    ),
            if (state.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  state.error!,
                  style: text.bodySmall?.copyWith(color: scheme.error),
                ),
              ),
            if (!answered) ...[
              const SizedBox(height: 8),
              AppButton(
                label: 'Trả lời',
                isLoading: state.submitting,
                onPressed: () => _answer(question),
              ),
            ] else ...[
              const SizedBox(height: 8),
              if (correctKeys.isEmpty)
                Text(
                  'Máy chủ chưa cung cấp đáp án đúng cho câu này.',
                  style: text.bodySmall,
                )
              else
                Text(
                  'Đáp án đúng: ${(correctKeys.toList()..sort()).join(', ')}',
                  style: text.bodyMedium,
                ),
              if (explanation != null && explanation.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('Giải thích: $explanation', style: text.bodySmall),
              ],
              if (question.updatedSinceAnswer)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Câu hỏi đã được chỉnh sửa sau khi bạn trả lời.',
                    style: text.bodySmall,
                  ),
                ),
            ],
            const Divider(height: 24),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                TextButton.icon(
                  onPressed: () => _rate(question),
                  icon: const Icon(Icons.star_outline),
                  label: Text(
                    rating == null ? 'Đánh giá' : 'Đánh giá của bạn: $rating/4',
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _report(question),
                  icon: const Icon(Icons.flag_outlined),
                  label: Text(reported ? 'Đã báo lỗi' : 'Báo lỗi'),
                ),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).pushNamed(
                    QuestionBankRoutes.ratings,
                    arguments: question.questionId,
                  ),
                  icon: const Icon(Icons.reviews_outlined),
                  label: Text(
                    question.ratingCount > 0
                        ? 'Xem đánh giá (${question.ratingCount})'
                        : 'Xem đánh giá',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AnsweredOption extends StatelessWidget {
  const _AnsweredOption({
    required this.option,
    required this.correct,
    required this.selected,
  });
  final QuestionOptionData option;
  final bool correct;
  final bool selected;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, icon, color) = correct
        ? (scheme.primaryContainer, Icons.check_circle, scheme.primary)
        : selected
        ? (scheme.errorContainer, Icons.cancel, scheme.error)
        : (null, Icons.radio_button_unchecked, scheme.outline);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text('${option.key}. ${option.text}')),
          if (selected)
            Text('Bạn chọn', style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

/// Trả về null khi thành công, hoặc thông báo lỗi để giữ nguyên nội dung nhập.
typedef _RateSubmit = Future<String?> Function(int rating, String comment);

class _RatingSheet extends StatefulWidget {
  const _RatingSheet({
    required this.initialRating,
    required this.initialComment,
    required this.submit,
  });
  final int? initialRating;
  final String initialComment;
  final _RateSubmit submit;
  @override
  State<_RatingSheet> createState() => _RatingSheetState();
}

class _RatingSheetState extends State<_RatingSheet> {
  late int? _rating = widget.initialRating;
  late final _comment = TextEditingController(text: widget.initialComment);
  bool _busy = false;
  String? _error;

  static const _labels = ['Rất kém', 'Kém', 'Trung bình', 'Tốt', 'Rất tốt'];

  Future<void> _save() async {
    if (_busy) return;
    final error =
        QuestionValidation.rating(_rating) ??
        QuestionValidation.comment(_comment.text);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final failure = await widget.submit(_rating!, _comment.text);
    if (!mounted) return;
    if (failure == null) {
      Navigator.of(context).pop(_rating);
    } else {
      setState(() {
        _busy = false;
        _error = failure;
      });
    }
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Đánh giá câu hỏi',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            const Text('Thang điểm từ 0 (rất kém) đến 4 (rất tốt).'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (var v = 0; v <= 4; v++)
                  ChoiceChip(
                    label: Text('$v · ${_labels[v]}'),
                    selected: _rating == v,
                    onSelected: _busy
                        ? null
                        : (_) => setState(() {
                            _rating = v;
                            _error = null;
                          }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _comment,
              enabled: !_busy,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Nhận xét (không bắt buộc)',
                helperText: 'Tối đa 500 ký tự',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            AppButton(
              label: 'Lưu đánh giá',
              isLoading: _busy,
              onPressed: _save,
            ),
          ],
        ),
      ),
    ),
  );
}

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({required this.submit});
  final Future<String?> Function(String description) submit;
  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  final _description = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _send() async {
    if (_busy) return;
    final error = QuestionValidation.comment(_description.text, required: true);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final failure = await widget.submit(_description.text);
    if (!mounted) return;
    if (failure == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _busy = false;
        _error = failure;
      });
    }
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Báo lỗi câu hỏi',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            const Text(
              'Mô tả lỗi bạn phát hiện (đáp án sai, đề thiếu dữ kiện…). Gửi lại sẽ cập nhật báo lỗi trước đó.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              enabled: !_busy,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Mô tả lỗi *',
                helperText: 'Tối đa 500 ký tự',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            AppButton(label: 'Gửi báo lỗi', isLoading: _busy, onPressed: _send),
          ],
        ),
      ),
    ),
  );
}
