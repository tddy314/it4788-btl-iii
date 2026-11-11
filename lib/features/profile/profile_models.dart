import '../../core/errors/app_failure.dart';
import '../relationships/social_models.dart';

abstract final class ProfileRoutes {
  static const user = '/profile/user';
}

class UserProfile {
  UserProfile._(this.json, this.id);
  final Map<String, dynamic> json;
  final String id;
  factory UserProfile.fromJson(Object? value) {
    final json = socialJson(value);
    return UserProfile._(Map.unmodifiable(json), socialId(json['user_id']));
  }
  String get name => text('full_name') ?? 'Người dùng';
  String? text(String key) => socialText(json[key]);
  int? count(String key) => socialCount(json[key]);
  String get roleLabel => switch (text('role')) {
    'STUDENT' => 'Sinh viên',
    'LECTURER' => 'Giảng viên',
    _ => 'Người dùng',
  };

  /// Only public presentation fields, never email, birth date, school code,
  /// relationship flags or other private fields in preferences.
  Map<String, dynamic> publicCache() => {
    for (final key in [
      'user_id',
      'full_name',
      'avatar_url',
      'cover_url',
      'bio',
      'role',
      'friends_count',
      'followers_count',
      'following_count',
    ])
      if (json[key] != null) key: json[key],
  };
}

class ProfileInput {
  const ProfileInput(this.fields, {this.changedKeys});
  final Map<String, String> fields;
  final Set<String>? changedKeys;
  static const editable = {
    'full_name',
    'bio',
    'gender',
    'date_of_birth',
    'timezone',
    'avatar_url',
    'cover_url',
  };

  String? validate({DateTime? now}) {
    final name = fields['full_name']?.trim() ?? '';
    if (name.isEmpty) return 'Vui lòng nhập họ và tên.';
    if (name.runes.length > 100) return 'Họ và tên tối đa 100 ký tự.';
    if ((fields['bio'] ?? '').runes.length > 500) {
      return 'Tiểu sử tối đa 500 ký tự.';
    }
    final gender = fields['gender'];
    if (gender != null &&
        gender.isNotEmpty &&
        !['MALE', 'FEMALE'].contains(gender)) {
      return 'Vui lòng chọn giới tính hợp lệ.';
    }
    final birth = fields['date_of_birth'];
    if (birth != null && birth.isNotEmpty) {
      final date = DateTime.tryParse(birth);
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(birth) ||
          date == null ||
          date.toIso8601String().substring(0, 10) != birth ||
          date.isAfter(now ?? DateTime.now())) {
        return 'Ngày sinh phải hợp lệ, theo dạng năm-tháng-ngày và không ở tương lai.';
      }
    }
    for (final key in ['avatar_url', 'cover_url']) {
      final url = fields[key];
      if (url != null && url.isNotEmpty) {
        final uri = Uri.tryParse(url);
        if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
          return 'Địa chỉ ảnh không hợp lệ.';
        }
      }
    }
    return null;
  }

  Map<String, dynamic> changesFrom(UserProfile profile) {
    final error = validate();
    if (error != null) throw AppFailure(FailureKind.rejected, error);
    return {
      for (final entry in fields.entries)
        if (editable.contains(entry.key) &&
            (changedKeys == null || changedKeys!.contains(entry.key)) &&
            // Omit unset optional values: null/clear semantics are undocumented.
            (entry.value.isNotEmpty || entry.key == 'bio') &&
            entry.value != (profile.text(entry.key) ?? ''))
          entry.key: entry.key == 'full_name'
              ? entry.value.trim()
              : entry.value,
    };
  }
}

class ProfileContent {
  const ProfileContent({
    required this.id,
    required this.title,
    required this.content,
    this.subtitle,
    this.status,
    this.image,
    this.video = false,
    this.createdAt,
  });
  final String id;
  final String title;
  final String content;
  final String? subtitle;
  final String? status;
  final String? image;
  final bool video;
  final DateTime? createdAt;

  factory ProfileContent.post(Object? value) {
    final json = socialJson(value);
    String? image;
    var video = false;
    final media = json['media_urls'];
    if (media is List) {
      for (final value in media) {
        if (value is! Map<String, dynamic>) continue;
        if (value['type'] == 'IMAGE') image ??= socialText(value['url']);
        if (value['type'] == 'VIDEO') {
          video = true;
          image ??= socialText(value['thumbnail_url']);
        }
      }
    }
    return ProfileContent(
      id: socialId(json['post_id']),
      title: 'Bài viết',
      content: socialText(json['content']) ?? '',
      image: image,
      video: video,
      createdAt: DateTime.tryParse(socialText(json['created_at']) ?? ''),
    );
  }

  factory ProfileContent.session(Object? value) {
    final json = socialJson(value);
    return ProfileContent(
      id: socialId(json['session_id']),
      title: socialText(json['title']) ?? 'Phiên đề xuất',
      content: socialText(json['content']) ?? '',
      subtitle: socialText(json['subject_name']),
      status: switch (json['status']) {
        'PENDING' => 'Chờ xem xét',
        'REVIEWING' => 'Đang xem xét',
        'RESOLVED' => 'Đã xử lý',
        _ => 'Chưa xác định trạng thái',
      },
      createdAt: DateTime.tryParse(socialText(json['created_at']) ?? ''),
    );
  }
}
