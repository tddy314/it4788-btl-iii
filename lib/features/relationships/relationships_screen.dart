import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/widgets/app_network_image.dart';
import '../../core/widgets/app_states.dart';
import '../profile/profile_models.dart';
import 'friend_finder_screen.dart';
import 'social_models.dart';
import 'social_repository.dart';
import 'social_state.dart';
import 'social_widgets.dart';

class RelationshipsScreen extends StatefulWidget {
  const RelationshipsScreen({
    super.key,
    required this.changes,
    this.initial = RelationshipList.friends,
    this.embedded = false,
  });
  final SocialChanges changes;
  final RelationshipList initial;
  final bool embedded;
  @override
  State<RelationshipsScreen> createState() => _RelationshipsScreenState();
}

class _RelationshipsScreenState extends State<RelationshipsScreen> {
  late SocialRepository _repository;
  final _lists = <RelationshipList, SocialListController<SocialPerson>>{};
  late RelationshipList _selected;
  bool _initialized = false;
  int _revision = 0;
  String? _message;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _repository = SocialRepository(
      api: AppScope.of(context).api,
      lease: widget.changes.lease(),
    );
    _revision = widget.changes.revision;
    widget.changes.addListener(_changed);
    _list(_selected);
  }

  SocialListController<SocialPerson> _list(RelationshipList kind) =>
      _lists.putIfAbsent(kind, () {
        final controller = SocialListController<SocialPerson>(
          lease: _repository.lease,
          fetch: (after) => _repository.people(kind, after: after),
          idOf: (person) => person.id,
        );
        unawaited(controller.load());
        return controller;
      });

  void _changed() {
    if (!mounted || !_repository.lease.active) return;
    if (_revision != widget.changes.revision) {
      _revision = widget.changes.revision;
      // Clear membership immediately after a mutation (especially block), then
      // reload only the visible list. Other tabs are invalidated lazily.
      for (final entry in _lists.entries) {
        entry.value.clear(
          keepItems:
              !widget.changes.lastMutationConfirmed &&
              widget.changes.lastBlockedUserId == null,
        );
      }
      unawaited(_list(_selected).load());
    }
    setState(() {});
  }

  Future<void> _act(SocialAction action, SocialPerson person) async {
    if (widget.changes.busy) return;
    if ([SocialAction.unfriend, SocialAction.unblock].contains(action)) {
      final yes = await confirmSocialAction(
        context,
        action.label,
        action == SocialAction.unblock
            ? 'Bỏ chặn ${person.name}? Quan hệ bạn bè và theo dõi cũ sẽ không tự khôi phục.'
            : 'Hủy kết bạn với ${person.name}?',
      );
      if (!yes || !mounted) return;
    }
    setState(() => _message = null);
    try {
      final done = await widget.changes.mutate(
        () => _repository.change(action, person.id),
      );
      if (mounted && _repository.lease.active && done) {
        setState(() => _message = 'Đã đối soát và cập nhật quan hệ.');
      }
    } catch (error) {
      if (mounted && _repository.lease.active) {
        setState(() => _message = socialWriteError(error));
      }
    }
  }

  @override
  void dispose() {
    if (_initialized) {
      widget.changes.removeListener(_changed);
      _repository.dispose();
      for (final list in _lists.values) {
        list.dispose();
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = _list(_selected);
    final body = Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextButton.icon(
              icon: const Icon(Icons.search),
              label: const Text('Tìm bạn bè'),
              onPressed: () =>
                  Navigator.pushNamed(context, RelationshipRoutes.findFriends),
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              for (final kind in RelationshipList.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(kind.label),
                    selected: _selected == kind,
                    onSelected: (_) => setState(() {
                      _selected = kind;
                      _message = null;
                      final next = _list(kind);
                      if (!next.loaded) unawaited(next.load());
                    }),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListenableBuilder(
            listenable: list,
            builder: (context, _) {
              if (list.items.isEmpty && list.loading) {
                return const AppLoadingState();
              }
              if (list.items.isEmpty && list.failure != null) {
                return AppErrorState(
                  message: list.failure!.message,
                  onRetry: () => list.load(),
                );
              }
              return RefreshIndicator(
                onRefresh: () => list.load(),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    if (_message != null) SocialNotice(message: _message!),
                    if (list.failure != null)
                      SocialNotice(
                        message: list.failure!.message,
                        onRetry: () => list.load(),
                      ),
                    if (list.loading) const LinearProgressIndicator(),
                    if (_selected == RelationshipList.sent)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Text('Lời mời đang chờ người nhận phản hồi.'),
                      ),
                    if (list.items.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 48),
                        child: AppEmptyState(
                          title: 'Danh sách trống',
                          message: 'Kéo xuống để tải lại.',
                          icon: Icons.people_outline,
                        ),
                      ),
                    for (final person in list.items) _person(person, list),
                    if (list.hasNext)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: OutlinedButton(
                          onPressed: list.loading
                              ? null
                              : () => list.load(more: true),
                          child: const Text('Tải thêm'),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
    return widget.embedded
        ? body
        : Scaffold(
            appBar: AppBar(title: Text(widget.initial.label)),
            body: SafeArea(child: body),
          );
  }

  Widget _person(SocialPerson person, SocialListController<SocialPerson> list) {
    final enabled =
        !widget.changes.busy && !list.loading && list.failure == null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: AppAvatar(imageUrl: person.avatar, name: person.name),
              title: Text(person.name),
              subtitle: person.subtitle == null ? null : Text(person.subtitle!),
              trailing: _selected == RelationshipList.blocked
                  ? null
                  : const Icon(Icons.chevron_right),
              onTap: _selected == RelationshipList.blocked
                  ? null
                  : () async {
                      await Navigator.pushNamed(
                        context,
                        ProfileRoutes.user,
                        arguments: person.id,
                      );
                      if (mounted && !list.loaded) unawaited(list.load());
                    },
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (_selected == RelationshipList.received) ...[
                  FilledButton(
                    onPressed: enabled
                        ? () => _act(SocialAction.accept, person)
                        : null,
                    child: const Text('Chấp nhận'),
                  ),
                  OutlinedButton(
                    onPressed: enabled
                        ? () => _act(SocialAction.decline, person)
                        : null,
                    child: const Text('Từ chối'),
                  ),
                ],
                if (_selected == RelationshipList.friends)
                  OutlinedButton(
                    onPressed: enabled
                        ? () => _act(SocialAction.unfriend, person)
                        : null,
                    child: const Text('Hủy kết bạn'),
                  ),
                if (_selected == RelationshipList.following)
                  OutlinedButton(
                    onPressed: enabled
                        ? () => _act(SocialAction.unfollow, person)
                        : null,
                    child: const Text('Bỏ theo dõi'),
                  ),
                if (_selected == RelationshipList.blocked)
                  OutlinedButton(
                    onPressed: enabled
                        ? () => _act(SocialAction.unblock, person)
                        : null,
                    child: const Text('Bỏ chặn'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
