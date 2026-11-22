import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/errors/app_failure.dart';
import '../../core/network/api_client.dart';
import '../../core/storage/session_store.dart';
import '../posts/post_models.dart';

/// GET /search?type=POST returns search previews, not PostResponseDto.
/// Opening a result must fetch the protected post again to check its access.
class PostSearchResult {
  const PostSearchResult(this.id, this.content, this.author, this.createdAt);
  final int id;
  final String content;
  final PostAuthor author;
  final DateTime? createdAt;

  factory PostSearchResult.fromJson(Object? raw) {
    final item = object(raw);
    if (item['type'] != 'POST') throw AppFailure.invalidData;
    final post = object(item['post']);
    return PostSearchResult(
      identifier(post['post_id']),
      textValue(post['content']),
      PostAuthor(
        post['author_id'] == null ? null : identifier(post['author_id']),
        textValue(post['author_name']),
        textValue(post['author_avatar_url']),
      ),
      DateTime.tryParse(textValue(post['created_at'])),
    );
  }
}

class PostSearchRepository {
  PostSearchRepository(this.api);
  final ApiClient api;

  Future<CursorPage<PostSearchResult>> find(
    String query, {
    int? after,
    required CancelToken cancel,
  }) {
    if (query.trim().isEmpty) {
      throw const AppFailure(
        FailureKind.rejected,
        'Nhập từ khóa tìm bài viết.',
      );
    }
    return api.get(
      'search',
      query: {
        'query': query.trim(),
        'type': 'POST',
        'limit': 20,
        'after': ?after,
      },
      cancelToken: cancel,
      decode: (v) => CursorPage.fromJson(v, PostSearchResult.fromJson),
    );
  }
}

class PostSearchController extends ChangeNotifier {
  PostSearchController({required this.repository, required this.session})
    : _owner = session.tokens {
    session.addListener(_sessionChanged);
  }
  final PostSearchRepository repository;
  final SessionStore session;
  final Object? _owner;
  final List<PostSearchResult> _items = [];
  List<PostSearchResult> get items => List.unmodifiable(_items);
  String _query = '';
  String get query => _query;
  AppFailure? failure;
  bool loading = false, loadingMore = false, hasNext = false, searched = false;
  int? _after;
  int _generation = 0;
  Timer? _timer;
  CancelToken? _cancel;
  bool _disposed = false, _invalidated = false;
  bool get active => !_disposed && !_invalidated && _owner != null;

  void _sessionChanged() {
    // Token rotation for the same account is fine; logout/switch invalidates
    // this controller permanently, even when the same account signs in again.
    final original = _owner;
    if (original is! SessionTokens ||
        session.tokens?.userId != original.userId) {
      _invalidated = true;
      ++_generation;
      _cancel?.cancel();
      _timer?.cancel();
      _items.clear();
    }
  }

  void updateQuery(String value) {
    if (!active || value.trim() == _query) return;
    _query = value.trim();
    _timer?.cancel();
    _cancel?.cancel();
    ++_generation;
    _items.clear();
    loading = loadingMore = hasNext = searched = false;
    failure = null;
    notifyListeners();
    if (_query.isNotEmpty) {
      _timer = Timer(
        const Duration(milliseconds: 350),
        () => unawaited(search()),
      );
    }
  }

  Future<void> search() async {
    _timer?.cancel();
    if (!active || _query.isEmpty || loading) return;
    _cancel?.cancel();
    final generation = ++_generation;
    final cancel = _cancel = CancelToken();
    loading = true;
    loadingMore = false;
    failure = null;
    notifyListeners();
    try {
      final page = await repository.find(_query, cancel: cancel);
      if (!active || generation != _generation) return;
      _items
        ..clear()
        ..addAll(page.items);
      _after = page.after;
      hasNext = page.hasNext;
    } on AppFailure catch (e) {
      if (!active || generation != _generation) return;
      failure = e;
      if (accessRevoked(e)) _items.clear();
    } catch (_) {
      if (active && generation == _generation) failure = AppFailure.invalidData;
    } finally {
      if (active && generation == _generation) {
        loading = false;
        searched = true;
        notifyListeners();
      }
    }
  }

  Future<void> more() async {
    if (!active || loading || loadingMore || !hasNext || _items.length >= 200) {
      return;
    }
    final generation = _generation, after = _after;
    final cancel = _cancel = CancelToken();
    loadingMore = true;
    failure = null;
    notifyListeners();
    try {
      final page = await repository.find(_query, after: after, cancel: cancel);
      if (!active || generation != _generation) return;
      final ids = _items.map((e) => e.id).toSet();
      _items.addAll(page.items.where((e) => ids.add(e.id)));
      if (_items.length > 200) _items.removeRange(200, _items.length);
      _after = page.after;
      hasNext = page.hasNext && page.after != after && _items.length < 200;
    } on AppFailure catch (e) {
      if (!active || generation != _generation) return;
      failure = e;
      if (accessRevoked(e)) {
        _items.clear();
        hasNext = false;
      }
    } catch (_) {
      if (active && generation == _generation) failure = AppFailure.invalidData;
    } finally {
      if (active && generation == _generation) {
        loadingMore = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    session.removeListener(_sessionChanged);
    _timer?.cancel();
    _cancel?.cancel();
    super.dispose();
  }
}
