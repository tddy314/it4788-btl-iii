import 'package:dio/dio.dart';

import '../../core/network/api_client.dart';
import '../../core/errors/app_failure.dart';
import '../../core/validation/validators.dart';
import 'post_models.dart';

class PostsRepository {
  PostsRepository(this.api);
  final ApiClient api;
  Future<Post> get(int id, {CancelToken? cancel}) =>
      api.get('posts/$id', decode: Post.fromJson, cancelToken: cancel);
  Future<CursorPage<Post>> mine({int? after, CancelToken? cancel}) => api.get(
    'posts/me',
    query: {'limit': 20, 'after': ?after},
    cancelToken: cancel,
    decode: (v) => CursorPage.fromJson(v, Post.fromJson),
  );
  Future<CursorPage<Post>> videos({int? after, CancelToken? cancel}) => api.get(
    'video-posts',
    query: {'limit': 3, 'after': ?after},
    cancelToken: cancel,
    decode: (v) => CursorPage.fromJson(v, Post.fromJson),
  );
  Future<Post> create(
    String content,
    List<PostMedia> media, {
    CancelToken? cancel,
  }) {
    validatePost(content, media);
    return api.request(
      'posts',
      method: 'POST',
      cancelToken: cancel,
      data: {
        'content': content.trim(),
        'media_urls': media.map((e) => e.toJson()).toList(),
        'visibility': 'PUBLIC',
        'post_type': 'SOCIAL_POST',
      },
      decode: Post.fromJson,
    );
  }

  Future<void> update(
    int id,
    String content,
    List<PostMedia> media, {
    CancelToken? cancel,
  }) {
    validatePost(content, media);
    return api.request(
      'posts/$id',
      method: 'PUT',
      cancelToken: cancel,
      data: {
        'content': content.trim(),
        'media_urls': media.map((e) => e.toJson()).toList(),
        'visibility': 'PUBLIC',
      },
      decode: (v) {
        if (identifier(object(v)['post_id']) != id) {
          throw AppFailure.invalidData;
        }
      },
    );
  }

  Future<void> delete(int id, {CancelToken? cancel}) => api.request(
    'posts/$id',
    method: 'DELETE',
    cancelToken: cancel,
    decode: (v) {
      if (identifier(object(v)['post_id']) != id) throw AppFailure.invalidData;
    },
  );
  Future<Reaction> like(int id, {CancelToken? cancel}) => api.request(
    'react',
    method: 'POST',
    data: {'target_type': 'POST', 'target_id': id, 'reaction_type': 'LIKE'},
    cancelToken: cancel,
    decode: Reaction.fromJson,
  );
  Future<CursorPage<PostComment>> comments(
    int id, {
    int? after,
    int? parent,
    CancelToken? cancel,
  }) => api.get(
    'comments',
    cancelToken: cancel,
    query: {
      'target_type': 'POST',
      'target_id': id,
      'sort': 'newest',
      'limit': 20,
      'after': ?after,
      'parent_comment_id': ?parent,
    },
    decode: (v) => CursorPage.fromJson(v, PostComment.fromJson),
  );
  Future<PostComment> comment(
    int id,
    String content, {
    int? parent,
    CancelToken? cancel,
  }) {
    final error =
        Validators.requiredText(content) ?? Validators.maxWords(content, 500);
    if (error != null) throw AppFailure(FailureKind.rejected, error);
    return api.request(
      'comments',
      method: 'POST',
      cancelToken: cancel,
      data: {
        'target_type': 'POST',
        'target_id': id,
        'content': content.trim(),
        'parent_comment_id': ?parent,
      },
      decode: PostComment.fromJson,
    );
  }

  Future<void> deleteComment(int id, {CancelToken? cancel}) => api.request(
    'comments/$id',
    method: 'DELETE',
    cancelToken: cancel,
    decode: (_) {},
  );
  Future<void> report(
    int id,
    String reason,
    String description, {
    CancelToken? cancel,
  }) {
    if (!['SPAM', 'HARASSMENT', 'HATE_STATEMENT', 'OTHER'].contains(reason) ||
        description.runes.length > 500) {
      throw const AppFailure(
        FailureKind.rejected,
        'Báo cáo không hợp lệ (tối đa 500 ký tự).',
      );
    }
    return api.request(
      'report',
      method: 'POST',
      cancelToken: cancel,
      data: {
        'target_type': 'POST',
        'target_id': id,
        'violation_type': reason,
        'description': description.trim(),
      },
      decode: (v) {
        identifier(object(v)['report_id']);
      },
    );
  }

  static void validatePost(String content, List<PostMedia> media) {
    final error = Validators.maxWords(content, 500);
    if (error != null) throw AppFailure(FailureKind.rejected, error);
    if (content.trim().isEmpty && media.isEmpty) {
      throw const AppFailure(
        FailureKind.rejected,
        'Nhập nội dung hoặc chọn ảnh/video cho bài viết.',
      );
    }
    if (media.any((m) => !['IMAGE', 'VIDEO'].contains(m.type)) ||
        media.length > 4 ||
        (media.any((m) => m.isVideo) && media.length != 1)) {
      throw const AppFailure(
        FailureKind.rejected,
        'Chỉ chọn tối đa 4 ảnh hoặc 1 video, không trộn cả hai.',
      );
    }
  }
}
