import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/errors/app_failure.dart';
import '../data/chat_repository.dart';
import '../data/chat_changes.dart';
import '../models/chat_event.dart';
import '../models/conversation_item.dart';

class ConversationsController extends ChangeNotifier {
  ConversationsController({
    required this.repository,
    required this.userId,
    bool Function()? isCurrent,
  }) : _isCurrent = isCurrent ?? (() => true);
  final ChatRepository repository;
  final String userId;
  final bool Function() _isCurrent;
  List<ConversationItem> _items = [];
  List<ChatPartnerSummary> _friends = [];
  bool _isLoading = false,
      _isLoadingMore = false,
      _disposed = false,
      _hasNext = false;
  int _generation = 0;
  Timer? _eventRefresh;
  StreamSubscription<ChatMessageRemoval>? _removals;
  final _removedPreviews = <String>{};
  String? _errorMessage, _after, _cursor;
  bool get _active => !_disposed && _isCurrent();
  List<ConversationItem> get items => List.unmodifiable(_items);
  List<ChatPartnerSummary> get friends => List.unmodifiable(_friends);
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  String? get errorMessage => _errorMessage;
  bool get hasNext => _hasNext;
  void _notify() {
    if (_active) notifyListeners();
  }

  Future<void> initialize() async {
    _removals ??= ChatChanges.removals.listen((event) {
      if (!_active || event.userId != userId) return;
      _removedPreviews.add(event.messageId);
      while (_removedPreviews.length > 200) {
        _removedPreviews.remove(_removedPreviews.first);
      }
      _items = _items.map(_safePreview).toList();
      _notify();
      unawaited(_savePreviewChanges());
    });
    try {
      final cached = await repository.loadCachedConversations(userId);
      if (!_active) return;
      if (cached != null) {
        _items = cached.items
            .where((e) => e.type == 'DIRECT')
            .map(_safePreview)
            .toList();
        _notify();
      }
    } catch (_) {
      /* Fetch even if storage fails. */
    }
    if (!_active) return;
    repository.stomp?.subscribe('/user/queue/messages', (payload) {
      if (!_active) return;
      final event = ChatEvent.parse(payload);
      if (event.type == ChatEventType.unknown ||
          event.type == ChatEventType.typing) {
        return;
      }
      // Fetch authoritative unread counts; own events/receipts are not unread messages.
      _eventRefresh?.cancel();
      _eventRefresh = Timer(const Duration(milliseconds: 300), () {
        if (_active) unawaited(fetchFirstPage(showLoading: false));
      });
    });
    await refresh();
  }

  Future<void> _loadFriends() async {
    try {
      final list = await repository.fetchFriendsForChat();
      if (_active) {
        _friends = list.where((e) => e.userId != userId).toList();
        _notify();
      }
    } catch (_) {
      /* Does not invalidate cached conversations. */
    }
  }

  Future<void> fetchFirstPage({bool showLoading = true}) async {
    if (!_active || _isLoading) return;
    final generation = ++_generation;
    _isLoading = true;
    _isLoadingMore = false;
    _errorMessage = null;
    _notify();
    try {
      final page = await repository.fetchConversations(limit: 20);
      if (!_active || generation != _generation) return;
      _items = page.items
          .where((e) => e.type == 'DIRECT')
          .map(_safePreview)
          .toList();
      _after = page.after;
      _cursor = page.nextCursor;
      _hasNext = page.hasNext;
      try {
        await repository.saveCachedConversations(userId, page);
      } catch (_) {
        if (_active) _errorMessage = 'Không lưu được hội thoại trên máy.';
      }
    } on AppFailure catch (e) {
      if (!_active || generation != _generation) return;
      _errorMessage = e.message;
      if (const [
        FailureKind.unauthorized,
        FailureKind.forbidden,
        FailureKind.notFound,
      ].contains(e.kind)) {
        _items = [];
        _hasNext = false;
        try {
          await repository.clearCachedConversations(userId);
        } catch (_) {}
      }
    } catch (_) {
      if (_active) _errorMessage = 'Không thể tải danh sách cuộc trò chuyện.';
    } finally {
      if (_active && generation == _generation) {
        _isLoading = false;
        _notify();
      }
    }
  }

  Future<void> refresh() async {
    if (!_active) return;
    await Future.wait([fetchFirstPage(showLoading: false), _loadFriends()]);
    if (_active) await repository.stomp?.connect();
  }

  Future<void> loadMore() async {
    if (!_active ||
        _isLoading ||
        _isLoadingMore ||
        !_hasNext ||
        (_after == null && _cursor == null) ||
        _items.length >= 200) {
      return;
    }
    final generation = _generation, after = _after, cursor = _cursor;
    _isLoadingMore = true;
    _notify();
    try {
      final page = await repository.fetchConversations(
        after: cursor == null ? after : null,
        cursor: cursor,
        limit: 20,
      );
      if (!_active || generation != _generation) return;
      final ids = _items.map((e) => e.conversationId).toSet();
      _items.addAll(
        page.items
            .where((e) => e.type == 'DIRECT' && ids.add(e.conversationId))
            .map(_safePreview),
      );
      _after = page.after;
      _cursor = page.nextCursor;
      _hasNext =
          page.hasNext &&
          (page.nextCursor != null
              ? page.nextCursor != cursor
              : page.after != after) &&
          _items.length < 200;
      try {
        await repository.saveCachedConversations(
          userId,
          ConversationListResponse(
            items: _items,
            after: _after,
            nextCursor: _cursor,
            hasNext: _hasNext,
          ),
        );
      } catch (_) {
        if (_active) _errorMessage = 'Không lưu được hội thoại trên máy.';
      }
    } on AppFailure catch (e) {
      if (!_active || generation != _generation) return;
      _errorMessage = e.message;
      if (const [
        FailureKind.unauthorized,
        FailureKind.forbidden,
        FailureKind.notFound,
      ].contains(e.kind)) {
        _items = [];
        _hasNext = false;
        try {
          await repository.clearCachedConversations(userId);
        } catch (_) {}
      }
    } catch (_) {
      if (_active) _errorMessage = 'Không thể tải thêm hội thoại.';
    } finally {
      if (_active && generation == _generation) {
        _isLoadingMore = false;
        _notify();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _eventRefresh?.cancel();
    unawaited(_removals?.cancel());
    repository.stomp?.unsubscribe('/user/queue/messages');
    repository.stomp?.disconnect();
    super.dispose();
  }

  ConversationItem _safePreview(ConversationItem item) =>
      _removedPreviews.contains(item.lastMessageId)
      ? item.copyWith(lastMessageContent: 'Tin nhắn không còn hiển thị.')
      : item;

  Future<void> _savePreviewChanges() async {
    try {
      if (!_active) return;
      await repository.saveCachedConversations(
        userId,
        ConversationListResponse(
          items: _items,
          after: _after,
          nextCursor: _cursor,
          hasNext: _hasNext,
        ),
      );
    } catch (_) {
      // The confirmed server mutation still succeeds when a cache write fails.
    }
  }
}
