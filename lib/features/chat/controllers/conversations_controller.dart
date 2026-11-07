import 'package:flutter/foundation.dart';

import '../../../core/errors/app_failure.dart';
import '../data/chat_repository.dart';
import '../models/conversation_item.dart';

class ConversationsController extends ChangeNotifier {
  ConversationsController({
    required ChatRepository repository,
    required String userId,
  }) : _repository = repository,
       _userId = userId;

  final ChatRepository _repository;
  final String _userId;

  List<ConversationItem> _items = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _errorMessage;
  String? _after;
  bool _hasNext = false;

  List<ConversationItem> get items => List.unmodifiable(_items);
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  String? get errorMessage => _errorMessage;
  bool get hasNext => _hasNext;

  Future<void> initialize() async {
    // 1. Cache-first loading
    final cached = await _repository.loadCachedConversations(_userId);
    if (cached != null && cached.items.isNotEmpty) {
      _items = cached.items;
      _after = cached.after;
      _hasNext = cached.hasNext;
      notifyListeners();
    }

    // 2. Lấy dữ liệu mới nhất
    await fetchFirstPage(showLoading: _items.isEmpty);

    // 3. Lắng nghe tin nhắn mới qua STOMP WebSocket để cập nhật danh sách hội thoại
    _setupStompListener();
  }

  void _setupStompListener() {
    final stomp = _repository.stomp;
    if (stomp == null) return;
    stomp.connect();

    stomp.subscribe('/user/queue/messages', (payload) {
      final convId = payload['conversation_id']?.toString();
      final content = payload['content'] as String?;
      final msgId = payload['message_id']?.toString();
      if (convId == null) return;

      final index = _items.indexWhere((e) => e.conversationId == convId);
      if (index != -1) {
        final existing = _items[index];
        final updated = existing.copyWith(
          lastMessageContent: content ?? existing.lastMessageContent,
          lastMessageId: msgId ?? existing.lastMessageId,
          unreadCount: existing.unreadCount + 1,
          updatedAt: DateTime.now(),
        );
        _items.removeAt(index);
        _items.insert(0, updated);
        notifyListeners();
        _repository.saveCachedConversations(
          _userId,
          ConversationListResponse(
            items: _items,
            after: _after,
            hasNext: _hasNext,
          ),
        );
      } else {
        // Tải lại trang đầu để cập nhật hội thoại mới
        fetchFirstPage(showLoading: false);
      }
    });
  }

  Future<void> fetchFirstPage({bool showLoading = true}) async {
    if (showLoading) {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();
    }

    try {
      final response = await _repository.fetchConversations(limit: 20);
      _items = response.items;
      _after = response.after;
      _hasNext = response.hasNext;
      _errorMessage = null;

      await _repository.saveCachedConversations(_userId, response);
    } on AppFailure catch (failure) {
      _errorMessage = failure.message;
    } catch (_) {
      _errorMessage = 'Không thể tải danh sách cuộc trò chuyện.';
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
      final response = await _repository.fetchConversations(
        after: _after,
        limit: 20,
      );
      final existingIds = _items.map((e) => e.conversationId).toSet();
      final newItems = response.items.where(
        (e) => !existingIds.contains(e.conversationId),
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
}
