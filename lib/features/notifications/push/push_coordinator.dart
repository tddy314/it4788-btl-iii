import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../../../app/app_dependencies.dart';
import '../../../core/network/connection_monitor.dart';
import '../../settings/data/push_settings_repository.dart';
import '../models/notification_item.dart';
import '../presentation/widgets/notification_deep_link_handler.dart';
import 'notification_presenter.dart';
import 'push_config.dart';

@pragma('vm:entry-point')
Future<void> sqbBackgroundMessage(RemoteMessage message) async {
  if (!PushConfig.configured) return;
  DartPluginRegistrant.ensureInitialized();
  try {
    await Firebase.initializeApp(options: PushConfig.options);
    // OS already shows a notification payload in background. Only data messages
    // are rendered here, so a single message cannot create two notifications.
    if (message.notification == null) {
      final presenter = NotificationPresenter();
      await presenter.initialize();
      await presenter.show(message);
    }
  } catch (_) {
    /* No tokens/content in logs; app startup is independent of push. */
  }
}

class PushScope extends InheritedNotifier<PushCoordinator> {
  const PushScope({
    super.key,
    required PushCoordinator controller,
    required super.child,
  }) : super(notifier: controller);
  static PushCoordinator? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PushScope>()?.notifier;
}

class PushCoordinator extends ChangeNotifier {
  PushCoordinator(this.dependencies) {
    _userId = dependencies.session.tokens?.userId;
    dependencies.session.addListener(_sessionChanged);
  }
  final AppDependencies dependencies;
  GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  final presenter = NotificationPresenter();
  final _subscriptions = <StreamSubscription<dynamic>>[];
  String? _userId, _fid, _attemptedFor, _deliveredTap;
  Map<String, dynamic>? _pending;
  bool _disposed = false, _initialized = false, busy = false;
  Future<void>? _starting;
  int _epoch = 0;
  Future<void> _sdkWork = Future.value();
  Future<void> _sdk(Future<void> Function() operation) {
    final work = _sdkWork.then((_) => operation());
    _sdkWork = work.catchError((Object _) {});
    return work;
  }

  String status = PushConfig.configured
      ? 'Đang kiểm tra thông báo đẩy…'
      : 'Thông báo đẩy chưa được cấu hình cho bản cài đặt này.';
  bool get configured => PushConfig.configured;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool _current(int epoch) => !_disposed && epoch == _epoch;
  Future<void> start() {
    if (!configured || _initialized || _disposed) return Future.value();
    return _starting ??= _start().whenComplete(() => _starting = null);
  }

  Future<void> _start() async {
    try {
      await Firebase.initializeApp(options: PushConfig.options)
          .timeout(const Duration(seconds: 8));
      if (_disposed) return;
      FirebaseMessaging.onBackgroundMessage(sqbBackgroundMessage);
      await presenter.initialize(onTap: _tap);
      if (_disposed) return;
      _initialized = true;
      _subscriptions.add(
        FirebaseMessaging.instance.onRegistered.listen(
          (fid) {
            if (_disposed) return;
            _fid = fid;
            unawaited(_sync());
          },
          onError: (Object _) {
            status = 'Chưa đăng ký được thiết bị nhận thông báo.';
            _notify();
          },
        ),
      );
      _subscriptions.add(
        FirebaseMessaging.onMessage.listen((message) {
          unawaited(
            presenter.show(message).catchError((Object _) {
              status = 'Không hiển thị được thông báo trên thiết bị.';
              _notify();
            }),
          );
        }),
      );
      _subscriptions.add(
        FirebaseMessaging.onMessageOpenedApp.listen(_remoteTap),
      );
      final local = await presenter.plugin.getNotificationAppLaunchDetails();
      if (_disposed) return;
      if (local?.didNotificationLaunchApp == true) {
        _tap(local?.notificationResponse?.payload);
      }
      final remote = await FirebaseMessaging.instance.getInitialMessage();
      if (_disposed) return;
      if (remote != null) _remoteTap(remote);
      await _registerIfPermitted();
    } catch (_) {
      if (!_disposed) {
        status = 'Chưa khởi tạo được nhận thông báo. Kiểm tra cấu hình bản cài đặt và kết nối mạng.';
        _notify();
      }
    }
  }

  Future<void> _registerIfPermitted() async {
    if (!_initialized || _disposed || _userId == null) return;
    final epoch = _epoch;
    final permission = await FirebaseMessaging.instance
        .getNotificationSettings();
    if (!_current(epoch)) return;
    if (permission.authorizationStatus != AuthorizationStatus.authorized) {
      status = 'Chưa cấp quyền thông báo. Bạn có thể cấp quyền tại đây.';
      _notify();
      return;
    }
    await _sdk(() async {
      if (!_current(epoch)) return;
      await FirebaseMessaging.instance.register().timeout(
        const Duration(seconds: 10),
      );
    });
    _notify();
  }

  Future<void> enable() async {
    if (busy || _disposed || !configured) return;
    busy = true;
    _notify();
    try {
      if (!_initialized) await start();
      if (!_initialized || _disposed) return;
      final permission = await FirebaseMessaging.instance.requestPermission();
      if (_disposed) return;
      if (permission.authorizationStatus == AuthorizationStatus.authorized) {
        await _registerIfPermitted();
      } else {
        status = 'Quyền thông báo chưa được cấp. Bạn có thể bật trong Cài đặt thiết bị.';
      }
    } catch (_) {
      if (!_disposed) status = 'Chưa kết nối được dịch vụ nhận thông báo.';
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> _sync() async {
    final userId = _userId, fid = _fid, epoch = _epoch;
    if (!_initialized || userId == null || fid == null || !_current(epoch)) {
      return;
    }
    final key = '$userId/$fid';
    if (dependencies.connection.status == ConnectionStatus.offline) {
      status = 'Đang mất mạng. Kết nối lại rồi nhấn kiểm tra thông báo để đăng ký thiết bị.';
      _notify();
      return;
    }
    if (_attemptedFor == key) return;
    _attemptedFor = key; // An ambiguous POST is never replayed automatically.
    try {
      await PushSettingsRepository(
        api: dependencies.api,
        cache: dependencies.cache,
      ).registerDevice(fid: fid);
      if (_current(epoch)) status = 'Thiết bị đã được đăng ký nhận thông báo.';
    } catch (_) {
      if (_current(epoch)) status = 'Chưa xác nhận được đăng ký thiết bị trên máy chủ. Không tự gửi lại yêu cầu.';
    }
    _notify();
  }

  void _sessionChanged() {
    final next = dependencies.session.tokens?.userId;
    if (next == _userId) return;
    _userId = next;
    ++_epoch;
    _attemptedFor = null;
    _deliveredTap = null;
    navigatorKey =
        GlobalKey<
          NavigatorState
        >(); // Never reuse another account's navigation stack.
    if (_pending?['account'] != null &&
        next != null &&
        _pending?['account'] != next) {
      _pending = null;
    }
    unawaited(presenter.plugin.cancelAll().catchError((Object _) {}));
    if (_initialized) {
      if (next == null) {
        unawaited(
          _sdk(
            () => FirebaseMessaging.instance.unregister().timeout(
              const Duration(seconds: 10),
            ),
          ).catchError((Object _) {}),
        );
      } else {
        unawaited(
          _registerIfPermitted().catchError((Object _) {
            if (!_disposed) {
              status = 'Chưa đăng ký được thông báo.';
              _notify();
            }
          }),
        );
      }
    }
    _notify();
    _drainTap();
  }

  Future<void> beforeLogout() async {
    if (!_initialized || _fid == null) return;
    try {
      await PushSettingsRepository(
        api: dependencies.api,
        cache: dependencies.cache,
      ).unregisterDevice(_fid!);
    } finally {
      await _sdk(
        () => FirebaseMessaging.instance.unregister().timeout(
          const Duration(seconds: 10),
        ),
      );
      await presenter.plugin.cancelAll();
    }
  }

  void _remoteTap(RemoteMessage message) {
    final id = message.data['recipient_user_id']?.toString() ?? _userId;
    if (id == null) return;
    final target = NotificationPresenter.target(message.data, id);
    if (target != null) {
      _tap(
        jsonEncode({
          ...target,
          'notification':
              message.messageId ??
              NotificationPresenter.stableId(jsonEncode(message.data))
                  .toString(),
        }),
      );
    }
  }

  void _tap(String? payload) {
    if (_disposed || payload == null || payload == _deliveredTap) return;
    try {
      final data = jsonDecode(payload);
      if (data is! Map<String, dynamic> || data['account'] is! String) return;
      _pending = data;
      _deliveredTap = payload;
      _drainTap();
    } on FormatException {
      /* Ignore untrusted notification payload. */
    }
  }

  void _drainTap() {
    if (_disposed ||
        _pending == null ||
        _userId == null ||
        _pending!['account'] != _userId) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || _pending == null || _pending!['account'] != _userId) {
        return;
      }
      final context = navigatorKey.currentContext;
      if (context == null) return;
      final pending = _pending!;
      _pending = null;
      NotificationDeepLinkHandler.handleTap(
        context,
        NotificationItem(
          notificationId: '',
          type: 'SYSTEM',
          title: '',
          body: '',
          createdAt: DateTime.now(),
          target: NotificationTarget(
            type: pending['type']?.toString() ?? '',
            id: pending['id']?.toString() ?? '',
          ),
        ),
      );
    });
  }

  @override
  void dispose() {
    _disposed = true;
    ++_epoch;
    dependencies.session.removeListener(_sessionChanged);
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }
}
