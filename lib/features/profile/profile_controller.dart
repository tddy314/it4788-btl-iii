import 'package:flutter/foundation.dart';

import '../../core/errors/app_failure.dart';
import '../../core/storage/json_cache.dart';
import '../relationships/social_models.dart';
import 'profile_models.dart';
import 'profile_repository.dart';

class ProfileController extends ChangeNotifier {
  ProfileController({
    required this.repository,
    required this.cache,
    required this.id,
  });
  final ProfileRepository repository;
  final JsonCache cache;
  final String id;
  UserProfile? profile;
  RelationshipStats? stats;
  AppFailure? failure;
  AppFailure? statsFailure;
  bool loading = false;
  bool fromCache = false;
  bool _disposed = false;
  int _generation = 0;
  bool get own => id == repository.social.lease.userId;
  bool get active => !_disposed && repository.social.lease.active;
  bool get writable => active && !loading && !fromCache && failure == null;
  static const cacheKey = 'profile.public.v1';

  Future<void> load() async {
    if (loading || !active) return;
    final generation = ++_generation;
    bool current() => active && generation == _generation;
    loading = true;
    failure = null;
    statsFailure = null;
    stats = null; // Old permissions must not enable buttons during refresh.
    notifyListeners();
    if (own && profile == null) {
      try {
        final entry = await cache.read(userId: id, resource: cacheKey);
        if (!current()) return;
        if (entry != null) {
          final saved = UserProfile.fromJson(entry.data);
          if (saved.id == id) {
            profile = saved;
            fromCache = true;
            notifyListeners();
          }
        }
      } catch (_) {
        /* Bad cache must not prevent an API read. */
      }
    }
    try {
      final fresh = await repository.profile(id);
      if (!current()) return;
      profile = fresh;
      fromCache = false;
      if (own) {
        try {
          await cache.write(
            userId: id,
            resource: cacheKey,
            data: fresh.publicCache(),
          );
        } catch (_) {
          /* Cache failure does not turn a successful read into failure. */
        }
      }
      if (!current()) return;
      try {
        final freshStats = await repository.social.stats(id);
        if (!current()) return;
        stats = freshStats;
        if (!own && freshStats.blocked != false) {
          profile = null;
          failure = const AppFailure(
            FailureKind.forbidden,
            'Hồ sơ bị hạn chế do quan hệ chặn hoặc chưa xác định được quyền truy cập.',
          );
        }
      } on AppFailure catch (error) {
        if (!current()) return;
        statsFailure = error;
        if (!own &&
            (error.kind == FailureKind.forbidden ||
                error.kind == FailureKind.notFound ||
                error.kind == FailureKind.unauthorized)) {
          profile = null;
          failure = error;
        }
      }
    } on AppFailure catch (error) {
      if (!current()) return;
      failure = error;
      if (!error.canUseCache) {
        profile = null;
        if (own) {
          try {
            await cache.remove(userId: id, resource: cacheKey);
          } catch (_) {}
        }
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

  void invalidate({bool hide = false}) {
    _generation++;
    loading = false;
    if (hide) profile = null;
    stats = null;
    if (active) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
