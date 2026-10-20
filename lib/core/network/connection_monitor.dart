import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

enum ConnectionStatus { unknown, offline, available }

/// Available không đảm bảo Internet/server thực sự truy cập được.
abstract class ConnectionMonitor extends ChangeNotifier {
  ConnectionStatus get status;
  Future<void> check();
}

class DeviceConnectionMonitor extends ConnectionMonitor {
  DeviceConnectionMonitor({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();
  final Connectivity _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  ConnectionStatus _status = ConnectionStatus.unknown;
  bool _disposed = false;
  @override
  ConnectionStatus get status => _status;
  Future<void> start() async {
    _subscription ??= _connectivity.onConnectivityChanged.listen(
      _update,
      onError: (Object _) => _set(ConnectionStatus.unknown),
    );
    await check();
  }

  @override
  Future<void> check() async {
    try {
      _update(
        await _connectivity.checkConnectivity().timeout(
          const Duration(seconds: 3),
        ),
      );
    } catch (_) {
      _set(ConnectionStatus.unknown);
    }
  }

  void _update(List<ConnectivityResult> values) => _set(
    values.isEmpty || values.every((v) => v == ConnectivityResult.none)
        ? ConnectionStatus.offline
        : ConnectionStatus.available,
  );
  void _set(ConnectionStatus value) {
    if (_disposed || value == _status) return;
    _status = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
