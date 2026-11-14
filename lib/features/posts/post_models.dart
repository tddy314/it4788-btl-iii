import '../../core/errors/app_failure.dart';

String postTime(DateTime? time) {
  if (time == null) return '';
  final date = time.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(date.day)}/${two(date.month)}/${date.year} · ${two(date.hour)}:${two(date.minute)}';
}

Map<String, dynamic> object(Object? value) {
  if (value is! Map<String, dynamic>) throw AppFailure.invalidData;
  return value;
}

int identifier(Object? value) {
  if (value is! int || value <= 0) throw AppFailure.invalidData;
  return value;
}

int count(Object? value) {
  if (value == null) return 0;
  if (value is! int || value < 0) throw AppFailure.invalidData;
  return value;
}

String textValue(Object? value) => value is String ? value : '';

class PostAuthor {
  const PostAuthor(this.id, this.name, this.avatar);
  final int? id;
  final String name;
  final String avatar;
  factory PostAuthor.fromJson(Object? value) {
    if (value == null) return const PostAuthor(null, 'Người dùng', '');
    final json = object(value);
    return PostAuthor(
      json['user_id'] == null ? null : identifier(json['user_id']),
      textValue(json['full_name']),
      textValue(json['avatar_url']),
    );
  }
  Map<String, dynamic> toJson() => {
    'user_id': id,
    'full_name': name,
    'avatar_url': avatar,
  };
}

class PostMedia {
  const PostMedia({
    required this.url,
    required this.type,
    this.key,
    this.width,
    this.height,
    this.size,
    this.duration,
    this.name,
    this.thumbnail,
  });
  final String url, type;
  final String? key, name, thumbnail;
  final int? width, height, size, duration;
  bool get isVideo => type == 'VIDEO';
  factory PostMedia.fromJson(Object? value) {
    final json = object(value);
    final url = textValue(json['url']);
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !uri.hasAuthority ||
        !['https', 'http'].contains(uri.scheme)) {
      throw AppFailure.invalidData;
    }
    return PostMedia(
      url: url,
      type: textValue(json['type']),
      key: json['key'] as String?,
      width: json['width'] as int?,
      height: json['height'] as int?,
      size: json['size'] as int?,
      duration: json['duration'] as int?,
      name: json['name'] as String?,
      thumbnail: json['thumbnail_url'] as String?,
    );
  }
  Map<String, dynamic> toJson() => {
    'url': url,
    'type': type,
    if (key != null) 'key': key,
    if (width != null) 'width': width,
    if (height != null) 'height': height,
    if (size != null) 'size': size,
    if (duration != null) 'duration': duration,
    if (name != null) 'name': name,
    if (thumbnail != null) 'thumbnail_url': thumbnail,
  };
}

class Post {
  const Post({
    required this.id,
    required this.content,
    required this.author,
    this.media = const [],
    this.type = 'SOCIAL_POST',
    this.visibility = '',
    this.reactCount = 0,
    this.commentCount = 0,
    this.reaction,
    this.createdAt,
    this.updatedAt,
    this.subject = '',
    this.lecturerNote = '',
  });
  final int id, reactCount, commentCount;
  final String content, type, visibility, subject, lecturerNote;
  final String? reaction;
  final PostAuthor author;
  final List<PostMedia> media;
  final DateTime? createdAt, updatedAt;
  bool get liked => reaction == 'LIKE';
  factory Post.fromJson(Object? value) {
    final json = object(value);
    return Post(
      id: identifier(json['post_id']),
      content: textValue(json['content']),
      author: PostAuthor.fromJson(json['author']),
      media: (json['media_urls'] as List? ?? [])
          .map(PostMedia.fromJson)
          .toList(),
      type: textValue(json['post_type']),
      visibility: textValue(json['visibility']),
      reactCount: count(json['react_count']),
      commentCount: count(json['comment_count']),
      reaction:
          json['my_reaction'] as String? ??
          (json['reacted_by_me'] == true ? 'LIKE' : null),
      createdAt: DateTime.tryParse(textValue(json['created_at'])),
      updatedAt: DateTime.tryParse(textValue(json['updated_at'])),
      subject: textValue(json['subject_name']),
      lecturerNote: textValue(json['lecturer_note']),
    );
  }
  Map<String, dynamic> toJson() => {
    'post_id': id,
    'content': content,
    'author': author.toJson(),
    'media_urls': media.map((m) => m.toJson()).toList(),
    'post_type': type,
    'visibility': visibility,
    'react_count': reactCount,
    'comment_count': commentCount,
    'my_reaction': reaction,
    'created_at': createdAt?.toIso8601String(),
    'updated_at': updatedAt?.toIso8601String(),
    'subject_name': subject,
    'lecturer_note': lecturerNote,
  };
  Post withReaction(Reaction result) => Post.fromJson({
    ...toJson(),
    'my_reaction': result.mine,
    'react_count': result.total,
  });
}

class Reaction {
  const Reaction(this.mine, this.total);
  final String? mine;
  final int total;
  factory Reaction.fromJson(Object? value) {
    final json = object(value);
    if (!json.containsKey('my_reaction') || json['total_count'] is! int) {
      throw AppFailure.invalidData;
    }
    return Reaction(json['my_reaction'] as String?, count(json['total_count']));
  }
}

class PostComment {
  const PostComment({
    required this.id,
    required this.content,
    required this.author,
    this.createdAt,
    this.deleted = false,
    this.replyCount = 0,
  });
  final int id, replyCount;
  final String content;
  final PostAuthor author;
  final DateTime? createdAt;
  final bool deleted;
  factory PostComment.fromJson(Object? value) {
    final json = object(value);
    final hidden =
        json['deleted'] == true ||
        json['hidden'] == true ||
        json['author'] == null;
    return PostComment(
      id: identifier(json['comment_id']),
      content: hidden ? '' : textValue(json['content']),
      author: PostAuthor.fromJson(hidden ? null : json['author']),
      createdAt: DateTime.tryParse(textValue(json['created_at'])),
      deleted: hidden,
      replyCount: count(json['reply_count']),
    );
  }
}

class CursorPage<T> {
  const CursorPage(this.items, this.after, this.hasNext);
  final List<T> items;
  final int? after;
  final bool hasNext;
  factory CursorPage.fromJson(Object? value, T Function(Object?) decode) {
    final json = object(value);
    final pagination = object(json['pagination']);
    if (json['items'] is! List || pagination['has_next'] is! bool) {
      throw AppFailure.invalidData;
    }
    final next = pagination['has_next'] as bool;
    final after = pagination['after'] == null
        ? null
        : identifier(pagination['after']);
    if (next && after == null) throw AppFailure.invalidData;
    return CursorPage(
      (json['items'] as List).map(decode).toList(),
      after,
      next,
    );
  }
}

bool accessRevoked(AppFailure error) => [
  FailureKind.unauthorized,
  FailureKind.forbidden,
  FailureKind.notFound,
].contains(error.kind);

// A lost response is not proof that a write failed. Never replay it automatically.
bool uncertainWrite(AppFailure error) => [
  FailureKind.offline,
  FailureKind.timeout,
  FailureKind.server,
  FailureKind.invalidData,
  FailureKind.unknown,
  FailureKind.cancelled,
].contains(error.kind);
