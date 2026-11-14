import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import 'paged_list_controller.dart';
import 'question_bank_repository.dart';
import 'question_bank_routes.dart';
import 'question_bank_widgets.dart';
import 'question_models.dart';

/// Danh sách phiên đề xuất của người dùng, lọc theo trạng thái.
class MySubmissionsView extends StatefulWidget {
  const MySubmissionsView({super.key});
  @override
  State<MySubmissionsView> createState() => _MySubmissionsViewState();
}

class _MySubmissionsViewState extends State<MySubmissionsView>
    with AutomaticKeepAliveClientMixin {
  PagedListController<SubmissionSummary>? _controller;
  late QuestionBankRepository _repository;
  SessionStatus? _status;

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final dependencies = AppScope.of(context);
    _repository = QuestionBankRepository(dependencies.api);
    _controller = PagedListController<SubmissionSummary>(
      fetch: _fetcher(null),
      idOf: (item) => item.sessionId,
      cache: dependencies.cache,
      userId: dependencies.session.tokens?.userId,
      encode: (item) => item.toJson(),
      decode: SubmissionSummary.fromJson,
    )..setResource(_resource(null));
    _controller!.refresh();
  }

  PageFetcher<SubmissionSummary> _fetcher(SessionStatus? status) =>
      (after) => _repository.mySubmissions(after: after, status: status);

  String _resource(SessionStatus? status) =>
      'qb.my-submissions.${status?.wire ?? 'ALL'}';

  void _filter(SessionStatus? status) {
    if (status == _status) return;
    setState(() => _status = status);
    _controller!.reset(_fetcher(status), resource: _resource(status));
  }

  Future<void> _open(String route, [Object? arguments]) async {
    final changed = await Navigator.of(context)
        .pushNamed(route, arguments: arguments);
    if (changed == true && mounted) await _controller!.refresh();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final controller = _controller!;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'qb-propose',
        onPressed: () => _open(QuestionBankRoutes.compose),
        icon: const Icon(Icons.add),
        label: const Text('Đề xuất câu hỏi'),
      ),
      body: Column(
        children: [
          _filters(),
          Expanded(child: _list(controller)),
        ],
      ),
    );
  }

  Widget _list(PagedListController<SubmissionSummary> controller) {
    return QbPagedList<SubmissionSummary>(
      controller: controller,
      bottomPadding: 96,
      emptyIcon: Icons.post_add_outlined,
      emptyTitle: _status == null
          ? 'Bạn chưa có đề xuất nào'
          : 'Không có đề xuất ${_status!.label.toLowerCase()}',
      emptyMessage: _status == null
          ? 'Bấm "Đề xuất câu hỏi" để gửi bộ câu hỏi đầu tiên cho lớp học phần của bạn.'
          : null,
      itemBuilder: (context, item) => _SubmissionCard(
        item: item,
        onTap: () => _open(QuestionBankRoutes.submission, item.sessionId),
      ),
    );
  }

  Widget _filters() => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
    child: Row(
      children: [
        for (final status in <SessionStatus?>[null, ...SessionStatus.filters])
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(status?.label ?? 'Tất cả'),
              selected: _status == status,
              onSelected: (_) => _filter(status),
            ),
          ),
      ],
    ),
  );
}

class _SubmissionCard extends StatelessWidget {
  const _SubmissionCard({required this.item, required this.onTap});
  final SubmissionSummary item;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final meta = [
      if (item.subjectLabel.isNotEmpty) item.subjectLabel,
      if (item.classCode.isNotEmpty) 'Lớp ${item.classCode}',
    ].join(' · ');
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
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
                      item.title.isEmpty ? 'Bộ câu hỏi không tên' : item.title,
                      style: text.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  QbStatusChip.session(item.status),
                ],
              ),
              if (meta.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  meta,
                  style: text.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 8),
              Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  if (item.questionCount != null)
                    Text(
                      '${item.questionCount} câu hỏi',
                      style: text.bodySmall,
                    ),
                  if (item.approvedCount != null)
                    Text(
                      'Được chọn ${item.approvedCount}'
                      '${item.questionCount == null ? '' : '/${item.questionCount}'}',
                      style: text.bodySmall,
                    ),
                  if (item.createdAt != null)
                    Text(qbFormatDate(item.createdAt), style: text.bodySmall),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
