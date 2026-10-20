import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../errors/app_failure.dart';
import '../storage/session_store.dart';
import 'connection_monitor.dart';

typedef TokenRefresher = Future<SessionTokens> Function(SessionTokens current);

/// Không retry tự động thao tác ghi/upload. Auth feature đăng ký refresher sau.
class ApiClient {
  ApiClient({
    required AppConfig config,
    required this.session,
    required this.connection,
    Dio? dio,
  }) : _config = config,
       _dio = dio ?? Dio() {
    _dio.options = BaseOptions(
      baseUrl: config.normalizedBaseUrl,
      connectTimeout: config.connectTimeout,
      receiveTimeout: config.receiveTimeout,
      sendTimeout: config.receiveTimeout,
      followRedirects: false,
      headers: {'Accept': 'application/json'},
    );
  }
  final AppConfig _config;
  final SessionStore session;
  final ConnectionMonitor connection;
  final Dio _dio;
  TokenRefresher? refreshTokens;
  Future<SessionTokens>? _refreshing;
  SessionTokens? _refreshingFor;

  Future<T> get<T>(
    String path, {
    required T Function(Object?) decode,
    Map<String, dynamic>? query,
    bool authenticated = true,
    CancelToken? cancelToken,
  }) => request(
    path,
    decode: decode,
    query: query,
    authenticated: authenticated,
    cancelToken: cancelToken,
  );

  Future<T> request<T>(
    String path, {
    required T Function(Object?) decode,
    String method = 'GET',
    Object? data,
    Map<String, dynamic>? query,
    bool authenticated = true,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
  }) async {
    final uri = Uri.parse(path);
    if (uri.hasScheme || uri.hasAuthority || uri.pathSegments.contains('..')) {
      throw ArgumentError('Chỉ dùng đường dẫn tương đối trong API client.');
    }
    final current = session.tokens;
    if (authenticated && current == null) throw AppFailure.unauthorized;
    await connection.check();
    if (connection.status == ConnectionStatus.offline) {
      throw AppFailure.offline;
    }
    if (authenticated && session.tokens?.userId != current?.userId) {
      throw AppFailure.unauthorized;
    }
    final verb = method.toUpperCase();
    try {
      return await _send(
        path,
        verb,
        data,
        query,
        authenticated ? current : null,
        decode,
        cancelToken,
        onSendProgress,
      );
    } on AppFailure catch (failure) {
      if (!authenticated ||
          current == null ||
          failure.kind != FailureKind.unauthorized ||
          refreshTokens == null) {
        rethrow;
      }
      // Không cho request cũ chạy tiếp dưới tài khoản mới hoặc sau logout.
      final latest = session.tokens;
      if (latest == null || latest.userId != current.userId) rethrow;
      if (identical(latest, current)) {
        await _refresh(current);
      }
      if (verb != 'GET' && verb != 'HEAD') {
        throw const AppFailure(
          FailureKind.rejected,
          'Phiên đã được làm mới. Vui lòng kiểm tra và gửi lại thao tác.',
        );
      }
      final renewed = session.tokens;
      if (renewed == null || renewed.userId != current.userId) {
        throw AppFailure.unauthorized;
      }
      // Chỉ một lần; không quay lại request() để tránh vòng lặp 401.
      return _send(
        path,
        verb,
        data,
        query,
        renewed,
        decode,
        cancelToken,
        onSendProgress,
      );
    }
  }

  Future<SessionTokens> _refresh(SessionTokens current) async {
    final pending = _refreshing;
    if (pending != null && identical(_refreshingFor, current)) return pending;
    final operation = () async {
      final next = await refreshTokens!(current);
      if (!identical(session.tokens, current) ||
          next.userId != current.userId) {
        throw AppFailure.unauthorized;
      }
      await session.save(next);
      return next;
    }();
    _refreshing = operation;
    _refreshingFor = current;
    try {
      return await operation;
    } finally {
      if (identical(_refreshing, operation)) {
        _refreshing = null;
        _refreshingFor = null;
      }
    }
  }

  Future<T> _send<T>(
    String path,
    String method,
    Object? data,
    Map<String, dynamic>? query,
    SessionTokens? session,
    T Function(Object?) decode,
    CancelToken? cancelToken,
    ProgressCallback? progress,
  ) async {
    try {
      final response = await _dio.request<Object?>(
        path.replaceFirst(RegExp(r'^/+'), ''),
        data: data,
        queryParameters: query,
        cancelToken: cancelToken,
        onSendProgress: progress,
        options: Options(
          method: method,
          headers: {
            if (session != null)
              'Authorization': 'Bearer ${session.accessToken}',
          },
        ),
      );
      // Không trả dữ liệu thuộc tài khoản cũ sau khi chuyển tài khoản/logout.
      if (session != null && this.session.tokens?.userId != session.userId) {
        throw AppFailure.unauthorized;
      }
      final json = response.data;
      if (json is! Map<String, dynamic> ||
          json['code'] == null ||
          !json.containsKey('data')) {
        throw AppFailure.invalidData;
      }
      if (json['code'].toString() != _config.successCode) {
        throw _failureFor(response.statusCode, json['code'].toString());
      }
      return decode(json['data']);
    } on DioException catch (error) {
      throw mapDioFailure(error);
    } on FormatException {
      throw AppFailure.invalidData;
    } on TypeError {
      throw AppFailure.invalidData;
    }
  }

  static AppFailure mapDioFailure(DioException error) {
    final body = error.response?.data;
    final code = body is Map ? body['code']?.toString() : null;
    return switch (error.type) {
      DioExceptionType.connectionError => AppFailure.offline,
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout => const AppFailure(
        FailureKind.timeout,
        'Kết nối quá thời gian chờ. Vui lòng kiểm tra trước khi gửi lại.',
      ),
      DioExceptionType.cancel => const AppFailure(
        FailureKind.cancelled,
        'Yêu cầu đã được hủy.',
      ),
      DioExceptionType.badResponse => _failureFor(
        error.response?.statusCode,
        code,
      ),
      _ =>
        error.error is FormatException
            ? AppFailure.invalidData
            : const AppFailure(
                FailureKind.unknown,
                'Không thể hoàn tất yêu cầu. Vui lòng thử lại.',
              ),
    };
  }

  static AppFailure _failureFor(int? status, String? code) {
    if (status == 401 || code == '9998') return AppFailure.unauthorized;
    final (kind, message) = switch (status) {
      403 => (
        FailureKind.forbidden,
        'Bạn không có quyền thực hiện thao tác này.',
      ),
      404 => (
        FailureKind.notFound,
        'Nội dung không còn tồn tại hoặc đã bị xóa.',
      ),
      429 => (
        FailureKind.rejected,
        'Bạn thao tác quá nhanh. Vui lòng thử lại sau.',
      ),
      final int value when value >= 500 => (
        FailureKind.server,
        'Máy chủ đang gặp sự cố. Vui lòng thử lại sau.',
      ),
      _ => (
        FailureKind.rejected,
        'Không thể thực hiện yêu cầu. Vui lòng kiểm tra dữ liệu và thử lại.',
      ),
    };
    return AppFailure(kind, message, code: code, statusCode: status);
  }

  void close() => _dio.close(force: true);
}
