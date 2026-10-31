import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/errors/app_failure.dart';
import '../../core/storage/session_store.dart';
import 'auth_repository.dart';
import 'auth_validation.dart';

/// Sống cùng app, không cùng màn login. Không lưu password hoặc log token.
class AuthController extends ChangeNotifier {
  AuthController({required this.repository, required this.session});
  final AuthRepository repository;
  final SessionStore session;
  bool busy = false;
  String? message;
  CancelToken? _loginCancel;
  bool _disposed = false;

  Future<void> login(String email, String password) async {
    if (busy || _disposed) return;
    message = AuthValidation.email(email) ?? AuthValidation.password(password);
    if (message != null) {
      notifyListeners();
      return;
    }
    busy = true;
    _loginCancel = CancelToken();
    notifyListeners();
    try {
      final tokens = await repository.login(
        email,
        password,
        cancelToken: _loginCancel,
      );
      if (_disposed || _loginCancel!.isCancelled) return;
      await session.save(tokens);
    } on AppFailure catch (error) {
      message = error.kind == FailureKind.cancelled ? null : error.message;
    } catch (_) {
      message = 'Không thể lưu phiên đăng nhập. Vui lòng thử lại.';
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// Mạng lỗi giữ phiên. Chỉ kết quả refresh xác thực bị từ chối mới hết phiên.
  Future<SessionTokens> refresh(SessionTokens current) async {
    try {
      return await repository.refresh(current);
    } on AppFailure catch (error) {
      if ((error.kind == FailureKind.unauthorized ||
              error.kind == FailureKind.forbidden) &&
          identical(session.tokens, current)) {
        message = 'Phiên đăng nhập đã kết thúc. Vui lòng đăng nhập lại.';
        await session.clear();
      }
      rethrow;
    }
  }

  Future<void> logout() async {
    if (busy || _disposed) return;
    busy = true;
    message = null;
    notifyListeners();
    var serverConfirmed = false;
    try {
      await repository.logout();
      serverConfirmed = true;
    } catch (_) {
      // Vẫn cho logout cục bộ khi offline; không tuyên bố server đã thu hồi.
    }
    try {
      message = serverConfirmed ? null : 'Đã đăng xuất trên máy này. Chưa xác nhận được thu hồi phiên trên máy chủ.';
      await session.clear();
    } catch (_) {
      message = 'Không thể xóa phiên đã lưu. Hãy thử đăng xuất lại trước khi đóng ứng dụng.';
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _loginCancel?.cancel();
    super.dispose();
  }
}
