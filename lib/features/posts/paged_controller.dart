import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/errors/app_failure.dart';
import '../../core/storage/json_cache.dart';
import '../../core/storage/session_store.dart';
import 'post_models.dart';

/// Serializes refresh/load-more, bounds memory/disk, and owns one account only.
class PagedController<T> extends ChangeNotifier {
  PagedController({
    required this.session,
    required this.fetch,
    required this.id,
    this.cache,
    this.resource,
    this.encode,
    this.decode,
    this.cacheable,
  }) : userId = session.tokens!.userId {
    session.addListener(_sessionChanged);
  }
  final SessionStore session;
  final String userId;
  final Future<CursorPage<T>> Function(int?, CancelToken) fetch;
  final Object Function(T) id;
  final JsonCache? cache;
  final String? resource;
  final Object? Function(T)? encode;
  final T Function(Object?)? decode;
  final bool Function(T)? cacheable;
  List<T> items = [];
  bool busy = false, initialized = false, hasNext = false, cached = false;
  int? after;
  DateTime? savedAt;
  AppFailure? failure;
  String? storageWarning;
  final CancelToken cancel = CancelToken();
  bool _disposed = false, _invalid = false;
  Future<void> _writes = Future.value();
  int _revision = 0;
  int _accessRevision = 0;
  final _changes = <Object, (int, T)>{};
  final _removed = <Object>{};
  final _seenCursors = <int>{};
  bool get active =>
      !_disposed && !_invalid && session.tokens?.userId == userId;
  void _sessionChanged() {
    if (session.tokens?.userId != userId) {
      _invalid = true;
      items = [];
      cancel.cancel();
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> start() async {
    if (initialized || busy || !active) return;
    busy = true;
    if (cache != null) {
      try {
        final entry = await cache!.read(userId: userId, resource: resource!);
        if (!active) return;
        if (entry != null) {
          items = (entry.data as List).map(decode!).toList();
          cached = true;
          savedAt = entry.savedAt;
        }
      } catch (_) {
        storageWarning = 'Không đọc được bản lưu. Đang thử tải dữ liệu mới.';
      }
    }
    if (!active) return;
    busy = false;
    initialized = true;
    notifyListeners();
    await refresh();
  }

  Future<void> refresh() => _load(false);
  Future<void> more() => _load(true);
  Future<void> _load(bool more) async {
    if (!active || busy || (more && (!hasNext || items.length >= 200))) return;
    busy = true;
    failure = null;
    final cursor = more ? after : null;
    final revision = _revision;
    final accessRevision = _accessRevision;
    notifyListeners();
    try {
      final page = await fetch(cursor, cancel);
      if (!active || accessRevision != _accessRevision) return;
      if (more && page.hasNext && _seenCursors.contains(page.after)) {
        hasNext = false;
        throw AppFailure.invalidData;
      }
      final merged = <Object, T>{
        for (final item in more ? items : <T>[]) id(item): item,
      };
      for (final item in page.items) {
        merged[id(item)] = item;
      }
      for (final change in _changes.entries) {
        if (change.value.$1 > revision && merged.containsKey(change.key)) {
          merged[change.key] = change.value.$2;
        }
      }
      merged.removeWhere((key, _) => _removed.contains(key));
      _changes.removeWhere(
        (key, change) => change.$1 <= revision || !merged.containsKey(key),
      );
      items = merged.values.take(200).toList();
      after = page.after;
      if (!more) _seenCursors.clear();
      if (page.hasNext && page.after != null) _seenCursors.add(page.after!);
      hasNext = page.hasNext && items.length < 200;
      cached = false;
      savedAt = DateTime.now();
      await persist();
    } on AppFailure catch (error) {
      if (!active) return;
      failure = error;
      if (accessRevoked(error)) {
        items = [];
        hasNext = false;
        await clearCache();
      }
    } catch (_) {
      if (active) failure = AppFailure.invalidData;
    } finally {
      if (active) {
        busy = false;
        initialized = true;
        notifyListeners();
      }
    }
  }

  void replaceWhere(bool Function(T) matches, T Function(T) replace) {
    if (!active) return;
    final revision = ++_revision;
    items = items.map((item) {
      if (!matches(item)) return item;
      final next = replace(item);
      _changes[id(item)] = (revision, next);
      return next;
    }).toList();
    unawaited(persist());
    notifyListeners();
  }

  void removeWhere(bool Function(T) matches) {
    if (!active || !items.any(matches)) return;
    _removed.addAll(items.where(matches).map(id));
    items = items.where((item) => !matches(item)).toList();
    unawaited(persist());
    notifyListeners();
  }

  Future<void> persist() {
    if (cache == null || !active) return Future.value();
    final data = items
        .where((e) => cacheable?.call(e) ?? true)
        .take(40)
        .map(encode!)
        .toList();
    while (data.isNotEmpty &&
        utf8.encode(jsonEncode(data)).length > cache!.maxBytes - 1024) {
      data.removeLast();
    }
    _writes = _writes.then((_) async {
      if (!active) return;
      try {
        await cache!.write(userId: userId, resource: resource!, data: data);
      } catch (_) {
        storageWarning =
            'Không lưu được dữ liệu trên máy. Nội dung mới vẫn được hiển thị.';
      }
    });
    return _writes;
  }

  Future<void> clearCache() async {
    if (cache == null) return;
    await _writes;
    try {
      await cache!.remove(userId: userId, resource: resource!);
    } catch (_) {
      storageWarning = 'Không xóa được bản lưu trên máy.';
    }
  }

  Future<void> invalidate(AppFailure error) async {
    if (!active) return;
    ++_accessRevision;
    items = [];
    hasNext = false;
    failure = error;
    await clearCache();
    if (active) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    cancel.cancel();
    session.removeListener(_sessionChanged);
    super.dispose();
  }
}
