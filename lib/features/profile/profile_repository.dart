import '../../core/errors/app_failure.dart';
import '../relationships/social_models.dart';
import '../relationships/social_repository.dart';
import 'profile_models.dart';

class ProfileRepository {
  ProfileRepository(this.social);
  final SocialRepository social;

  Future<UserProfile> profile(String id) async {
    socialId(id);
    final result = await social.read(
      id == social.lease.userId ? 'users/me' : 'users/$id',
      UserProfile.fromJson,
    );
    if (result.id != id) throw AppFailure.invalidData;
    return result;
  }

  Future<UserProfile> update(ProfileInput input) async {
    // Validate before connectivity/API. Read first to reconcile a previous
    // ambiguous PUT and omit unchanged fields instead of replaying blindly.
    final error = input.validate();
    if (error != null) throw AppFailure(FailureKind.rejected, error);
    final current = await profile(social.lease.userId);
    final changes = input.changesFrom(current);
    if (changes.isEmpty) return current;
    social.lease.check();
    final saved = await social.api.request(
      'users/me',
      method: 'PUT',
      data: changes,
      decode: UserProfile.fromJson,
      cancelToken: social.cancel,
    );
    social.lease.check();
    if (saved.id != social.lease.userId) throw AppFailure.invalidData;
    // A success envelope without the updated representation is not confirmation.
    if (changes.entries.any((entry) => saved.text(entry.key) != entry.value)) {
      throw const AppFailure(
        FailureKind.invalidData,
        'Máy chủ chưa trả về đầy đủ thay đổi. Hãy tải lại hồ sơ để kiểm tra trước khi lưu tiếp.',
      );
    }
    return saved;
  }

  Future<SocialPage<ProfileContent>> content(
    String id, {
    required bool sessions,
    int? after,
  }) async {
    socialId(id);
    if (id != social.lease.userId) {
      final relation = await social.stats(id);
      if (relation.blocked != false) {
        throw const AppFailure(
          FailureKind.forbidden,
          'Không thể xem nội dung của người dùng này.',
        );
      }
    }
    return social.read(
      'users/$id/${sessions ? 'sessions' : 'posts'}',
      (data) => SocialPage.decode(
        data,
        sessions ? ProfileContent.session : ProfileContent.post,
        itemsKey: sessions ? 'contents' : 'items',
      ),
      query: {'limit': 10, 'after': ?after},
    );
  }
}
