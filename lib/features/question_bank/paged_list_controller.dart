import 'package:flutter/foundation.dart';

import '../../core/errors/app_failure.dart';
import '../../core/storage/json_cache.dart';
import 'question_models.dart';

typedef PageFetcher<T> = Future<CursorPage<T>> Function(int? after);

/// Danh sách phân trang con trỏ cho ngân hàng câu hỏi.
///
/// - Chỉ cache trang đầu của bộ lọc mặc định (giới hạn số mục), theo tài khoản.
/// - Refresh thất bại do mạng giữ danh sách cũ; 401/403/404 thì xóa và bỏ cache.
/// - Mỗi lần đổi bộ lọc/refresh tăng `generation`; phản hồi cũ về sau bị bỏ qua.
/// - Không tự retry; load-more lỗi giữ nguyên danh sách và cho bấm thử lại.
class PagedListController<T> extends ChangeNotifier {
  PagedListController({
    required PageFetcher<T> fetch,
    required this.idOf,
    this.cache,
    this.userId,
    this.encode,
    this.decode,
    this.maxCachedItems = 20,
  }) : _fetcher = fetch;

  PageFetcher<T> _fetcher;
  final Object Function(T) idOf;
  final JsonCache? cache;
  final String? userId;
  final Object? Function(T)? encode;
  final T Function(Object?)? decode;
  final int maxCachedItems;

  /// null: bộ lọc hiện tại không được cache.
  String? _resource;

  List<T> items = const [];
  bool hasNext = false;
  int? _cursor;
  bool isRefreshing = false;
  bool isLoadingMore = false;
  bool isFromCache = false;
  bool loadedOnce = false;
  DateTime? savedAt;
  AppFailure? failure;
  AppFailure? loadMoreFailure;
  int _generation = 0;
  bool _disposed = false;

  bool get isEmpty => items.isEmpty;

  /// Đổi nguồn dữ liệu (bộ lọc/từ khóa) rồi tải lại từ đầu.
  Future<void> reset(PageFetcher<T> fetch, {String? resource}) {
    _fetcher = fetch;
    _resource = resource;
    _generation++;
    items = const [];
    hasNext = false;
    _cursor = null;
    isFromCache = false;
    loadedOnce = false;
    savedAt = null;
    failure = null;
    loadMoreFailure = null;
    isRefreshing = false;
    isLoadingMore = false;
    _notify();
    return refresh();
  }

  void setResource(String? resource) => _resource = resource;

  Future<void> refresh() async {
    if (_disposed || isRefreshing) return;
    final generation = ++_generation;
    isRefreshing = true;
    // Refresh thay thế mọi load-more đang chạy; kết quả cũ sẽ bị bỏ.
    isLoadingMore = false;
    failure = null;
    loadMoreFailure = null;
    _notify();
    if (items.isEmpty && !loadedOnce) await _readCache(generation);
    if (!_current(generation)) return;
    try {
      final page = await _fetcher(null);
      if (!_current(generation)) return;
      items = _dedupe(page.items);
      hasNext = page.hasNext;
      _cursor = page.after;
      isFromCache = false;
      savedAt = DateTime.now().toUtc();
      await _writeCache(items);
    } on AppFailure catch (error) {
      if (!_current(generation)) return;
      failure = error;
      if (!error.canUseCache) {
        items = const [];
        hasNext = false;
        _cursor = null;
        isFromCache = false;
        if (error.kind == FailureKind.unauthorized ||
            error.kind == FailureKind.forbidden ||
            error.kind == FailureKind.notFound) {
          await _removeCache();
        }
      }
    } catch (_) {
      if (!_current(generation)) return;
      failure = AppFailure.invalidData;
    } finally {
      if (_current(generation)) {
        isRefreshing = false;
        loadedOnce = true;
        _notify();
      }
    }
  }

  Future<void> loadMore() async {
    if (_disposed || isRefreshing || isLoadingMore || !hasNext) return;
    // Danh sách từ cache chưa có cursor đáng tin; cần refresh thành công trước.
    if (isFromCache || _cursor == null) return;
    final generation = _generation;
    final cursor = _cursor;
    isLoadingMore = true;
    loadMoreFailure = null;
    _notify();
    try {
      final page = await _fetcher(cursor);
      if (!_current(generation) || cursor != _cursor) return;
      items = _dedupe([...items, ...page.items]);
      // Server trả cùng cursor → dừng để tránh gọi lại cùng trang vô hạn.
      hasNext = page.hasNext && page.after != cursor;
      _cursor = page.after;
    } on AppFailure catch (error) {
      if (!_current(generation)) return;
      loadMoreFailure = error;
    } catch (_) {
      if (!_current(generation)) return;
      loadMoreFailure = AppFailure.invalidData;
    } finally {
      if (_current(generation)) {
        isLoadingMore = false;
        _notify();
      }
    }
  }

  /// Cập nhật cục bộ sau khi server xác nhận (ví dụ xóa một mục).
  void removeWhere(bool Function(T) test) {
    items = items.where((item) => !test(item)).toList(growable: false);
    _notify();
    _writeCache(items);
  }

  bool _current(int generation) => !_disposed && generation == _generation;

  List<T> _dedupe(List<T> values) {
    final seen = <Object>{};
    return [
      for (final item in values)
        if (seen.add(idOf(item))) item,
    ];
  }

  Future<void> _readCache(int generation) async {
    final resource = _resource;
    final cache = this.cache, user = userId, decode = this.decode;
    if (resource == null || cache == null || user == null || decode == null) {
      return;
    }
    try {
      final entry = await cache.read(userId: user, resource: resource);
      if (entry == null || !_current(generation)) return;
      items = [for (final raw in qbList(entry.data)) decode(raw)];
      savedAt = entry.savedAt;
      isFromCache = true;
      hasNext = false;
      _notify();
    } catch (_) {
      // Cache hỏng chỉ là cache miss.
    }
  }

  Future<void> _writeCache(List<T> values) async {
    final resource = _resource;
    final cache = this.cache, user = userId, encode = this.encode;
    if (resource == null || cache == null || user == null || encode == null) {
      return;
    }
    try {
      await cache.write(
        userId: user,
        resource: resource,
        data: [for (final item in values.take(maxCachedItems)) encode(item)],
      );
    } catch (_) {
      // Lỗi lưu cache không biến request thành công thành thất bại.
    }
  }

  Future<void> _removeCache() async {
    final resource = _resource;
    final cache = this.cache, user = userId;
    if (resource == null || cache == null || user == null) return;
    try {
      await cache.remove(userId: user, resource: resource);
    } catch (_) {}
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
