import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/widgets/app_network_image.dart';
import '../../core/widgets/app_states.dart';
import '../relationships/social_repository.dart';
import '../relationships/social_state.dart';
import '../relationships/social_widgets.dart';
import 'profile_models.dart';
import 'profile_repository.dart';

/// Read-only summaries. Detail routes belong to posts/question_bank features.
class ProfileContentScreen extends StatefulWidget {
  const ProfileContentScreen({
    super.key,
    required this.userId,
    required this.changes,
    required this.sessions,
  });
  final String userId;
  final SocialChanges changes;
  final bool sessions;
  @override
  State<ProfileContentScreen> createState() => _ProfileContentScreenState();
}

class _ProfileContentScreenState extends State<ProfileContentScreen> {
  SocialRepository? _social;
  late SocialListController<ProfileContent> _list;
  int _revision = 0;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_social != null) return;
    final social = _social = SocialRepository(
      api: AppScope.of(context).api,
      lease: widget.changes.lease(),
    );
    final repository = ProfileRepository(social);
    _list = SocialListController(
      lease: social.lease,
      fetch: (after) => repository.content(
        widget.userId,
        sessions: widget.sessions,
        after: after,
      ),
      idOf: (item) => item.id,
    );
    _revision = widget.changes.revision;
    widget.changes.addListener(_changed);
    unawaited(_list.load());
  }

  void _changed() {
    if (_revision == widget.changes.revision) return;
    _revision = widget.changes.revision;
    _list.clear(
      keepItems:
          !widget.changes.lastMutationConfirmed &&
          widget.changes.lastBlockedUserId == null,
    );
    unawaited(_list.load());
  }

  @override
  void dispose() {
    widget.changes.removeListener(_changed);
    _social?.dispose();
    _list.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.sessions ? 'Phiên đề xuất' : 'Bài viết')),
    body: SafeArea(
      child: ListenableBuilder(
        listenable: _list,
        builder: (context, _) {
          if (_list.loading && _list.items.isEmpty) {
            return const AppLoadingState();
          }
          if (_list.failure != null && _list.items.isEmpty) {
            return AppErrorState(
              message: _list.failure!.message,
              onRetry: () => _list.load(),
            );
          }
          return RefreshIndicator(
            onRefresh: () => _list.load(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                if (_list.failure != null)
                  SocialNotice(
                    message: _list.failure!.message,
                    onRetry: () => _list.load(),
                  ),
                if (_list.loading) const LinearProgressIndicator(),
                if (_list.items.isEmpty)
                  const AppEmptyState(title: 'Chưa có nội dung'),
                for (final item in _list.items)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (item.subtitle != null) Text(item.subtitle!),
                          if (item.status != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(item.status!),
                            ),
                          if (item.createdAt != null)
                            Text(
                              MaterialLocalizations.of(context)
                                  .formatMediumDate(item.createdAt!.toLocal()),
                            ),
                          if (item.content.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(item.content),
                            ),
                          if (item.image != null)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: AppNetworkImage(
                                url: item.image,
                                height: 200,
                                width: double.infinity,
                              ),
                            ),
                          if (item.video) const Text('Video đính kèm'),
                        ],
                      ),
                    ),
                  ),
                if (_list.hasNext)
                  OutlinedButton(
                    onPressed: _list.loading
                        ? null
                        : () => _list.load(more: true),
                    child: const Text('Tải thêm'),
                  ),
              ],
            ),
          );
        },
      ),
    ),
  );
}
