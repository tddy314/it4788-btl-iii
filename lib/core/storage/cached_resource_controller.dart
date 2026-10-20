import 'package:flutter/foundation.dart';

import '../errors/app_failure.dart';
import 'json_cache.dart';

/// Nền tảng cho các màn chỉ đọc: cache trước, refresh sau, giữ data khi lỗi mạng.
/// Mỗi instance gắn với một user/resource, dispose khi logout/chuyển tài khoản.
class CachedResourceController<T> extends ChangeNotifier {
  CachedResourceController({
    required this.cache,
    required this.userId,
    required this.resource,
    required this.fetch,
    required this.decode,
    required this.encode,
  });
  final JsonCache cache;
  final String userId;
  final String resource;
  final Future<T> Function() fetch;
  final T Function(Object?) decode;
  final Object? Function(T) encode;
  T? data;
  DateTime? savedAt;
  AppFailure? failure;
  bool isLoading = false;
  bool isFromCache = false;
  bool _disposed = false;

  Future<void> load() async {
    if (isLoading || _disposed) return;
    isLoading = true;
    failure = null;
    notifyListeners();
    if (data == null) {
      try {
        final entry = await cache.read(userId: userId, resource: resource);
        if (_disposed) return;
        if (entry != null) {
          data = decode(entry.data);
          savedAt = entry.savedAt;
          isFromCache = true;
          notifyListeners();
        }
      } catch (_) {
        // Cache hỏng/không đọc được không ngăn việc tải dữ liệu thật.
      }
    }
    try {
      final fresh = await fetch();
      if (_disposed) return;
      data = fresh;
      isFromCache = false;
      savedAt = DateTime.now().toUtc();
      try {
        await cache.write(
          userId: userId,
          resource: resource,
          data: encode(fresh),
        );
      } catch (_) {
        // Lỗi lưu cache không biến request đã thành công thành thất bại.
      }
    } on AppFailure catch (error) {
      if (_disposed) return;
      failure = error;
      if (!error.canUseCache) {
        data = null;
        savedAt = null;
        isFromCache = false;
        if (error.kind == FailureKind.unauthorized ||
            error.kind == FailureKind.forbidden ||
            error.kind == FailureKind.notFound) {
          try {
            await cache.remove(userId: userId, resource: resource);
          } catch (_) {
            // Vẫn ẩn nội dung nếu bộ nhớ đang không ghi được.
          }
        }
      }
    } catch (_) {
      if (_disposed) return;
      failure = const AppFailure(
        FailureKind.unknown,
        'Không thể tải nội dung. Vui lòng thử lại.',
      );
    } finally {
      if (!_disposed) {
        isLoading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
