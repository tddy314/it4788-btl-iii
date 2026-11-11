import 'package:flutter/material.dart';

import '../../core/errors/app_failure.dart';
import '../../core/widgets/app_network_image.dart';
import '../../core/widgets/app_states.dart';
import 'paged_list_controller.dart';
import 'question_models.dart';

/// Chip trạng thái phiên/câu hỏi, chỉ dùng màu từ theme.
class QbStatusChip extends StatelessWidget {
  const QbStatusChip({super.key, required this.label, required this.tone});
  final String label;
  final QbTone tone;

  factory QbStatusChip.session(SessionStatus status) => QbStatusChip(
    label: status.label,
    tone: switch (status) {
      SessionStatus.pending => QbTone.neutral,
      SessionStatus.reviewing => QbTone.info,
      SessionStatus.resolved => QbTone.positive,
      SessionStatus.unknown => QbTone.neutral,
    },
  );

  factory QbStatusChip.question(QuestionReviewStatus status) => QbStatusChip(
    label: status.label,
    tone: switch (status) {
      QuestionReviewStatus.approved => QbTone.positive,
      QuestionReviewStatus.rejected => QbTone.negative,
      _ => QbTone.neutral,
    },
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (tone) {
      QbTone.neutral => (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
      ),
      QbTone.info => (scheme.secondaryContainer, scheme.onSecondaryContainer),
      QbTone.positive => (scheme.primaryContainer, scheme.onPrimaryContainer),
      QbTone.negative => (scheme.errorContainer, scheme.onErrorContainer),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: foreground),
      ),
    );
  }
}

enum QbTone { neutral, info, positive, negative }

/// Thông báo nhỏ trên đầu danh sách: lỗi refresh hoặc dữ liệu đã lưu.
class QbNotice extends StatelessWidget {
  const QbNotice({
    super.key,
    required this.message,
    this.onRetry,
    this.isError = true,
  });
  final String message;
  final VoidCallback? onRetry;
  final bool isError;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isError
              ? scheme.errorContainer
              : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.history,
              size: 20,
              color: isError
                  ? scheme.onErrorContainer
                  : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: isError
                      ? scheme.onErrorContainer
                      : scheme.onSurfaceVariant,
                ),
              ),
            ),
            if (onRetry != null)
              TextButton(onPressed: onRetry, child: const Text('Thử lại')),
          ],
        ),
      ),
    );
  }
}

String savedAtText(DateTime? savedAt) => savedAt == null
    ? 'Đang hiển thị dữ liệu đã lưu trên máy.'
    : 'Đang hiển thị dữ liệu đã lưu lúc ${qbFormatDate(savedAt)}.';

/// Danh sách phân trang: kéo xuống để làm mới, cuộn gần cuối để tải thêm.
/// Không tự tải thêm lại sau khi lỗi; người dùng bấm "Thử lại".
class QbPagedList<T> extends StatelessWidget {
  const QbPagedList({
    super.key,
    required this.controller,
    required this.itemBuilder,
    this.header,
    this.emptyTitle = 'Chưa có nội dung',
    this.emptyMessage,
    this.emptyIcon = Icons.inbox_outlined,
    this.bottomPadding = 24,
  });
  final PagedListController<T> controller;
  final Widget Function(BuildContext, T) itemBuilder;
  final Widget? header;
  final String emptyTitle;
  final String? emptyMessage;
  final IconData emptyIcon;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final items = controller.items;
      final failure = controller.failure;
      final top = <Widget>[
        ?header,
        if (controller.isRefreshing && items.isNotEmpty)
          const LinearProgressIndicator(),
        if (failure != null && items.isNotEmpty)
          QbNotice(
            message: failure.message,
            onRetry: controller.isRefreshing ? null : controller.refresh,
          ),
        if (controller.isFromCache && failure == null && items.isNotEmpty)
          QbNotice(message: savedAtText(controller.savedAt), isError: false),
      ];
      Widget body;
      if (items.isEmpty) {
        final Widget state;
        if (controller.isRefreshing || !controller.loadedOnce) {
          state = const Padding(
            padding: EdgeInsets.only(top: 48),
            child: AppLoadingState(),
          );
        } else if (failure != null) {
          state = AppErrorState(
            message: failure.message,
            onRetry: controller.refresh,
          );
        } else {
          state = AppEmptyState(
            title: emptyTitle,
            message: emptyMessage,
            icon: emptyIcon,
          );
        }
        body = ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(bottom: bottomPadding),
          children: [...top, state],
        );
      } else {
        body = NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.metrics.extentAfter < 400 &&
                controller.loadMoreFailure == null) {
              controller.loadMore();
            }
            return false;
          },
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.only(bottom: bottomPadding),
            itemCount: top.length + items.length + 1,
            itemBuilder: (context, index) {
              if (index < top.length) return top[index];
              final i = index - top.length;
              if (i < items.length) return itemBuilder(context, items[i]);
              return _footer(context);
            },
          ),
        );
      }
      return RefreshIndicator(onRefresh: controller.refresh, child: body);
    },
  );

  Widget _footer(BuildContext context) {
    if (controller.isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    final failure = controller.loadMoreFailure;
    if (failure != null) {
      return QbNotice(
        message: failure.message,
        onRetry: () {
          controller.loadMoreFailure = null;
          controller.loadMore();
        },
      );
    }
    if (controller.isFromCache && controller.items.isNotEmpty) {
      return const SizedBox(height: 8);
    }
    if (!controller.hasNext && controller.items.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Đã hiển thị tất cả.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }
    return const SizedBox(height: 8);
  }
}

/// Lưới ảnh câu hỏi; ảnh chưa tải được hiển thị fallback của AppNetworkImage.
class QbImageGrid extends StatelessWidget {
  const QbImageGrid({super.key, required this.urls});
  final List<String> urls;
  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < urls.length; i++)
            GestureDetector(
              onTap: () => showDialog<void>(
                context: context,
                builder: (context) => Dialog(
                  child: InteractiveViewer(
                    child: AppNetworkImage(
                      url: urls[i],
                      fit: BoxFit.contain,
                      semanticLabel: 'Ảnh minh họa ${i + 1}',
                    ),
                  ),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AppNetworkImage(
                  url: urls[i],
                  width: 96,
                  height: 96,
                  semanticLabel: 'Ảnh minh họa ${i + 1}',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Đọc AppFailure an toàn từ lỗi bất kỳ để hiển thị.
String failureText(Object error) => error is AppFailure
    ? error.message
    : 'Không thể hoàn tất thao tác. Vui lòng thử lại.';
