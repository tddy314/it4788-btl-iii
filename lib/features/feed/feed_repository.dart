import 'package:dio/dio.dart';

import '../../core/network/api_client.dart';
import '../../core/errors/app_failure.dart';
import '../posts/post_models.dart';

class FeedItem {
  const FeedItem({
    required this.id,
    required this.targetId,
    required this.targetType,
    required this.action,
    required this.actor,
    required this.title,
    this.createdAt,
    this.post,
  });
  final int id, targetId;
  final String targetType, action, title;
  final PostAuthor actor;
  final DateTime? createdAt;
  final Post? post;
  factory FeedItem.fromJson(Object? value) =>
      FeedItem._decode(value, saved: true);
  factory FeedItem.fromEvent(Object? value) =>
      FeedItem._decode(value, saved: false);
  factory FeedItem._decode(Object? value, {required bool saved}) {
    final json = object(value);
    final content = json['content'] is Map<String, dynamic>
        ? object(json['content'])
        : <String, dynamic>{};
    final target = textValue(json['target_type']);
    final id = identifier(json['target_id']);
    final actor = PostAuthor.fromJson(json['actor']);
    final snapshot = saved && target == 'POST' ? Post.fromJson(content) : null;
    if (snapshot != null && snapshot.id != id) throw AppFailure.invalidData;
    return FeedItem(
      id: identifier(json['feed_id']),
      targetId: id,
      targetType: target,
      action: textValue(json['action_type']),
      actor: actor,
      title: textValue(content['title']).isNotEmpty
          ? textValue(content['title'])
          : textValue(content['badge_name']),
      createdAt: DateTime.tryParse(textValue(json['created_at'])),
      post: snapshot,
    );
  }
  // Keep only display fields; never persist arbitrary academic payloads.
  Map<String, dynamic> toJson() => {
    'feed_id': id,
    'target_id': targetId,
    'target_type': targetType,
    'action_type': action,
    'actor': actor.toJson(),
    'content': post?.toJson() ?? {'title': title},
    'created_at': createdAt?.toIso8601String(),
  };
  FeedItem withPost(Post value) => FeedItem(
    id: id,
    targetId: targetId,
    targetType: targetType,
    action: action,
    actor: value.author,
    title: title,
    createdAt: createdAt,
    post: value,
  );
}

class FeedRepository {
  FeedRepository(this.api, {this.onPostUnavailable});
  final ApiClient api;
  final void Function(int id)? onPostUnavailable;
  Future<CursorPage<FeedItem>> fetch(int? after, CancelToken cancel) async {
    final page = await api.get(
      'activity-feeds',
      query: {'limit': 20, 'after': ?after},
      cancelToken: cancel,
      decode: (v) => CursorPage.fromJson(v, FeedItem.fromEvent),
    );
    final items = <FeedItem>[];
    // A CREATED_POST event survives deletion on the live server. Validate its
    // target before displaying or caching it, even if its snapshot looks full.
    for (var offset = 0; offset < page.items.length; offset += 4) {
      final batch = page.items.skip(offset).take(4);
      final resolved = await Future.wait(
        batch.map((item) async {
          if (item.targetType != 'POST') {
            return item;
          }
          try {
            final post = await api.get(
              'posts/${item.targetId}',
              decode: Post.fromJson,
              cancelToken: cancel,
            );
            return item.withPost(post);
          } on AppFailure catch (error) {
            if (error.kind == FailureKind.forbidden ||
                error.kind == FailureKind.notFound) {
              onPostUnavailable?.call(item.targetId);
              return null;
            }
            rethrow;
          }
        }),
      );
      items.addAll(resolved.whereType<FeedItem>());
    }
    return CursorPage(items, page.after, page.hasNext);
  }

  Future<int> newCount(DateTime since, CancelToken cancel) => api.get(
    'activity-feeds/new-count',
    query: {'since': since.millisecondsSinceEpoch.toString()},
    cancelToken: cancel,
    decode: (v) => count(object(v)['new_count']),
  );
}
