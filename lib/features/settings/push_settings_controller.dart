import 'package:flutter/foundation.dart';

import '../../core/errors/app_failure.dart';
import 'data/push_settings_repository.dart';
import 'models/push_settings.dart';

class PushSettingsController extends ChangeNotifier {
  PushSettingsController(this.repository, this.userId, this.isCurrent);
  final PushSettingsRepository repository;
  final String userId;
  final bool Function() isCurrent;
  PushSettings? settings;
  String? message;
  bool loading = false,
      saving = false,
      fromCache = false,
      uncertain = false,
      _disposed = false;
  bool get active => !_disposed && isCurrent();
  bool get writable =>
      active &&
      settings != null &&
      !loading &&
      !saving &&
      !fromCache &&
      !uncertain;
  void _notify() {
    if (active) notifyListeners();
  }

  Future<void> load() async {
    if (!active || loading || saving) return;
    loading = true;
    message = null;
    _notify();
    try {
      if (settings == null) {
        try {
          final cached = await repository.loadCached(userId);
          if (!active) return;
          if (cached != null) {
            settings = cached;
            fromCache = true;
            _notify();
          }
        } catch (_) {}
      }
      final fresh = await repository.fetchSettings();
      if (!active) return;
      settings = fresh;
      fromCache = false;
      uncertain = false;
      await _cache(fresh);
    } on AppFailure catch (e) {
      if (active) {
        message = e.message;
        if (!e.canUseCache) settings = null;
      }
    } catch (_) {
      if (active) message = 'Không thể tải cài đặt thông báo.';
    } finally {
      loading = false;
      _notify();
    }
  }

  Future<void> update(PushSettings value) async {
    if (!writable) return;
    saving = true;
    message = null;
    _notify();
    try {
      final confirmed = await repository.updateSettings(value);
      if (!active) return;
      settings = confirmed;
      await _cache(confirmed);
    } on AppFailure catch (e) {
      if (active) {
        message = e.message;
        uncertain = const [
          FailureKind.offline,
          FailureKind.timeout,
          FailureKind.server,
          FailureKind.unknown,
        ].contains(e.kind);
      }
    } catch (_) {
      if (active) {
        uncertain = true;
        message = 'Chưa xác định được kết quả. Hãy tải lại cài đặt trước khi thay đổi tiếp.';
      }
    } finally {
      saving = false;
      _notify();
    }
    if (active && uncertain) await load(); // GET only; no automatic PUT replay.
  }

  Future<void> _cache(PushSettings value) async {
    if (!active) return;
    try {
      await repository.saveToCache(userId, value);
    } catch (_) {
      if (active) {
        message = 'Cài đặt đã được cập nhật nhưng chưa lưu được trên máy.';
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
