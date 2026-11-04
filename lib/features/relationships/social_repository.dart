import 'package:dio/dio.dart';

import '../../core/errors/app_failure.dart';
import '../../core/network/api_client.dart';
import 'social_models.dart';
import 'social_state.dart';

class SocialRepository {
  SocialRepository({required this.api, required this.lease}) {
    lease.owner.addListener(_sessionChanged);
  }
  final ApiClient api;
  final SocialLease lease;
  final cancel = CancelToken();

  void _sessionChanged() {
    // Cancel synchronously on logout/account switch, including the gap while
    // MediaUploadService is asynchronously opening a file before its request.
    if (!lease.active) cancel.cancel();
  }

  Future<T> read<T>(
    String path,
    T Function(Object?) decode, {
    Map<String, dynamic>? query,
  }) async {
    lease.check();
    final result = await api.get(
      path,
      decode: decode,
      query: query,
      cancelToken: cancel,
    );
    lease.check();
    return result;
  }

  Future<RelationshipStats> stats(String id) async {
    socialId(id);
    final result = await read(
      'users/$id/relationship-stats',
      RelationshipStats.fromJson,
    );
    if (result.userId != id) throw AppFailure.invalidData;
    return result;
  }

  Future<SocialPage<SocialPerson>> people(
    RelationshipList kind, {
    int? after,
  }) => read(
    kind.path,
    (data) => SocialPage.decode(data, kind.decode),
    query: {'limit': 20, 'after': ?after},
  );

  Future<bool> _contains(RelationshipList kind, String id) async {
    int? cursor;
    final seen = <int>{};
    // Explicit reconciliation only, with a hard bound and no retry/polling.
    for (var i = 0; i < 50; i++) {
      final page = await people(kind, after: cursor);
      if (page.items.any((person) => person.id == id)) return true;
      if (!page.hasNext) return false;
      if (!seen.add(page.after!)) throw AppFailure.invalidData;
      cursor = page.after;
    }
    throw const AppFailure(
      FailureKind.rejected,
      'Danh sách quá dài để đối soát. Vui lòng kiểm tra lại sau.',
    );
  }

  Future<void> _write(
    String path, {
    String method = 'POST',
    Object? data,
    void Function(Object?)? validate,
  }) async {
    lease.check();
    await api.request<void>(
      path,
      method: method,
      data: data,
      cancelToken: cancel,
      decode: (value) {
        validate?.call(value);
      },
    );
    lease.check();
  }

  /// Every user-initiated write first checks authoritative state, including
  /// retry after timeout/relaunch. No mutation is automatically replayed.
  Future<void> change(SocialAction action, String targetId) async {
    final id = int.parse(socialId(targetId));
    if (targetId == lease.userId) {
      throw const AppFailure(
        FailureKind.rejected,
        'Không thể thực hiện thao tác này với chính mình.',
      );
    }
    if (action == SocialAction.block || action == SocialAction.unblock) {
      final blocked = await _contains(RelationshipList.blocked, targetId);
      if (blocked == (action == SocialAction.block)) return;
      await _write(
        'blocks/$id',
        method: action == SocialAction.block ? 'POST' : 'DELETE',
        validate: (value) {
          final json = socialJson(value);
          if (json['blocked'] != (action == SocialAction.block) ||
              socialId(
                    json[action == SocialAction.block
                        ? 'blocked_user_id'
                        : 'unblocked_user_id'],
                  ) !=
                  targetId) {
            throw AppFailure.invalidData;
          }
        },
      );
      return;
    }
    final state = await stats(targetId);
    if (state.blocked != false) {
      throw const AppFailure(
        FailureKind.forbidden,
        'Không thể thao tác khi quan hệ bị chặn hoặc chưa xác định.',
      );
    }
    switch (action) {
      case SocialAction.request:
        if (state.isFriend == true || state.requestStatus == 'PENDING') return;
        if (state.isFriend != false ||
            !['NONE', 'DECLINED'].contains(state.requestStatus)) {
          throw AppFailure.invalidData;
        }
        final me = await read('users/me', socialJson);
        final target = await read('users/$targetId', socialJson);
        if (!['STUDENT', 'LECTURER'].contains(me['role']) ||
            me['role'] != target['role']) {
          throw const AppFailure(
            FailureKind.rejected,
            'Chỉ có thể kết bạn với người dùng cùng vai trò sinh viên hoặc giảng viên.',
          );
        }
        await _write(
          'friendships/request',
          data: {'addressee_id': id},
          validate: (value) => _friendship(value, targetId),
        );
      case SocialAction.accept:
      case SocialAction.decline:
        if (state.isFriend == true) return;
        if (!await _contains(RelationshipList.received, targetId)) return;
        await _write(
          'friendships/${action == SocialAction.accept ? 'accept' : 'decline'}',
          data: {'requester_id': id},
          validate: action == SocialAction.accept
              ? (value) => _friendship(value, targetId, accepted: true)
              : null,
        );
      case SocialAction.unfriend:
        if (state.isFriend == false) return;
        if (state.isFriend != true) throw AppFailure.invalidData;
        await _write('friendships/$id', method: 'DELETE');
      case SocialAction.follow:
      case SocialAction.unfollow:
        final desired = action == SocialAction.follow;
        if (state.isFollowing == desired) return;
        if (state.isFollowing == null) throw AppFailure.invalidData;
        await _write(
          'follows/$id',
          method: desired ? 'POST' : 'DELETE',
          validate: (value) {
            final json = socialJson(value);
            if (json['following'] != desired ||
                socialId(json['target_user_id']) != targetId) {
              throw AppFailure.invalidData;
            }
          },
        );
      case SocialAction.block:
      case SocialAction.unblock:
        break;
    }
  }

  void _friendship(Object? value, String targetId, {bool accepted = false}) {
    final json = socialJson(value);
    final requester = socialId(json['requester_id']);
    final addressee = socialId(json['addressee_id']);
    if (!((requester == lease.userId && addressee == targetId) ||
            (requester == targetId && addressee == lease.userId)) ||
        !(accepted ? ['ACCEPTED'] : ['PENDING', 'ACCEPTED']).contains(
          json['status'],
        )) {
      throw AppFailure.invalidData;
    }
  }

  void dispose() {
    lease.owner.removeListener(_sessionChanged);
    cancel.cancel();
  }
}
