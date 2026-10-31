import 'package:dio/dio.dart';

import '../../core/errors/app_failure.dart';
import '../../core/network/api_client.dart';
import '../../core/storage/session_store.dart';
import 'device_identity.dart';

class AuthRepository {
  AuthRepository({required this.api, required this.device});
  final ApiClient api;
  final DeviceIdentity device;

  Future<SessionTokens> login(
    String email,
    String password, {
    CancelToken? cancelToken,
  }) async {
    final deviceId = await device.getId();
    try {
      return await api.request(
        'auth/login',
        method: 'POST',
        authenticated: false,
        cancelToken: cancelToken,
        data: {
          'email': email.trim(),
          'password': password,
          'device_id': deviceId,
          'platform': 'ANDROID',
        },
        decode: (value) {
          final json = value as Map<String, dynamic>;
          final id = json['user_id'];
          if ((id is! int && id is! String) || id.toString().isEmpty) {
            throw const FormatException('Invalid user ID');
          }
          return _tokens(json, id.toString());
        },
      );
    } on AppFailure catch (error) {
      throw _describe(error, login: true);
    }
  }

  Future<SessionTokens> refresh(SessionTokens current) => api.request(
    'auth/refresh',
    method: 'POST',
    authenticated: false,
    data: {'refresh_token': current.refreshToken},
    decode: (value) => _tokens(value as Map<String, dynamic>, current.userId),
  );

  Future<void> logout() =>
      api.request<void>('auth/logout', method: 'POST', decode: (_) {});

  Future<void> changePassword(
    String oldPassword,
    String newPassword, {
    CancelToken? cancelToken,
  }) async {
    try {
      await api.request<void>(
        'auth/change-password',
        method: 'POST',
        cancelToken: cancelToken,
        data: {'old_password': oldPassword, 'new_password': newPassword},
        decode: (_) {},
      );
    } on AppFailure catch (error) {
      throw _describe(error, login: false);
    }
  }

  static SessionTokens _tokens(Map<String, dynamic> json, String userId) {
    final access = json['access_token'];
    final refresh = json['refresh_token'];
    if (access is! String ||
        access.isEmpty ||
        refresh is! String ||
        refresh.isEmpty) {
      throw const FormatException('Invalid tokens');
    }
    return SessionTokens(
      userId: userId,
      accessToken: access,
      refreshToken: refresh,
    );
  }

  static AppFailure _describe(AppFailure failure, {required bool login}) {
    if (failure.statusCode == 400) {
      return AppFailure(
        failure.kind,
        login ? 'Email hoặc mật khẩu chưa đúng. Vui lòng kiểm tra lại.' : 'Không thể đổi mật khẩu. Vui lòng kiểm tra mật khẩu hiện tại và yêu cầu của máy chủ.',
        code: failure.code,
        statusCode: failure.statusCode,
      );
    }
    if (login && failure.kind == FailureKind.forbidden) {
      return AppFailure(
        failure.kind,
        'Tài khoản bị khóa hoặc chưa được kích hoạt. Vui lòng liên hệ giảng viên.',
        code: failure.code,
        statusCode: failure.statusCode,
      );
    }
    return failure;
  }
}
