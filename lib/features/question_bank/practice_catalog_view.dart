import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/storage/cached_resource_controller.dart';
import 'paged_list_controller.dart';
import 'question_bank_repository.dart';
import 'question_bank_routes.dart';
import 'question_bank_widgets.dart';
import 'question_models.dart';

/// Kho bộ câu hỏi đã chốt để luyện tập, tìm theo tiêu đề/mã phiên và môn.
class PracticeCatalogView extends StatefulWidget {
  const PracticeCatalogView({super.key});
  @override
  State<PracticeCatalogView> createState() => _PracticeCatalogViewState();
}

class _PracticeCatalogViewState extends State<PracticeCatalogView>
    with AutomaticKeepAliveClientMixin {
  PagedListController<PracticeSetSummary>? _controller;
  late CachedResourceController<List<SubjectItem>> _subjects;
  late QuestionBankRepository _repository;
  final _search = TextEditingController();
  Timer? _debounce;
  String _query = '';
  int? _subjectId;

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final dependencies = AppScope.of(context);
    final userId = dependencies.session.tokens?.userId ?? '';
    _repository = QuestionBankRepository(dependencies.api);
    _subjects = CachedResourceController<List<SubjectItem>>(
      cache: dependencies.cache,
      userId: userId,
      resource: 'qb.subjects',
      fetch: () => _repository.subjects(),
      encode: (value) => [for (final s in value) s.toJson()],
      decode: (value) => [
        for (final s in qbList(value)) SubjectItem.fromJson(s),
      ],
    )..load();
    _controller = PagedListController<PracticeSetSummary>(
      fetch: _fetcher(),
      idOf: (item) => item.sessionId,
      cache: dependencies.cache,
      userId: userId,
      encode: (item) => item.toJson(),
      decode: PracticeSetSummary.fromJson,
    )..setResource(_resource());
    _controller!.refresh();
  }

  PageFetcher<PracticeSetSummary> _fetcher() {
    final query = _query, subject = _subjectId;
    return (after) => _repository.practiceCatalog(
      after: after,
      subjectId: subject,
      query: query,
    );
  }

  /// Chỉ cache trang đầu khi không lọc; kết quả tìm kiếm không lưu.
  String? _resource() =>
      _query.isEmpty && _subjectId == null ? 'qb.practice-catalog' : null;

  void _apply() => _controller!.reset(_fetcher(), resource: _resource());

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      final next = value.trim();
      if (next == _query || !mounted) return;
      _query = next;
      _apply();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _subjects.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        _filters(context),
        Expanded(child: _list()),
      ],
    );
  }

  Widget _list() {
    return QbPagedList<PracticeSetSummary>(
      controller: _controller!,
      emptyIcon: Icons.quiz_outlined,
      emptyTitle: _query.isEmpty && _subjectId == null
          ? 'Chưa có bộ câu hỏi để luyện tập'
          : 'Không tìm thấy bộ câu hỏi phù hợp',
      emptyMessage: _query.isEmpty && _subjectId == null
          ? 'Các bộ câu hỏi sẽ xuất hiện sau khi giảng viên chốt phiên đề xuất.'
          : 'Hãy thử từ khóa hoặc môn học khác.',
      itemBuilder: (context, item) => _PracticeCard(
        item: item,
        onTap: () => Navigator.of(context)
            .pushNamed(QuestionBankRoutes.practice, arguments: item.sessionId),
      ),
    );
  }

  Widget _filters(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _search,
          maxLength: 120,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Tìm theo tiêu đề hoặc mã phiên',
            prefixIcon: const Icon(Icons.search),
            counterText: '',
            suffixIcon: ListenableBuilder(
              listenable: _search,
              builder: (context, _) => _search.text.isEmpty
                  ? const SizedBox.shrink()
                  : IconButton(
                      tooltip: 'Xóa từ khóa',
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _search.clear();
                        _onSearch('');
                      },
                    ),
            ),
          ),
          onChanged: _onSearch,
          onSubmitted: (value) {
            _debounce?.cancel();
            final next = value.trim();
            if (next == _query) return;
            _query = next;
            _apply();
          },
        ),
        const SizedBox(height: 8),
        ListenableBuilder(
          listenable: _subjects,
          builder: (context, _) {
            final subjects = _subjects.data;
            if (subjects == null || subjects.isEmpty) {
              return const SizedBox.shrink();
            }
            final known = subjects.any((s) => s.id == _subjectId);
            return DropdownButtonFormField<int?>(
              initialValue: known ? _subjectId : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Môn học'),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('Tất cả môn học'),
                ),
                for (final subject in subjects)
                  DropdownMenuItem<int?>(
                    value: subject.id,
                    child: Text(subject.label, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (value) {
                if (value == _subjectId) return;
                setState(() => _subjectId = value);
                _apply();
              },
            );
          },
        ),
      ],
    ),
  );
}

class _PracticeCard extends StatelessWidget {
  const _PracticeCard({required this.item, required this.onTap});
  final PracticeSetSummary item;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: const Icon(Icons.quiz_outlined),
        title: Text(
          item.title.isEmpty ? 'Bộ câu hỏi không tên' : item.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          [
            if (item.subjectLabel.isNotEmpty) item.subjectLabel,
            if (item.questionCount != null) '${item.questionCount} câu hỏi',
            if (item.createdAt != null) qbFormatDate(item.createdAt),
          ].join(' · '),
          style: text.bodySmall,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
