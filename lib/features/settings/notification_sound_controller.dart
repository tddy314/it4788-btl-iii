import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../core/storage/draft_store.dart';

class NotificationSoundController extends ChangeNotifier {
  NotificationSoundController(this.store, this.userId, this.isCurrent);
  final DraftStore store;
  final String userId;
  final bool Function() isCurrent;
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();
  bool _disposed = false, busy = false, recording = false;
  String mode = 'default';
  String? voicePath, voiceUri, message;
  Timer? _limit;
  bool get active => !_disposed && isCurrent();
  static const key = 'notification.sound.v1';
  void _notify() {
    if (active) notifyListeners();
  }

  Future<void> load() async {
    try {
      final saved = await store.read(userId: userId, name: key);
      if (!active) return;
      voicePath = saved?['path'] as String?;
      voiceUri = saved?['uri'] as String?;
      mode =
          saved?['mode'] == 'voice' &&
              voicePath != null &&
              await File(voicePath!).exists()
          ? 'voice'
          : 'default';
    } catch (_) {
      if (active) message = 'Không đọc được âm thanh đã lưu.';
    }
    _notify();
  }

  Future<void> choose(String value) async {
    if (!active || busy || recording) return;
    if (value == 'voice' &&
        (voicePath == null || !await File(voicePath!).exists())) {
      message = 'Hãy thu âm giọng nói trước khi chọn.';
      _notify();
      return;
    }
    busy = true;
    _notify();
    try {
      await store.save(
        userId: userId,
        name: key,
        data: {'mode': value, 'path': voicePath, 'uri': voiceUri},
      );
      if (active) {
        mode = value;
        message = null;
      }
    } catch (_) {
      if (active) message = 'Không lưu được lựa chọn âm thanh.';
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> start() async {
    if (!active || busy || recording) return;
    busy = true;
    message = null;
    _notify();
    try {
      if (!await _recorder.hasPermission()) {
        if (active) message = 'Cần quyền micro để thu âm. Bạn có thể cấp lại trong Cài đặt thiết bị.';
        return;
      }
      if (!active) return;
      final root = await getApplicationSupportDirectory();
      final dir = Directory(
        '${root.path}/notification-sounds/${Uri.encodeComponent(userId)}',
      );
      await dir.create(recursive: true);
      final files = await dir
          .list(followLinks: false)
          .where((e) => e is File)
          .cast<File>()
          .toList();
      for (final file in files.where((e) => e.path != voicePath)) {
        await file.delete();
      }
      if (!active) return;
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000),
        path: '${dir.path}/${DateTime.now().microsecondsSinceEpoch}.m4a',
      );
      if (!active) {
        await _recorder.cancel();
        return;
      }
      recording = true;
      _limit = Timer(const Duration(seconds: 15), () {
        unawaited(stop());
      });
    } catch (_) {
      if (active) {
        message = 'Không thể bắt đầu thu âm. Hãy kiểm tra quyền micro.';
      }
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> stop() async {
    if (!active || busy || !recording) return;
    busy = true;
    _limit?.cancel();
    _notify();
    try {
      final path = await _recorder.stop();
      recording = false;
      if (!active || path == null || await File(path).length() == 0) return;
      final uri = await const MethodChannel('sqb.notification_sounds')
          .invokeMethod<String>('uri', {'path': path});
      if (!active) return;
      await store.save(
        userId: userId,
        name: key,
        data: {'mode': 'voice', 'path': path, 'uri': uri},
      );
      if (active) {
        voicePath = path;
        voiceUri = uri;
        mode = 'voice';
        message = 'Đã lưu giọng nói trên thiết bị này.';
      }
    } catch (_) {
      if (active) {
        message = 'Không lưu được bản thu. Lựa chọn trước được giữ nguyên.';
      }
    } finally {
      busy = false;
      recording = false;
      _notify();
    }
  }

  Future<void> preview() async {
    if (!active || busy || recording) return;
    try {
      if (mode == 'voice' && voicePath != null) {
        await _player.play(DeviceFileSource(voicePath!));
      } else {
        await SystemSound.play(SystemSoundType.alert);
      }
    } catch (_) {
      if (active) {
        message = 'Không phát được âm thanh đã chọn.';
        _notify();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _limit?.cancel();
    unawaited(_recorder.dispose());
    unawaited(_player.dispose());
    super.dispose();
  }
}
