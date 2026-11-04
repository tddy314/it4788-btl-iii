import 'package:flutter/foundation.dart';

import '../../core/errors/app_failure.dart';
import '../../core/storage/session_store.dart';
import 'social_models.dart';

/// Feature-local invalidation; other features can listen without changing core.
class SocialChanges extends ChangeNotifier {
  SocialChanges(this.session) : _userId = session.tokens?.userId {
    session.addListener(_sessionChanged);
  }
  final SessionStore session;
  String? _userId;
  int _epoch = 0;
  int revision = 0;
  bool busy = false;
  bool lastMutationConfirmed = false;
  bool _disposed = false;
  String? lastBlockedUserId;
  String? get userId => _userId;

  void _sessionChanged() {
    final next = session.tokens?.userId;
    if (next == _userId) return; // Token rotation is not an account switch.
    _userId = next;
    _epoch++;
    busy = false;
    lastMutationConfirmed = false;
    lastBlockedUserId = null;
    invalidate();
  }

  SocialLease lease() {
    final id = _userId;
    if (id == null) throw AppFailure.unauthorized;
    return SocialLease(this, id, _epoch);
  }

  void invalidate({String? blockedUserId}) {
    lastBlockedUserId = blockedUserId;
    revision++;
    if (!_disposed) notifyListeners();
  }

  Future<bool> mutate(
    Future<void> Function() operation, {
    String? blockedUserId,
  }) async {
    if (busy) return false;
    final guard = lease();
    busy = true;
    lastMutationConfirmed = false;
    notifyListeners();
    try {
      await operation();
      guard.check();
      lastMutationConfirmed = true;
      return true;
    } finally {
      if (guard.active) {
        busy = false;
        // Also reconcile failed/ambiguous writes. Never replay the write.
        invalidate(blockedUserId: blockedUserId);
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    session.removeListener(_sessionChanged);
    super.dispose();
  }
}

class SocialLease {
  SocialLease(this.owner, this.userId, this.epoch);
  final SocialChanges owner;
  final String userId;
  final int epoch;
  bool get active =>
      !owner._disposed && owner._epoch == epoch && owner.userId == userId;
  void check() {
    if (!active) throw AppFailure.unauthorized;
  }
}

/// One request at a time; refresh and append cannot overwrite each other.
/// Keeps existing content on operational failures; no persistent social graph.
class SocialListController<T> extends ChangeNotifier {
  SocialListController({
    required this.lease,
    required this.fetch,
    required this.idOf,
  });
  final SocialLease lease;
  final Future<SocialPage<T>> Function(int? after) fetch;
  final String Function(T) idOf;
  List<T> items = [];
  bool loading = false;
  bool loaded = false;
  bool hasNext = false;
  int? after;
  AppFailure? failure;
  bool _disposed = false;
  int _generation = 0;
  bool get active => !_disposed && lease.active;

  Future<void> load({bool more = false}) async {
    if (!active || loading || (more && (!loaded || !hasNext))) return;
    final generation = ++_generation;
    bool current() => active && generation == _generation;
    loading = true;
    failure = null;
    notifyListeners();
    try {
      final page = await fetch(more ? after : null);
      if (!current()) return;
      if (more && page.hasNext && page.after == after) {
        // A non-advancing cursor must not create an infinite load-more loop.
        hasNext = false;
        throw AppFailure.invalidData;
      }
      final merged = <String, T>{
        if (more)
          for (final item in items) idOf(item): item,
        for (final item in page.items) idOf(item): item,
      };
      items = merged.values.toList();
      after = page.after;
      hasNext = page.hasNext;
      loaded = true;
    } on AppFailure catch (error) {
      if (!current()) return;
      failure = error;
      if (!error.canUseCache &&
          (error.kind == FailureKind.unauthorized ||
              error.kind == FailureKind.forbidden ||
              error.kind == FailureKind.notFound)) {
        items = [];
        hasNext = false;
      }
    } catch (_) {
      if (current()) failure = AppFailure.invalidData;
    } finally {
      if (current()) {
        loading = false;
        notifyListeners();
      }
    }
  }

  void clear({bool keepItems = false}) {
    _generation++;
    loading = false;
    failure = null;
    if (!keepItems) items = [];
    loaded = false;
    hasNext = false;
    after = null;
    if (active) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
