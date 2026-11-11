import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/widgets/app_network_image.dart';
import '../../core/widgets/app_states.dart';
import '../relationships/relationships_screen.dart';
import '../relationships/social_models.dart';
import '../relationships/social_repository.dart';
import '../relationships/social_state.dart';
import '../relationships/social_widgets.dart';
import '../settings/settings_screen.dart';
import 'edit_profile_screen.dart';
import 'profile_content_screen.dart';
import 'profile_controller.dart';
import 'profile_models.dart';
import 'profile_repository.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.changes,
    this.userId,
    this.embedded = false,
  });
  final SocialChanges changes;
  final String? userId;
  final bool embedded;
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  SocialRepository? _social;
  late ProfileController _controller;
  int _revision = 0;
  String? _message;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_social != null) return;
    final dependencies = AppScope.of(context);
    final social = _social = SocialRepository(
      api: dependencies.api,
      lease: widget.changes.lease(),
    );
    _controller = ProfileController(
      repository: ProfileRepository(social),
      cache: dependencies.cache,
      id: widget.userId ?? social.lease.userId,
    );
    _revision = widget.changes.revision;
    widget.changes.addListener(_changed);
    unawaited(_controller.load());
  }

  void _changed() {
    if (!mounted || !_social!.lease.active) return;
    if (_revision != widget.changes.revision) {
      _revision = widget.changes.revision;
      _controller.invalidate(
        hide: widget.changes.lastBlockedUserId == _controller.id,
      );
      unawaited(_controller.load());
    }
    setState(() {});
  }

  Future<void> _act(SocialAction action) async {
    if (widget.changes.busy || !_controller.writable) return;
    if ([SocialAction.block, SocialAction.unfriend].contains(action)) {
      final confirmed = await confirmSocialAction(
        context,
        action.label,
        action == SocialAction.block
            ? 'Chặn người dùng này sẽ hủy quan hệ bạn bè và theo dõi hai chiều. '
                  'Bỏ chặn không tự khôi phục các quan hệ đó.'
            : 'Bạn có muốn hủy kết bạn với người này?',
      );
      if (!confirmed || !mounted) return;
    }
    setState(() => _message = null);
    try {
      final done = await widget.changes.mutate(
        () => _social!.change(action, _controller.id),
        blockedUserId: action == SocialAction.block ? _controller.id : null,
      );
      if (mounted && _social!.lease.active && done) {
        setState(() => _message = 'Đã đối soát và cập nhật quan hệ.');
      }
    } catch (error) {
      if (mounted && _social!.lease.active) {
        setState(() => _message = socialWriteError(error));
      }
    }
  }

  Future<void> _edit() async {
    if (!_controller.writable || widget.changes.busy) return;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EditProfileScreen(
          profile: _controller.profile!,
          changes: widget.changes,
        ),
      ),
    );
    if (mounted && changed == true) {
      setState(() => _message = 'Đã lưu hồ sơ.');
    }
  }

  void _people(RelationshipList kind) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) =>
          RelationshipsScreen(changes: widget.changes, initial: kind),
    ),
  );

  @override
  void dispose() {
    widget.changes.removeListener(_changed);
    _controller.dispose();
    _social?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final body = ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final profile = _controller.profile;
        return Column(
          children: [
            if (_controller.own)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: const Icon(Icons.settings_outlined),
                  label: const Text('Cài đặt'),
                  onPressed: () =>
                      Navigator.pushNamed(context, SettingsRoutes.settings),
                ),
              ),
            Expanded(
              child: profile == null
                  ? _controller.loading
                        ? const AppLoadingState()
                        : AppErrorState(
                            message:
                                _controller.failure?.message ??
                                'Không thể tải hồ sơ.',
                            onRetry: () => _controller.load(),
                          )
                  : RefreshIndicator(
                      onRefresh: () => _controller.load(),
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          if (_controller.loading)
                            const LinearProgressIndicator(),
                          if (_message != null)
                            SocialNotice(message: _message!),
                          if (_controller.fromCache ||
                              _controller.failure != null)
                            SocialNotice(
                              message:
                                  _controller.failure?.message ??
                                  'Đang hiển thị thông tin đã lưu trên máy.',
                              onRetry: _controller.loading
                                  ? null
                                  : () => _controller.load(),
                            ),
                          if (_controller.statsFailure != null)
                            SocialNotice(
                              message:
                                  'Chưa tải được trạng thái quan hệ. ${_controller.statsFailure!.message}',
                              onRetry: _controller.loading
                                  ? null
                                  : () => _controller.load(),
                            ),
                          _header(profile),
                          const SizedBox(height: 16),
                          _counts(profile),
                          const SizedBox(height: 16),
                          if (_controller.own)
                            FilledButton.icon(
                              onPressed:
                                  _controller.writable && !widget.changes.busy
                                  ? _edit
                                  : null,
                              icon: const Icon(Icons.edit_outlined),
                              label: const Text('Chỉnh sửa hồ sơ'),
                            )
                          else
                            _actions(),
                          const SizedBox(height: 16),
                          _information(profile),
                          const SizedBox(height: 16),
                          Card(
                            child: Column(
                              children: [
                                for (final sessions in [false, true])
                                  ListTile(
                                    leading: Icon(
                                      sessions
                                          ? Icons.menu_book_outlined
                                          : Icons.article_outlined,
                                    ),
                                    title: Text(
                                      sessions ? 'Phiên đề xuất' : 'Bài viết',
                                    ),
                                    trailing: const Icon(Icons.chevron_right),
                                    enabled:
                                        !_controller.fromCache &&
                                        _controller.failure == null,
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute<void>(
                                        builder: (_) => ProfileContentScreen(
                                          userId: profile.id,
                                          changes: widget.changes,
                                          sessions: sessions,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (_controller.own) ...[
                            const SizedBox(height: 8),
                            ListTile(
                              leading: const Icon(Icons.block_outlined),
                              title: const Text('Danh sách chặn'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => _people(RelationshipList.blocked),
                            ),
                          ],
                        ],
                      ),
                    ),
            ),
          ],
        );
      },
    );
    return widget.embedded
        ? body
        : Scaffold(
            appBar: AppBar(title: const Text('Hồ sơ')),
            body: SafeArea(child: body),
          );
  }

  Widget _header(UserProfile profile) => Card(
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (profile.text('cover_url') != null)
          AppNetworkImage(
            url: profile.text('cover_url'),
            height: 144,
            width: double.infinity,
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppAvatar(
                imageUrl: profile.text('avatar_url'),
                name: profile.name,
                size: 80,
              ),
              const SizedBox(height: 12),
              Text(
                profile.name,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text(
                profile.roleLabel,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if ((profile.text('bio') ?? '').isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(profile.text('bio')!),
              ],
            ],
          ),
        ),
      ],
    ),
  );

  Widget _counts(UserProfile profile) {
    final stats = _controller.stats;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final entry in [
          (
            RelationshipList.friends,
            stats?.friends ?? profile.count('friends_count'),
          ),
          (
            RelationshipList.followers,
            stats?.followers ?? profile.count('followers_count'),
          ),
          (
            RelationshipList.following,
            stats?.followingCount ?? profile.count('following_count'),
          ),
        ])
          ActionChip(
            label: Text('${entry.$2 ?? '—'} ${entry.$1.label.toLowerCase()}'),
            onPressed: _controller.own ? () => _people(entry.$1) : null,
          ),
      ],
    );
  }

  Widget _information(UserProfile profile) {
    final values = <String, String?>{
      'Khoa / trường': profile.text('school_faculty'),
      'Chuyên ngành': profile.text('major'),
      'Lớp': profile.text('class_name'),
      if (_controller.own) ...{
        'Email': profile.text('email'),
        'Mã sinh viên / giảng viên': profile.text('student_lecturer_code'),
        'Ngày sinh': profile.text('date_of_birth'),
        'Múi giờ': profile.text('timezone'),
      },
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Giới thiệu', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final entry in values.entries)
              if (entry.value != null && entry.value!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text('${entry.key}: ${entry.value}'),
                ),
            if (values.values.every((value) => value == null || value.isEmpty))
              const Text('Chưa có thông tin giới thiệu.'),
          ],
        ),
      ),
    );
  }

  Widget _actions() {
    final stats = _controller.stats;
    final enabled =
        _controller.writable &&
        stats != null &&
        stats.blocked == false &&
        !widget.changes.busy;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (stats?.isFriend == true)
          OutlinedButton.icon(
            onPressed: enabled ? () => _act(SocialAction.unfriend) : null,
            icon: const Icon(Icons.people_outline),
            label: const Text('Hủy kết bạn'),
          )
        else if (stats?.requestStatus == 'PENDING')
          OutlinedButton(
            onPressed: () => _people(RelationshipList.received),
            child: const Text('Kiểm tra lời mời kết bạn'),
          )
        else
          FilledButton.icon(
            onPressed: enabled ? () => _act(SocialAction.request) : null,
            icon: const Icon(Icons.person_add_outlined),
            label: const Text('Kết bạn'),
          ),
        OutlinedButton(
          onPressed: enabled && stats.isFollowing != null
              ? () => _act(
                  stats.isFollowing!
                      ? SocialAction.unfollow
                      : SocialAction.follow,
                )
              : null,
          child: Text(stats?.isFollowing == true ? 'Bỏ theo dõi' : 'Theo dõi'),
        ),
        OutlinedButton.icon(
          onPressed: enabled ? () => _act(SocialAction.block) : null,
          icon: const Icon(Icons.block),
          label: const Text('Chặn'),
        ),
      ],
    );
  }
}
