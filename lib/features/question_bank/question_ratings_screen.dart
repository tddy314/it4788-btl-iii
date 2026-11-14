import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/widgets/app_network_image.dart';
import 'paged_list_controller.dart';
import 'question_bank_repository.dart';
import 'question_bank_widgets.dart';
import 'question_models.dart';

/// Danh sách đánh giá của một câu hỏi (thang 0–4), không cache.
class QuestionRatingsScreen extends StatefulWidget {
  const QuestionRatingsScreen({super.key, required this.questionId});
  final int questionId;
  @override
  State<QuestionRatingsScreen> createState() => _QuestionRatingsScreenState();
}

class _QuestionRatingsScreenState extends State<QuestionRatingsScreen> {
  PagedListController<RatingItem>? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final repository = QuestionBankRepository(AppScope.of(context).api);
    _controller = PagedListController<RatingItem>(
      fetch: (after) => repository.ratings(widget.questionId, after: after),
      idOf: (item) =>
          '${item.userId}-${item.createdAt?.toIso8601String()}-${item.comment}',
    )..refresh();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Đánh giá câu hỏi')),
    body: SafeArea(
      child: QbPagedList<RatingItem>(
        controller: _controller!,
        emptyIcon: Icons.reviews_outlined,
        emptyTitle: 'Chưa có đánh giá nào',
        itemBuilder: (context, item) {
          final text = Theme.of(context).textTheme;
          final rating = item.rating;
          return Card(
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: ListTile(
              leading: AppAvatar(name: item.reviewerName, size: 40),
              title: Text(
                item.reviewerName.isEmpty
                    ? 'Người dùng SQB'
                    : item.reviewerName,
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    [
                      if (rating != null) 'Đánh giá ${_score(rating)}/4',
                      if (item.createdAt != null) qbFormatDate(item.createdAt),
                    ].join(' · '),
                    style: text.bodySmall,
                  ),
                  if (item.comment.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(item.comment),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    ),
  );

  static String _score(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1);
}
