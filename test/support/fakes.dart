import 'package:it4788_btl/core/network/connection_monitor.dart';
import 'package:it4788_btl/core/storage/key_value_store.dart';

class MemoryStore implements KeyValueStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }
}

class FakeConnection extends ConnectionMonitor {
  FakeConnection([this.value = ConnectionStatus.available]);
  ConnectionStatus value;
  @override
  ConnectionStatus get status => value;
  @override
  Future<void> check() async {}
  void change(ConnectionStatus next) {
    value = next;
    notifyListeners();
  }
}
