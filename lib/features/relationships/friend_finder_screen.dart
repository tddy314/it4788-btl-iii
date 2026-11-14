import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/widgets/app_network_image.dart';
import '../../core/widgets/app_states.dart';
import '../profile/profile_models.dart';
import 'friend_finder_controller.dart';
import 'friend_finder_repository.dart';
import 'social_state.dart';
import 'social_widgets.dart';

abstract final class RelationshipRoutes {
  static const findFriends = '/friends/find';
}

class FriendFinderScreen extends StatefulWidget {
  const FriendFinderScreen({super.key, required this.changes});
  final SocialChanges changes;
  @override
  State<FriendFinderScreen> createState() => _FriendFinderScreenState();
}

class _FriendFinderScreenState extends State<FriendFinderScreen> {
  final _input = TextEditingController();
  FriendFinderController? _controller;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller ??= FriendFinderController(
      repository: FriendFinderRepository(
        api: AppScope.of(context).api,
        lease: widget.changes.lease(),
      ),
    );
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    unawaited(_controller!.refresh());
  }

  @override
  void dispose() {
    _controller?.dispose();
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Tìm bạn bè')),
    body: SafeArea(
      child: ListenableBuilder(
        listenable: _controller!,
        builder: (context, _) {
          final controller = _controller!;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        textInputAction: TextInputAction.search,
                        autocorrect: false,
                        onChanged: controller.setQuery,
                        onSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: 'Tên người dùng',
                          hintText: 'Nhập tên để tìm bạn',
                          suffixIcon: IconButton(
                            tooltip: 'Xóa từ khóa',
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _input.clear();
                              controller.setQuery('');
                            },
                          ),
                        ),
                      ),
                    ),
                    IconButton.filled(
                      tooltip: 'Tìm bạn bè',
                      icon: const Icon(Icons.search),
                      onPressed: controller.validation == null ? _submit : null,
                    ),
                  ],
                ),
              ),
              Expanded(child: _results(controller)),
            ],
          );
        },
      ),
    ),
  );

  Widget _results(FriendFinderController controller) {
    if (controller.validation != null) {
      return AppEmptyState(
        title: 'Tìm người để kết bạn',
        message: controller.validation,
        icon: Icons.person_search_outlined,
      );
    }
    if (controller.loading && controller.people.isEmpty) {
      return const AppLoadingState();
    }
    if (controller.failure != null && controller.people.isEmpty) {
      return AppErrorState(
        message: controller.failure!.message,
        onRetry: controller.refresh,
      );
    }
    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        itemCount: controller.people.length + 2,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (controller.loading) const LinearProgressIndicator(),
                if (controller.failure != null)
                  SocialNotice(
                    message: controller.failure!.message,
                    onRetry: controller.refresh,
                  ),
                if (!controller.loaded && !controller.loading)
                  const Text('Đang chờ tìm người…'),
                if (controller.loaded && controller.people.isEmpty)
                  const AppEmptyState(
                    title: 'Không tìm thấy người dùng',
                    message: 'Thử nhập tên khác.',
                    icon: Icons.person_search_outlined,
                  ),
              ],
            );
          }
          if (index == controller.people.length + 1) {
            return controller.hasNext
                ? OutlinedButton(
                    onPressed: controller.loading ? null : controller.loadMore,
                    child: const Text('Tải thêm'),
                  )
                : const SizedBox.shrink();
          }
          final person = controller.people[index - 1];
          return Card(
            child: ListTile(
              leading: AppAvatar(imageUrl: person.avatar, name: person.name),
              title: Text(
                person.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: person.subtitle == null
                  ? null
                  : Text(
                      person.subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pushNamed(
                context,
                ProfileRoutes.user,
                arguments: person.id,
              ),
            ),
          );
        },
      ),
    );
  }
}
