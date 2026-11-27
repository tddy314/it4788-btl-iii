import 'package:flutter/foundation.dart';

import '../../../core/errors/app_failure.dart';
import '../data/notification_repository.dart';
import '../models/notification_item.dart';

class NotificationController extends ChangeNotifier {
  NotificationController({
    required this.repository,
    required this.userId,
    bool Function()? isCurrent,
  }) : _isCurrent = isCurrent ?? (() => true);
  final NotificationRepository repository;
  final String userId;
  final bool Function() _isCurrent;
  List<NotificationItem> _items = [];
  int _unreadCount = 0;
  bool _isLoading = false, _isLoadingMore = false, _isMarkingAllRead = false;
  bool _isFromCache = false, _disposed = false, _writing = false;
  int _generation = 0;
  String? _errorMessage, _after;
  bool _hasNext = false;
  bool get _active => !_disposed && _isCurrent();
  List<NotificationItem> get items => List.unmodifiable(_items);
  int get unreadCount => _unreadCount;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get isMarkingAllRead => _isMarkingAllRead;
  bool get isFromCache => _isFromCache;
  String? get errorMessage => _errorMessage;
  bool get hasNext => _hasNext;
  void _notify() {
    if (_active) notifyListeners();
  }

  Future<void> initialize() async {
    final generation = _generation;
    try {
      final cached = await repository.loadCached(userId);
      if (!_active || generation != _generation) return;
      if (cached != null) {
        _items = cached.items;
        _unreadCount = cached.unreadCount;
        _isFromCache = true;
        _hasNext = false;
        _notify();
      }
    } catch (_) {
      /* Cache must not prevent fetching. */
    }
    if (_active) await fetchFirstPage();
  }

  Future<void> fetchFirstPage({bool showLoading = true}) async {
    if (!_active || _isLoading || _writing) return;
    final generation = ++_generation;
    _isLoading = true;
    _isLoadingMore = false;
    _errorMessage = null;
    _notify();
    try {
      final response = await repository.fetchNotifications(limit: 20);
      if (!_active || generation != _generation) return;
      _items = response.items;
      _unreadCount = response.unreadCount;
      _after = response.after;
      _hasNext = response.hasNext;
      _isFromCache = false;
      await _persist();
    } on AppFailure catch (e) {
      if (!_active || generation != _generation) return;
      _errorMessage = e.message;
      if (const [
        FailureKind.unauthorized,
        FailureKind.forbidden,
        FailureKind.notFound,
      ].contains(e.kind)) {
        _items = [];
        _unreadCount = 0;
        _hasNext = false;
        try {
          await repository.clearCache(userId);
        } catch (_) {}
      }
    } catch (_) {
      if (_active) _errorMessage = 'Không thể tải thông báo. Vui lòng thử lại.';
    } finally {
      if (_active && generation == _generation) {
        _isLoading = false;
        _notify();
      }
    }
  }

  Future<void> refresh() => fetchFirstPage(showLoading: false);
  Future<void> loadMore() async {
    if (!_active ||
        _isLoading ||
        _isLoadingMore ||
        _writing ||
        !_hasNext ||
        _after == null ||
        _items.length >= 200 ||
        _isFromCache) {
      return;
    }
    final generation = _generation, cursor = _after;
    _isLoadingMore = true;
    _notify();
    try {
      final response = await repository.fetchNotifications(
        after: cursor,
        limit: 20,
      );
      if (!_active || generation != _generation) return;
      final ids = _items.map((e) => e.notificationId).toSet();
      _items = [
        ..._items,
        ...response.items.where((e) => ids.add(e.notificationId)),
      ].take(200).toList();
      _after = response.after;
      _hasNext =
          response.hasNext && response.after != cursor && _items.length < 200;
      _unreadCount = response.unreadCount;
      await _persist();
    } on AppFailure catch (e) {
      if (!_active || generation != _generation) return;
      _errorMessage = e.message;
      if (const [
        FailureKind.unauthorized,
        FailureKind.forbidden,
        FailureKind.notFound,
      ].contains(e.kind)) {
        _items = [];
        _unreadCount = 0;
        _hasNext = false;
        try {
          await repository.clearCache(userId);
        } catch (_) {}
      }
    } catch (_) {
      if (_active) _errorMessage = 'Không thể tải thêm thông báo.';
    } finally {
      if (_active && generation == _generation) {
        _isLoadingMore = false;
        _notify();
      }
    }
  }

  Future<void> _persist() async {
    if (!_active) return;
    try {
      await repository.saveToCache(
        userId,
        NotificationListResponse(
          items: _items,
          unreadCount: _unreadCount,
          after: _after,
          hasNext: _hasNext,
        ),
      );
    } catch (_) {
      if (_active) _errorMessage = 'Không lưu được thông báo trên máy.';
    }
  }

  Future<void> markAsRead(String id) async {
    if (!_active ||
        _writing ||
        !_items.any((e) => e.notificationId == id && !e.isRead)) {
      return;
    }
    await _mark(id);
  }

  Future<void> markAllAsRead() async {
    if (!_active || _writing || _unreadCount == 0) {
      return;
    }
    await _mark(null);
  }

  Future<void> _mark(String? id) async {
    // Opening an already-visible cached item must still mark it during a
    // refresh. Discard any older GET so it cannot undo the confirmed receipt.
    ++_generation;
    _isLoading = _isLoadingMore = false;
    _writing = true;
    _isMarkingAllRead = id == null;
    _errorMessage = null;
    _notify();
    var reconcile = false;
    try {
      NotificationReadResult? result;
      if (id == null) {
        await repository.markAllAsRead();
      } else {
        result = await repository.markAsRead(id);
        if (result.notificationId != id || !result.read) {
          throw AppFailure.invalidData;
        }
      }
      if (!_active) return;
      final readAt = result?.readAt ?? DateTime.now();
      _items = _items
          .map(
            (e) => id == null || e.notificationId == id
                ? e.copyWith(readAt: readAt)
                : e,
          )
          .toList();
      _unreadCount = result?.unreadCount ?? 0;
      await _persist();
    } on AppFailure catch (e) {
      if (_active) {
        _errorMessage = e.message;
        reconcile = e.kind != FailureKind.offline;
      }
    } catch (_) {
      if (_active) {
        reconcile = true;
        _errorMessage =
            'Chưa xác nhận được trạng thái đã đọc. Hãy tải lại để kiểm tra.';
      }
    } finally {
      _writing = false;
      _isMarkingAllRead = false;
      _notify();
    }
    // Only a GET may reconcile an ambiguous write; never replay the POST.
    if (_active && reconcile) await refresh();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    super.dispose();
  }
}
