import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/widgets/app_states.dart';
import '../../notifications/push/push_coordinator.dart';
import '../data/push_settings_repository.dart';
import '../notification_sound_controller.dart';
import '../push_settings_controller.dart';

class PushSettingsScreen extends StatefulWidget {
  const PushSettingsScreen({super.key});
  @override
  State<PushSettingsScreen> createState() => _PushSettingsScreenState();
}

class _PushSettingsScreenState extends State<PushSettingsScreen>
    with WidgetsBindingObserver {
  PushSettingsController? _settings;
  NotificationSoundController? _sound;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_settings != null) return;
    final deps = AppScope.of(context),
        id = AppScope.of(context).session.tokens!.userId;
    bool current() => mounted && deps.session.tokens?.userId == id;
    _settings = PushSettingsController(
      PushSettingsRepository(api: deps.api, cache: deps.cache),
      id,
      current,
    )..load();
    _sound = NotificationSoundController(deps.drafts, id, current)..load();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _sound?.recording == true) {
      unawaited(_sound?.stop());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _settings?.dispose();
    _sound?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _settings!, sound = _sound!, push = PushScope.maybeOf(context);
    return ListenableBuilder(
      listenable: Listenable.merge([c, sound, ?push]),
      builder: (context, _) {
        final settings = c.settings;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Cài đặt thông báo'),
            actions: [
              IconButton(
                tooltip: 'Tải lại',
                onPressed: c.loading || c.saving ? null : c.load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          body: PopScope(
            canPop: !sound.recording && !sound.busy,
            onPopInvokedWithResult: (didPop, result) async {
              if (!didPop && !sound.busy && sound.recording) await sound.stop();
            },
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                if (c.loading || c.saving) const LinearProgressIndicator(),
                if (c.message != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(c.message!),
                  ),
                if (c.fromCache)
                  const ListTile(
                    leading: Icon(Icons.offline_bolt_outlined),
                    title: Text(
                      'Đang xem cài đặt đã lưu. Kết nối mạng và tải lại để chỉnh sửa.',
                    ),
                  ),
                if (settings == null && !c.loading)
                  AppErrorState(
                    message: 'Chưa tải được cài đặt thông báo.',
                    onRetry: c.load,
                  ),
                if (settings != null) ...[
                  SwitchListTile(
                    title: const Text('Cho phép thông báo đẩy'),
                    secondary: const Icon(Icons.notifications_active_outlined),
                    value: settings.pushEnabled,
                    onChanged: c.writable
                        ? (v) => c.update(settings.copyWith(pushEnabled: v))
                        : null,
                  ),
                  if (settings.pushEnabled) ...[
                    const Divider(),
                    SwitchListTile(
                      title: const Text('Mạng xã hội và tin nhắn'),
                      value: settings.social.enabled,
                      onChanged: c.writable
                          ? (v) => c.update(
                              settings.copyWith(
                                social: settings.social.copyWith(enabled: v),
                              ),
                            )
                          : null,
                    ),
                    SwitchListTile(
                      title: const Text('Ngân hàng câu hỏi'),
                      value: settings.academic.enabled,
                      onChanged: c.writable
                          ? (v) => c.update(
                              settings.copyWith(
                                academic: settings.academic.copyWith(
                                  enabled: v,
                                ),
                              ),
                            )
                          : null,
                    ),
                    SwitchListTile(
                      title: const Text('Hệ thống'),
                      value: settings.system.enabled,
                      onChanged: c.writable
                          ? (v) => c.update(
                              settings.copyWith(
                                system: settings.system.copyWith(enabled: v),
                              ),
                            )
                          : null,
                    ),
                    const Divider(),
                    SwitchListTile(
                      title: const Text('Phát âm thanh'),
                      secondary: const Icon(Icons.volume_up_outlined),
                      value: settings.soundEnabled,
                      onChanged: c.writable
                          ? (v) => c.update(settings.copyWith(soundEnabled: v))
                          : null,
                    ),
                    SwitchListTile(
                      title: const Text('Rung khi có thông báo'),
                      secondary: const Icon(Icons.vibration_outlined),
                      value: settings.vibrationEnabled,
                      onChanged: c.writable
                          ? (v) =>
                                c.update(settings.copyWith(vibrationEnabled: v))
                          : null,
                    ),
                  ],
                ],
                const Divider(),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Âm thanh trên thiết bị này',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                RadioGroup<String>(
                  groupValue: sound.mode,
                  onChanged: (v) {
                    if (sound.busy || sound.recording) return;
                    if (v != null) unawaited(sound.choose(v));
                  },
                  child: const Column(
                    children: [
                      RadioListTile<String>(
                        title: Text('Âm thanh mặc định'),
                        value: 'default',
                      ),
                      RadioListTile<String>(
                        title: Text('Giọng nói đã thu'),
                        value: 'voice',
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: sound.busy
                            ? null
                            : sound.recording
                            ? sound.stop
                            : sound.start,
                        icon: Icon(sound.recording ? Icons.stop : Icons.mic),
                        label: Text(
                          sound.recording
                              ? 'Dừng và lưu'
                              : 'Thu âm (tối đa 15 giây)',
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: sound.busy || sound.recording
                            ? null
                            : sound.preview,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Nghe thử'),
                      ),
                    ],
                  ),
                ),
                if (sound.message != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(sound.message!),
                  ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.phone_android),
                  title: const Text('Nhận thông báo trên điện thoại'),
                  subtitle: Text(
                    push?.status ??
                        'Thông báo đẩy chưa được cấu hình cho bản cài đặt này.',
                  ),
                ),
                if (push?.configured == true)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: OutlinedButton(
                      onPressed: push!.busy ? null : push.enable,
                      child: const Text('Kiểm tra và cấp quyền thông báo'),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
