import '../../core/errors/app_failure.dart';

Map<String, dynamic> socialJson(Object? value) {
  if (value is! Map<String, dynamic>) throw AppFailure.invalidData;
  return value;
}

String socialId(Object? value) {
  if (value is int && value > 0) return value.toString();
  if (value is String && RegExp(r'^[1-9][0-9]*$').hasMatch(value)) {
    return value;
  }
  throw AppFailure.invalidData;
}

String? socialText(Object? value) => value is String ? value : null;
int? socialCount(Object? value) => value is int && value >= 0 ? value : null;

/// Unknown/missing flags remain unknown: never manufacture permission to write.
bool? socialFlag(Object? value) => value is bool ? value : null;

class SocialPerson {
  const SocialPerson({
    required this.id,
    required this.name,
    this.avatar,
    this.role,
    this.subtitle,
  });
  final String id;
  final String name;
  final String? avatar;
  final String? role;
  final String? subtitle;

  factory SocialPerson.fromJson(Object? value) {
    final json = socialJson(value);
    return SocialPerson(
      id: socialId(json['user_id']),
      name: socialText(json['full_name']) ?? 'Người dùng',
      avatar: socialText(json['avatar_url']),
      role: socialText(json['role']),
      subtitle: socialText(json['school_faculty']),
    );
  }
}

enum RelationshipList {
  friends('Bạn bè', 'friendships'),
  received('Lời mời nhận', 'friendships/requests/received'),
  sent('Lời mời gửi', 'friendships/requests/sent'),
  following('Đang theo dõi', 'follows/following'),
  followers('Người theo dõi', 'follows/followers'),
  blocked('Đã chặn', 'blocks');

  const RelationshipList(this.label, this.path);
  final String label;
  final String path;

  SocialPerson decode(Object? value) {
    final json = socialJson(value);
    return SocialPerson.fromJson(switch (this) {
      received => json['requester'],
      sent => json['receiver'],
      _ => json,
    });
  }
}

class SocialPage<T> {
  const SocialPage({required this.items, required this.hasNext, this.after});
  final List<T> items;
  final bool hasNext;
  final int? after;

  factory SocialPage.decode(
    Object? value,
    T Function(Object?) decode, {
    String itemsKey = 'items',
  }) {
    final json = socialJson(value);
    final items = json[itemsKey];
    final pagination = socialJson(json['pagination']);
    final hasNext = pagination['has_next'];
    final after = pagination['after'];
    if (items is! List ||
        hasNext is! bool ||
        (after != null && after is! int) ||
        (hasNext && (after is! int || items.isEmpty))) {
      throw AppFailure.invalidData;
    }
    return SocialPage(
      items: items.map(decode).toList(),
      hasNext: hasNext,
      after: after as int?,
    );
  }
}

class RelationshipStats {
  const RelationshipStats({
    required this.userId,
    this.friends,
    this.followers,
    this.followingCount,
    this.isFriend,
    this.isFollowing,
    this.followedBy,
    this.blocked,
    this.requestStatus,
  });
  final String userId;
  final int? friends;
  final int? followers;
  final int? followingCount;
  final bool? isFriend;
  final bool? isFollowing;
  final bool? followedBy;
  final bool? blocked;
  final String? requestStatus;

  factory RelationshipStats.fromJson(Object? value) {
    final json = socialJson(value);
    final counts = socialJson(json['counts']);
    final relation = socialJson(json['relationship_with_me']);
    return RelationshipStats(
      userId: socialId(json['user_id']),
      friends: socialCount(counts['friends_count']),
      followers: socialCount(counts['followers_count']),
      followingCount: socialCount(counts['following_count']),
      isFriend: socialFlag(relation['friend']),
      isFollowing: socialFlag(relation['following']),
      followedBy: socialFlag(relation['followed_by']),
      blocked: socialFlag(relation['blocked']),
      requestStatus: socialText(relation['friend_request_status']),
    );
  }
}

enum SocialAction {
  request('Kết bạn'),
  accept('Chấp nhận'),
  decline('Từ chối'),
  unfriend('Hủy kết bạn'),
  follow('Theo dõi'),
  unfollow('Bỏ theo dõi'),
  block('Chặn'),
  unblock('Bỏ chặn');

  const SocialAction(this.label);
  final String label;
}
