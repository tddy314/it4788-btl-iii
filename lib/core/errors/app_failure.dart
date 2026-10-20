enum FailureKind {
  offline,
  timeout,
  unauthorized,
  forbidden,
  notFound,
  server,
  invalidData,
  rejected,
  cancelled,
  storage,
  unknown,
}

class AppFailure implements Exception {
  const AppFailure(this.kind, this.message, {this.code, this.statusCode});
  final FailureKind kind;
  final String message;
  final String? code;
  final int? statusCode;
  bool get canUseCache => switch (kind) {
    FailureKind.offline || FailureKind.timeout || FailureKind.server => true,
    _ => false,
  };
  static const offline = AppFailure(
    FailureKind.offline,
    'Không thể kết nối mạng. Vui lòng kiểm tra kết nối và thử lại.',
  );
  static const invalidData = AppFailure(
    FailureKind.invalidData,
    'Dữ liệu trả về không hợp lệ. Vui lòng thử lại.',
  );
  static const unauthorized = AppFailure(
    FailureKind.unauthorized,
    'Phiên đăng nhập không còn hợp lệ. Vui lòng đăng nhập lại.',
  );
  @override
  String toString() => 'AppFailure(${kind.name}, code: $code)';
}
