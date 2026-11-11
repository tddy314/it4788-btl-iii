import 'package:dio/dio.dart';

import '../../core/errors/app_failure.dart';
import '../../core/network/api_client.dart';
import 'social_models.dart';
import 'social_state.dart';

String? validateFriendQuery(String query) {
  if (query.trim().isEmpty) return 'Nhập tên người dùng để tìm bạn bè.';
  if (query.trim().runes.length > 200) return 'Từ khóa tối đa 200 ký tự.';
  return null;
}

/// Only user discovery for the friendship flow. No global search/history writes.
class FriendFinderRepository {
  FriendFinderRepository({required this.api, required this.lease}) {
    lease.owner.addListener(_sessionChanged);
  }
  final ApiClient api;
  final SocialLease lease;
  final _tokens = <CancelToken>{};
  bool _disposed = false;
  bool get active => !_disposed && lease.active;

  void _sessionChanged() {
    if (!lease.active) _cancel();
  }

  void _cancel() {
    for (final token in _tokens.toList()) {
      token.cancel();
    }
    _tokens.clear();
  }

  Future<SocialPage<SocialPerson>> find(
    String query, {
    int offset = 0,
    required CancelToken cancelToken,
  }) async {
    final error = validateFriendQuery(query);
    if (error != null || offset < 0) {
      throw AppFailure(
        FailureKind.rejected,
        error ?? 'Vị trí tìm người không hợp lệ.',
      );
    }
    lease.check();
    if (_disposed) throw AppFailure.unauthorized;
    _tokens.add(cancelToken);
    try {
      final page = await api.get(
        'search',
        query: {
          'query': query.trim(),
          'type': 'USER',
          'limit': 20,
          if (offset > 0) 'after': offset,
        },
        cancelToken: cancelToken,
        decode: (data) {
          final page = SocialPage<SocialPerson>.decode(data, (value) {
            final item = socialJson(value);
            if (item['type'] != 'USER') throw AppFailure.invalidData;
            // Reuse the public person DTO; discard email and student codes.
            return SocialPerson.fromJson(item['user']);
          });
          if (page.hasNext && page.after! <= offset) {
            throw AppFailure.invalidData;
          }
          return page;
        },
      );
      lease.check();
      if (_disposed) throw AppFailure.unauthorized;
      return page;
    } finally {
      _tokens.remove(cancelToken);
    }
  }

  void dispose() {
    _disposed = true;
    lease.owner.removeListener(_sessionChanged);
    _cancel();
  }
}
