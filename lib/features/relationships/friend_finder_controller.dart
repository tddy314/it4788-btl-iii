import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/errors/app_failure.dart';
import 'friend_finder_repository.dart';
import 'social_models.dart';

class FriendFinderController extends ChangeNotifier {
  FriendFinderController({
    required this.repository,
    this.debounce = const Duration(milliseconds: 350),
  }) {
    _revision = repository.lease.owner.revision;
    repository.lease.owner.addListener(_relationshipsChanged);
  }
  final FriendFinderRepository repository;
  final Duration debounce;
  String query = '';
  List<SocialPerson> people = [];
  AppFailure? failure;
  bool loading = false;
  bool loaded = false;
  bool hasNext = false;
  int? after;
  int _generation = 0;
  int _revision = 0;
  bool _disposed = false;
  Timer? _timer;
  CancelToken? _cancel;
  bool get active => !_disposed && repository.active;
  String? get validation => validateFriendQuery(query);

  void setQuery(String raw) {
    if (!active) return;
    final next = raw.trim();
    if (query == next) return;
    query = next;
    _reset();
    if (validation == null) {
      _timer = Timer(debounce, () => unawaited(refresh()));
    }
  }

  void _reset() {
    _timer?.cancel();
    _cancel?.cancel();
    _generation++;
    loading = false;
    loaded = false;
    failure = null;
    people = [];
    hasNext = false;
    after = null;
    if (active) notifyListeners();
  }

  void _relationshipsChanged() {
    final changes = repository.lease.owner;
    if (!active || _revision == changes.revision) return;
    _revision = changes.revision;
    _reset(); // Recheck visibility after block/relationship changes.
    if (validation == null) unawaited(refresh());
  }

  Future<void> refresh() {
    _timer?.cancel();
    return _load();
  }

  Future<void> loadMore() => _load(more: true);

  Future<void> _load({bool more = false}) async {
    if (!active || loading || validation != null || (more && !hasNext)) return;
    final generation = ++_generation;
    bool current() => active && generation == _generation;
    final token = _cancel = CancelToken();
    loading = true;
    failure = null;
    notifyListeners();
    try {
      final page = await repository.find(
        query,
        offset: more ? after! : 0,
        cancelToken: token,
      );
      if (!current()) return;
      people = <String, SocialPerson>{
        if (more)
          for (final person in people) person.id: person,
        for (final person in page.items) person.id: person,
      }.values.toList();
      after = page.after;
      hasNext = page.hasNext;
      loaded = true;
    } on AppFailure catch (error) {
      if (!current()) return;
      failure = error;
      if (more && error.kind == FailureKind.invalidData) hasNext = false;
      if ([
        FailureKind.unauthorized,
        FailureKind.forbidden,
        FailureKind.notFound,
      ].contains(error.kind)) {
        people = [];
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

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _cancel?.cancel();
    repository.lease.owner.removeListener(_relationshipsChanged);
    repository.dispose();
    super.dispose();
  }
}
