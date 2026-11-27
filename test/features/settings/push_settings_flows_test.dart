import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:it4788_btl/core/errors/app_failure.dart';
import 'package:it4788_btl/features/settings/data/push_settings_repository.dart';
import 'package:it4788_btl/features/settings/models/push_settings.dart';
import 'package:it4788_btl/features/settings/push_settings_controller.dart';

class Repository extends Fake implements PushSettingsRepository {
  Completer<PushSettings>? pending;
  AppFailure? readFailure, writeFailure;
  int puts = 0;
  PushSettings value = PushSettings.defaults();
  @override
  Future<PushSettings?> loadCached(String id) async => null;
  @override
  Future<PushSettings> fetchSettings() async {
    if (readFailure != null) throw readFailure!;
    return value;
  }

  @override
  Future<PushSettings> updateSettings(PushSettings settings) async {
    puts++;
    if (writeFailure != null) throw writeFailure!;
    return pending == null ? settings : pending!.future;
  }

  @override
  Future<void> saveToCache(String id, PushSettings settings) async {}
}

void main() {
  test('Settings serialize only server fields and preserve quiet hours/other categories', () {
    final settings = PushSettings.fromJson({
      ...PushSettings.defaults().toJson(),
      'categories': {
        'GAMIFICATION': {'enabled': false},
      },
      'quiet_hours': {'enabled': true, 'start': '23:00', 'end': '07:00'},
    });
    final body = settings
        .copyWith(soundEnabled: false, soundType: 'voice')
        .toServerJson();
    expect(body.containsKey('sound_type'), isFalse);
    expect((body['categories'] as Map)['GAMIFICATION'], {'enabled': false});
    expect((body['quiet_hours'] as Map)['start'], '23:00');
  });
  test('Updates are serialized and late responses cannot update a disposed controller', () async {
    final r = Repository();
    final c = PushSettingsController(r, '7', () => true);
    await c.load();
    r.pending = Completer();
    final future = c.update(r.value.copyWith(pushEnabled: false));
    await c.update(r.value.copyWith(soundEnabled: false));
    expect(r.puts, 1);
    c.dispose();
    r.pending!.complete(r.value.copyWith(pushEnabled: false));
    await future;
    expect(c.settings!.pushEnabled, isTrue);
  });
  test('Timeout reconciles with GET only, and failed reconciliation prevents write replay', () async {
    final r = Repository();
    final c = PushSettingsController(r, '7', () => true);
    await c.load();
    r.writeFailure = const AppFailure(FailureKind.timeout, 'Hết thời gian');
    r.readFailure = AppFailure.offline;
    await c.update(r.value.copyWith(pushEnabled: false));
    await c.update(r.value);
    expect(c.uncertain, isTrue);
    expect(c.writable, isFalse);
    expect(r.puts, 1);
    r.readFailure = null;
    await c.load();
    expect(c.writable, isTrue);
    c.dispose();
  });
}
