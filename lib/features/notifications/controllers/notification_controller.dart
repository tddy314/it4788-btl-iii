import 'package:flutter/foundation.dart';

import '../../../core/errors/app_failure.dart';
import '../data/notification_repository.dart';
import '../models/notification_item.dart';

class NotificationController extends ChangeNotifier {
  NotificationController({required this.repository, required this.userId});

  final NotificationRepository repository;
  final String userId;

  List<NotificationItem> _items = [];
  int _unreadCount = 0;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _isMarkingAllRead = false;
  bool _isFromCache = false;
  String? _errorMessage;
  String? _after;
  bool _hasNext = false;

  List<NotificationItem> get items => List.unmodifiable(_items);
  int get unreadCount => _unreadCount;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get isMarkingAllRead => _isMarkingAllRead;
  bool get isFromCache => _isFromCache;
  String? get errorMessage => _errorMessage;
  bool get hasNext => _hasNext;

  Future<void> initialize() async {
    // 1. Đọc từ cache trước (Cache-first pattern để hiển thị tức thì & hỗ trợ offline)
    final cached = await repository.loadCached(userId);
    if (cached != null && cached.items.isNotEmpty) {
      _items = cached.items;
      _unreadCount = cached.unreadCount;
      _after = cached.after;
      _hasNext = cached.hasNext;
      _isFromCache = true;
      notifyListeners();
    }

    // 2. Fetch dữ liệu mới từ server
    await fetchFirstPage(showLoading: _items.isEmpty);
  }

  Future<void> fetchFirstPage({bool showLoading = true}) async {
    if (showLoading) {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();
    }

    try {
      final response = await repository.fetchNotifications(limit: 20);
      _items = response.items;
      _unreadCount = response.unreadCount;
      _after = response.after;
      _hasNext = response.hasNext;
      _errorMessage = null;
      _isFromCache = false;

      // Lưu lại cache mới nhất
      await repository.saveToCache(userId, response);
    } on AppFailure catch (failure) {
      // Nếu đã có cache thì giữ nguyên dữ liệu trên màn hình, chỉ lưu message lỗi
      _errorMessage = failure.message;
    } catch (_) {
      _errorMessage = 'Không thể tải thông báo. Vui lòng thử lại sau.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    await fetchFirstPage(showLoading: false);
  }

  Future<void> loadMore() async {
    if (_isLoadingMore || !_hasNext || _after == null) return;

    _isLoadingMore = true;
    notifyListeners();

    try {
      final response = await repository.fetchNotifications(
        after: _after,
        limit: 20,
      );
      // Tránh duplicate theo notification_id
      final existingIds = _items.map((e) => e.notificationId).toSet();
      final newItems = response.items.where(
        (e) => !existingIds.contains(e.notificationId),
      );

      _items = [..._items, ...newItems];
      _after = response.after;
      _hasNext = response.hasNext;
    } catch (_) {
      // Giữ nguyên trạng thái tải thêm
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  Future<void> markAsRead(String notificationId) async {
    final index = _items.indexWhere((e) => e.notificationId == notificationId);
    if (index == -1 || _items[index].isRead) return;

    // Optimistic update trên UI
    final updated = _items[index].copyWith(readAt: DateTime.now());
    _items[index] = updated;
    if (_unreadCount > 0) _unreadCount--;
    notifyListeners();

    try {
      await repository.markAsRead(notificationId);
    } catch (_) {
      // Lỗi mạng khi mark read không ảnh hưởng trải nghiệm đọc
    }
  }

  Future<void> markAllAsRead() async {
    if (_isMarkingAllRead || _unreadCount == 0) return;

    _isMarkingAllRead = true;
    final now = DateTime.now();
    _items = _items.map((e) => e.copyWith(readAt: e.readAt ?? now)).toList();
    _unreadCount = 0;
    notifyListeners();

    try {
      await repository.markAllAsRead();
    } catch (_) {
      // Giữ optimistic update
    } finally {
      _isMarkingAllRead = false;
      notifyListeners();
    }
  }
}
