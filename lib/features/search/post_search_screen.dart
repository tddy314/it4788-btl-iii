import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/widgets/app_network_image.dart';
import '../../core/widgets/app_states.dart';
import '../../core/widgets/app_text_field.dart';
import '../posts/post_models.dart';
import '../posts/post_routes.dart';
import 'post_search.dart';

class PostSearchScreen extends StatefulWidget {
  const PostSearchScreen({super.key});
  @override
  State<PostSearchScreen> createState() => _PostSearchScreenState();
}

class _PostSearchScreenState extends State<PostSearchScreen> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  PostSearchController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final deps = AppScope.of(context);
    _controller = PostSearchController(
      repository: PostSearchRepository(deps.api),
      session: deps.session,
    );
    _text.addListener(() => _controller!.updateQuery(_text.text));
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 200 && _controller!.failure == null) {
        unawaited(_controller!.more());
      }
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller!;
    return Scaffold(
      appBar: AppBar(title: const Text('Tìm bài viết')),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: AppTextField(
                      label: 'Từ khóa bài viết',
                      controller: _text,
                      textInputAction: TextInputAction.search,
                      onFieldSubmitted: (_) => controller.search(),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Tìm kiếm',
                    onPressed: controller.loading || controller.query.isEmpty
                        ? null
                        : controller.search,
                    icon: const Icon(Icons.search),
                  ),
                  IconButton(
                    tooltip: 'Xóa từ khóa',
                    onPressed: _text.clear,
                    icon: const Icon(Icons.clear),
                  ),
                ],
              ),
            ),
            if (controller.loading) const LinearProgressIndicator(),
            if (controller.failure != null && controller.items.isNotEmpty)
              MaterialBanner(
                content: Text(controller.failure!.message),
                actions: [
                  TextButton(
                    onPressed: controller.loading ? null : controller.search,
                    child: const Text('Thử lại'),
                  ),
                ],
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: controller.search,
                child: ListView.builder(
                  controller: _scroll,
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: controller.items.isEmpty
                      ? 1
                      : controller.items.length + (controller.hasNext ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (controller.items.isEmpty) {
                      if (controller.loading) {
                        return const SizedBox(height: 200);
                      }
                      if (controller.failure != null) {
                        return SizedBox(
                          height: 280,
                          child: AppErrorState(
                            message: controller.failure!.message,
                            onRetry: controller.search,
                          ),
                        );
                      }
                      return SizedBox(
                        height: 280,
                        child: AppEmptyState(
                          icon: Icons.search,
                          title: controller.searched
                              ? 'Không tìm thấy bài viết'
                              : 'Tìm bài viết',
                          message: controller.searched
                              ? 'Hãy thử từ khóa khác.'
                              : 'Nhập từ khóa để tìm nội dung trong bài viết.',
                        ),
                      );
                    }
                    if (i == controller.items.length) {
                      return TextButton(
                        onPressed: controller.loadingMore
                            ? null
                            : controller.more,
                        child: Text(
                          controller.loadingMore
                              ? 'Đang tải…'
                              : 'Tải thêm kết quả',
                        ),
                      );
                    }
                    final result = controller.items[i];
                    return ListTile(
                      leading: AppAvatar(
                        name: result.author.name,
                        imageUrl: result.author.avatar,
                      ),
                      title: Text(
                        result.author.name.isEmpty
                            ? 'Người dùng'
                            : result.author.name,
                      ),
                      subtitle: Text(
                        '${result.content}\n${postTime(result.createdAt)}',
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                      ),
                      isThreeLine: true,
                      onTap: () => Navigator.of(context).pushNamed(
                        PostRoutes.detail,
                        arguments: {'postId': result.id},
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
