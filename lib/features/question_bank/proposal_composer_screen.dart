import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_network_image.dart';
import '../../core/widgets/app_states.dart';
import 'proposal_composer_controller.dart';
import 'proposal_draft.dart';
import 'question_bank_repository.dart';
import 'question_bank_routes.dart';
import 'question_bank_widgets.dart';
import 'question_image_service.dart';
import 'question_models.dart';
import 'question_validation.dart';

/// Soạn bộ câu hỏi mới hoặc sửa phiên còn Chờ duyệt.
class ProposalComposerScreen extends StatefulWidget {
  const ProposalComposerScreen({super.key, this.editing, this.images});
  final SubmissionDetail? editing;

  /// Cho phép test thay thế picker/upload thật.
  final QuestionImageService? images;
  @override
  State<ProposalComposerScreen> createState() => _ProposalComposerScreenState();
}

class _ProposalComposerScreenState extends State<ProposalComposerScreen> {
  ProposalComposerController? _controller;

  /// Điểm neo để cuộn tới mục lỗi đầu tiên sau khi validate.
  final _anchors = <String, GlobalKey>{};
  GlobalKey _anchor(String id) => _anchors.putIfAbsent(id, GlobalKey.new);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final dependencies = AppScope.of(context);
    _controller = ProposalComposerController(
      repository: QuestionBankRepository(dependencies.api),
      drafts: dependencies.drafts,
      cache: dependencies.cache,
      images:
          widget.images ?? DeviceQuestionImageService(dependencies.mediaUpload),
      userId: dependencies.session.tokens?.userId ?? '',
      editing: widget.editing,
    )..init();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final outcome = await _controller!.submit();
    if (!mounted) return;
    if (outcome == null) {
      _revealFirstError();
      return;
    }
    final navigator = Navigator.of(context);
    switch (outcome) {
      case ProposalCreated(:final sessionId):
        _snack('Đã gửi đề xuất. Phiên đang chờ giảng viên duyệt.');
        await navigator.pushReplacementNamed(
          QuestionBankRoutes.submission,
          arguments: sessionId,
          result: true,
        );
      case ProposalFoundExisting(:final sessionId):
        _snack('Lần gửi trước đã được máy chủ ghi nhận. Đã mở đề xuất đó.');
        await navigator.pushReplacementNamed(
          QuestionBankRoutes.submission,
          arguments: sessionId,
          result: true,
        );
      case ProposalUpdated():
        _snack('Đã lưu thay đổi.');
        navigator.pop(true);
    }
  }

  void _revealFirstError() {
    final c = _controller!;
    if (c.errors.isEmpty) return;
    String? target;
    if (const ['class', 'title', 'source_url'].any(c.errors.containsKey)) {
      target = 'header';
    } else {
      for (var i = 0; i < c.draft.questions.length; i++) {
        if (c.errors.keys.any((k) => k.startsWith('q$i.'))) {
          target = c.draft.questions[i].id;
          break;
        }
      }
    }
    // Lỗi "cần tối thiểu 3 câu" nằm ở tiêu đề danh sách câu hỏi.
    target ??= 'questions';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _anchors[target]?.currentContext;
      if (context != null && context.mounted) {
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 300),
          alignment: 0.1,
        );
      }
    });
  }

  Future<void> _discard() async {
    final controller = _controller!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bỏ bản nháp?'),
        content: Text(
          controller.hasPendingVerification
              ? 'Lần gửi trước chưa được xác nhận và có thể đã được máy chủ ghi nhận. '
                    'Hãy kiểm tra mục "Đề xuất của tôi" trước khi bỏ bản nháp.'
              : 'Nội dung đang soạn và ảnh chưa gửi sẽ bị xóa khỏi máy.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Bỏ bản nháp'),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.discardDraft();
  }

  Future<void> _removeQuestion(QuestionDraft question) async {
    final hasContent =
        question.content.trim().isNotEmpty ||
        question.options.any((o) => o.text.trim().isNotEmpty) ||
        question.images.isNotEmpty;
    if (hasContent) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Xóa câu hỏi này?'),
          content: const Text('Nội dung câu hỏi sẽ bị xóa khỏi bản nháp.'),
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
      if (confirmed != true) return;
    }
    await _controller!.removeQuestion(question);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller!;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => PopScope<Object?>(
        canPop: !controller.busy,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && controller.busy) {
            _snack('Đang gửi, vui lòng đợi kết quả từ máy chủ.');
          }
        },
        child: Scaffold(
          appBar: AppBar(
            title: Text(controller.isEdit ? 'Sửa đề xuất' : 'Đề xuất câu hỏi'),
            actions: [
              if (controller.ready)
                PopupMenuButton<String>(
                  enabled: !controller.busy,
                  onSelected: (_) => _discard(),
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'discard', child: Text('Bỏ bản nháp')),
                  ],
                ),
            ],
          ),
          body: SafeArea(
            child: !controller.ready
                ? const AppLoadingState(message: 'Đang mở bản nháp…')
                : KeyedSubtree(
                    // Bản nháp bị thay (bỏ nháp) thì dựng lại toàn bộ ô nhập.
                    key: ObjectKey(controller.draft),
                    child: _form(context, controller),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _form(BuildContext context, ProposalComposerController c) {
    final draft = c.draft;
    final errors = c.errors;
    final text = Theme.of(context).textTheme;
    final enabled = !c.busy && !c.locked;
    // Không dùng ListView lười: mọi ô nhập luôn được dựng để cuộn tới lỗi.
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (c.draftStatus != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(c.draftStatus!, style: text.bodySmall),
            ),
          KeyedSubtree(
            key: _anchor('header'),
            child: _classSection(context, c),
          ),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: draft.title,
            enabled: enabled,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'Tiêu đề bộ câu hỏi *',
              errorText: errors['title'],
            ),
            onChanged: (value) {
              draft.title = value;
              c.changed();
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: draft.content,
            enabled: enabled,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Mô tả (không bắt buộc)',
            ),
            onChanged: (value) {
              draft.content = value;
              c.changed();
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: draft.sourceUrl,
            enabled: enabled,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: 'Đường dẫn tài liệu tham khảo (không bắt buộc)',
              errorText: errors['source_url'],
            ),
            onChanged: (value) {
              draft.sourceUrl = value;
              c.changed();
            },
          ),
          const SizedBox(height: 16),
          Text(
            'Câu hỏi (${draft.questions.length})',
            key: _anchor('questions'),
            style: text.titleMedium,
          ),
          Text(
            'Cần tối thiểu ${QuestionValidation.minQuestions} câu. Nguồn câu hỏi '
            'được khai báo trung thực và không hiển thị với giảng viên.',
            style: text.bodySmall,
          ),
          if (errors['questions'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                errors['questions']!,
                style: text.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          for (var i = 0; i < draft.questions.length; i++)
            KeyedSubtree(
              key: _anchor(draft.questions[i].id),
              child: _QuestionEditor(
                index: i,
                question: draft.questions[i],
                controller: c,
                enabled: enabled,
                onRemove: () => _removeQuestion(draft.questions[i]),
              ),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: enabled ? c.addQuestion : null,
            icon: const Icon(Icons.add),
            label: const Text('Thêm câu hỏi'),
          ),
          const SizedBox(height: 16),
          if (c.message != null) ...[
            QbNotice(message: c.message!, isError: c.messageIsError),
            const SizedBox(height: 12),
          ],
          if (c.progress != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(c.progress!, textAlign: TextAlign.center),
            ),
          AppButton(
            label: c.isEdit ? 'Lưu thay đổi' : 'Gửi đề xuất',
            icon: Icons.send_outlined,
            isLoading: c.busy,
            onPressed: c.locked ? null : _submit,
          ),
        ],
      ),
    );
  }

  Widget _classSection(BuildContext context, ProposalComposerController c) {
    final draft = c.draft;
    if (c.isEdit) {
      return InputDecorator(
        decoration: const InputDecoration(labelText: 'Lớp học phần'),
        child: Text(draft.courseClass?.label ?? 'Không rõ lớp học phần'),
      );
    }
    return ListenableBuilder(
      listenable: c.classes,
      builder: (context, _) {
        final classes = c.classes.data;
        final failure = c.classes.failure;
        if (classes == null) {
          if (failure != null) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (draft.courseClass != null)
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Lớp học phần đã chọn',
                    ),
                    child: Text(draft.courseClass!.label),
                  ),
                QbNotice(
                  message:
                      'Chưa tải được danh sách lớp học phần. ${failure.message}',
                  onRetry: c.classes.isLoading ? null : c.classes.load,
                ),
              ],
            );
          }
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Text('Đang tải lớp học phần…'),
              ],
            ),
          );
        }
        if (classes.isEmpty) {
          return QbNotice(
            message:
                'Bạn chưa tham gia lớp học phần nào. Hãy liên hệ giảng viên nếu '
                'bạn đang học môn nhưng chưa có trong danh sách.',
            onRetry: c.classes.isLoading ? null : c.classes.load,
          );
        }
        final selected = draft.courseClass?.courseClassId;
        final known = classes.any((k) => k.courseClassId == selected);
        final noneOpen = !classes.any((k) => k.canPropose);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<int>(
              key: ValueKey('class-$selected-${classes.length}'),
              initialValue: known ? selected : null,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Lớp học phần *',
                errorText: c.errors['class'],
              ),
              items: [
                for (final option in classes)
                  DropdownMenuItem(
                    value: option.courseClassId,
                    enabled: option.canPropose,
                    child: Text(
                      option.canPropose
                          ? option.label
                          : '${option.label} (đã kết thúc)',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: c.busy
                  ? null
                  : (id) {
                      for (final option in classes) {
                        if (option.courseClassId == id) c.selectClass(option);
                      }
                    },
            ),
            if (noneOpen)
              const QbNotice(
                message: 'Không có lớp học phần nào của học kỳ hiện tại đang nhận đề xuất.',
                isError: false,
              ),
            if (c.classes.isFromCache)
              QbNotice(message: savedAtText(c.classes.savedAt), isError: false),
          ],
        );
      },
    );
  }
}

class _QuestionEditor extends StatelessWidget {
  const _QuestionEditor({
    required this.index,
    required this.question,
    required this.controller,
    required this.enabled,
    required this.onRemove,
  });
  final int index;
  final QuestionDraft question;
  final ProposalComposerController controller;
  final bool enabled;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final errors = c.errors;
    final key = 'q$index';
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    Widget errorLine(String? message) => message == null
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              message,
              style: text.bodySmall?.copyWith(color: scheme.error),
            ),
          );
    final canAddImage =
        enabled &&
        !c.pickingImage &&
        question.images.length < QuestionValidation.maxImagesPerQuestion;
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Câu ${index + 1}', style: text.titleSmall),
                ),
                IconButton(
                  tooltip: 'Xóa câu hỏi',
                  onPressed: enabled ? onRemove : null,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            TextFormField(
              initialValue: question.content,
              enabled: enabled,
              minLines: 2,
              maxLines: 8,
              decoration: InputDecoration(
                labelText: 'Nội dung câu hỏi *',
                errorText: errors['$key.content'],
              ),
              onChanged: (value) {
                question.content = value;
                c.changed();
              },
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final image in question.images)
                  _ImageThumb(
                    image: image,
                    onRemove: enabled
                        ? () => c.removeImage(question, image)
                        : null,
                  ),
              ],
            ),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: canAddImage
                      ? () => c.addImage(question, camera: false)
                      : null,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Chọn ảnh'),
                ),
                TextButton.icon(
                  onPressed: canAddImage
                      ? () => c.addImage(question, camera: true)
                      : null,
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Chụp ảnh'),
                ),
              ],
            ),
            Text(
              'Tối đa ${QuestionValidation.maxImagesPerQuestion} ảnh, mỗi ảnh không quá 4 MB.',
              style: text.bodySmall,
            ),
            errorLine(errors['$key.images']),
            const SizedBox(height: 12),
            Text('Đáp án', style: text.titleSmall),
            Text(
              'Đánh dấu ô bên trái cho đáp án đúng (có thể nhiều đáp án).',
              style: text.bodySmall,
            ),
            for (var j = 0; j < question.options.length; j++)
              _OptionRow(
                key: ValueKey(question.options[j].id),
                label: optionKey(j),
                option: question.options[j],
                error: errors['$key.o$j'],
                enabled: enabled,
                canRemove:
                    question.options.length > QuestionValidation.minOptions,
                onChanged: () => c.changed(rebuild: true),
                onTextChanged: c.changed,
                onRemove: () => c.removeOption(question, question.options[j]),
              ),
            errorLine(errors['$key.correct'] ?? errors['$key.options']),
            if (question.options.length < QuestionValidation.maxOptions)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: enabled ? () => c.addOption(question) : null,
                  icon: const Icon(Icons.add),
                  label: const Text('Thêm đáp án'),
                ),
              ),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: question.explanation,
              enabled: enabled,
              minLines: 1,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Giải thích đáp án (không bắt buộc)',
              ),
              onChanged: (value) {
                question.explanation = value;
                c.changed();
              },
            ),
            const SizedBox(height: 12),
            Text('Nguồn câu hỏi *', style: text.titleSmall),
            const SizedBox(height: 4),
            SegmentedButton<QuestionSource>(
              emptySelectionAllowed: true,
              showSelectedIcon: false,
              segments: [
                for (final source in QuestionSource.values)
                  ButtonSegment(value: source, label: Text(source.label)),
              ],
              selected: {?question.source},
              onSelectionChanged: enabled
                  ? (value) {
                      question.source = value.isEmpty ? null : value.first;
                      c.changed(rebuild: true);
                    }
                  : null,
            ),
            errorLine(errors['$key.source']),
            const SizedBox(height: 12),
            Text('Mức tự tin của bạn (0–4) *', style: text.titleSmall),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (var v = 0; v <= 4; v++)
                  ChoiceChip(
                    label: Text('$v · ${confidenceLabels[v]}'),
                    selected: question.confidence == v,
                    onSelected: enabled
                        ? (_) {
                            question.confidence = v;
                            c.changed(rebuild: true);
                          }
                        : null,
                  ),
              ],
            ),
            errorLine(errors['$key.confidence']),
          ],
        ),
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    super.key,
    required this.label,
    required this.option,
    required this.error,
    required this.enabled,
    required this.canRemove,
    required this.onChanged,
    required this.onTextChanged,
    required this.onRemove,
  });
  final String label;
  final OptionDraft option;
  final String? error;
  final bool enabled;
  final bool canRemove;
  final VoidCallback onChanged;
  final VoidCallback onTextChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Checkbox(
            value: option.correct,
            semanticLabel: 'Đáp án $label đúng',
            onChanged: enabled
                ? (value) {
                    option.correct = value ?? false;
                    onChanged();
                  }
                : null,
          ),
        ),
        Expanded(
          child: TextFormField(
            initialValue: option.text,
            enabled: enabled,
            maxLines: 4,
            minLines: 1,
            decoration: InputDecoration(
              labelText: 'Đáp án $label',
              errorText: error,
            ),
            onChanged: (value) {
              option.text = value;
              onTextChanged();
            },
          ),
        ),
        IconButton(
          tooltip: 'Xóa đáp án $label',
          onPressed: enabled && canRemove ? onRemove : null,
          icon: const Icon(Icons.close),
        ),
      ],
    ),
  );
}

class _ImageThumb extends StatelessWidget {
  const _ImageThumb({required this.image, required this.onRemove});
  final DraftImage image;
  final VoidCallback? onRemove;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final missing = SizedBox(
      width: 80,
      height: 80,
      child: ColoredBox(
        color: scheme.surfaceContainerHighest,
        child: const Icon(Icons.broken_image_outlined),
      ),
    );
    final Widget picture = image.localPath != null
        ? Image.file(
            File(image.localPath!),
            width: 80,
            height: 80,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => missing,
          )
        : AppNetworkImage(url: image.remoteUrl, width: 80, height: 80);
    return Stack(
      children: [
        ClipRRect(borderRadius: BorderRadius.circular(8), child: picture),
        if (!image.uploaded)
          Positioned(
            left: 4,
            bottom: 4,
            child: Icon(
              Icons.cloud_upload_outlined,
              size: 18,
              color: scheme.onSurface,
              semanticLabel: 'Ảnh chưa tải lên',
            ),
          ),
        if (onRemove != null)
          Positioned(
            right: 0,
            top: 0,
            child: IconButton.filledTonal(
              visualDensity: VisualDensity.compact,
              iconSize: 16,
              tooltip: 'Xóa ảnh',
              onPressed: onRemove,
              icon: const Icon(Icons.close),
            ),
          ),
      ],
    );
  }
}
