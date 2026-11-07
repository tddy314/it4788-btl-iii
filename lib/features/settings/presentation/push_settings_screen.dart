import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/widgets/app_states.dart';
import '../data/push_settings_repository.dart';
import '../models/push_settings.dart';

class PushSettingsScreen extends StatefulWidget {
  const PushSettingsScreen({super.key});

  @override
  State<PushSettingsScreen> createState() => _PushSettingsScreenState();
}

class _PushSettingsScreenState extends State<PushSettingsScreen> {
  PushSettingsRepository? _repository;
  PushSettings _settings = PushSettings.defaults();
  bool _isLoading = true;
  String? _userId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_repository == null) {
      final deps = AppScope.of(context);
      _userId = deps.session.tokens?.userId ?? 'anonymous';
      _repository = PushSettingsRepository(api: deps.api, cache: deps.cache);
      _loadSettings();
    }
  }

  Future<void> _loadSettings() async {
    // 1. Đọc từ cache trước
    if (_userId != null) {
      final cached = await _repository?.loadCached(_userId!);
      if (cached != null && mounted) {
        setState(() {
          _settings = cached;
        });
      }
    }

    // 2. Fetch server
    try {
      final remote = await _repository?.fetchSettings();
      if (remote != null && mounted) {
        setState(() {
          _settings = remote;
          _isLoading = false;
        });
        if (_userId != null) {
          await _repository?.saveToCache(_userId!, remote);
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _update(PushSettings newSettings) async {
    final oldSettings = _settings;
    setState(() => _settings = newSettings);

    try {
      final updated = await _repository?.updateSettings(newSettings);
      if (updated != null && mounted) {
        setState(() => _settings = updated);
        if (_userId != null) {
          await _repository?.saveToCache(_userId!, updated);
        }
      }
    } catch (_) {
      // Rollback nếu có lỗi
      if (mounted) {
        setState(() => _settings = oldSettings);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Không thể cập nhật cài đặt. Vui lòng thử lại.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Cài đặt thông báo')),
      body: _isLoading
          ? const AppLoadingState(message: 'Đang tải cài đặt…')
          : ListView(
              children: [
                // Công tắc tổng thể
                SwitchListTile(
                  secondary: const Icon(Icons.notifications_active_outlined),
                  title: const Text(
                    'Cho phép thông báo đẩy',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text('Nhận thông báo khi có tương tác mới'),
                  value: _settings.pushEnabled,
                  onChanged: (val) {
                    _update(_settings.copyWith(pushEnabled: val));
                  },
                ),
                const Divider(),

                if (_settings.pushEnabled) ...[
                  // Danh mục thông báo
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(
                      'Chuyên mục thông báo',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  SwitchListTile(
                    title: const Text('Mạng xã hội & Tin nhắn'),
                    subtitle: const Text(
                      'Thông báo khi có người nhắn tin, like hoặc bình luận',
                    ),
                    value: _settings.social.enabled,
                    onChanged: (val) {
                      _update(
                        _settings.copyWith(
                          social: _settings.social.copyWith(enabled: val),
                        ),
                      );
                    },
                  ),
                  SwitchListTile(
                    title: const Text('Ngân hàng câu hỏi'),
                    subtitle: const Text(
                      'Thông báo khi bộ câu hỏi được duyệt hoặc có phản hồi',
                    ),
                    value: _settings.academic.enabled,
                    onChanged: (val) {
                      _update(
                        _settings.copyWith(
                          academic: _settings.academic.copyWith(enabled: val),
                        ),
                      );
                    },
                  ),
                  SwitchListTile(
                    title: const Text('Hệ thống'),
                    subtitle: const Text('Thông báo bảo mật và phiên đăng nhập'),
                    value: _settings.system.enabled,
                    onChanged: (val) {
                      _update(
                        _settings.copyWith(
                          system: _settings.system.copyWith(enabled: val),
                        ),
                      );
                    },
                  ),

                  const Divider(),

                  // Âm thanh và rung
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(
                      'Hiệu ứng thông báo',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  SwitchListTile(
                    title: const Text('Phát âm thanh'),
                    secondary: const Icon(Icons.volume_up_outlined),
                    value: _settings.soundEnabled,
                    onChanged: (val) {
                      _update(_settings.copyWith(soundEnabled: val));
                    },
                  ),
                  SwitchListTile(
                    title: const Text('Rung khi có thông báo'),
                    secondary: const Icon(Icons.vibration_outlined),
                    value: _settings.vibrationEnabled,
                    onChanged: (val) {
                      _update(_settings.copyWith(vibrationEnabled: val));
                    },
                  ),

                  if (_settings.soundEnabled) ...[
                    const Divider(),
                    // Tùy chọn âm thanh theo yêu cầu riêng môn IT4788 (Slide 26 & 29)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                      child: Text(
                        'Kiểu âm thanh thông báo (Yêu cầu IT4788)',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    RadioListTile<String>(
                      title: const Text('Âm thanh mặc định'),
                      subtitle: const Text('Tiếng chuông ngân vang hệ thống'),
                      value: 'default',
                      groupValue: _settings.soundType,
                      onChanged: (val) {
                        if (val != null) {
                          _update(_settings.copyWith(soundType: val));
                        }
                      },
                    ),
                    RadioListTile<String>(
                      title: const Text('Giọng nói phát ra (Thu âm đặc trưng)'),
                      subtitle: const Text(
                        'Phát file âm thanh giọng nói của nhóm sinh viên',
                      ),
                      value: 'voice',
                      groupValue: _settings.soundType,
                      onChanged: (val) {
                        if (val != null) {
                          _update(_settings.copyWith(soundType: val));
                        }
                      },
                    ),
                  ],
                ],
              ],
            ),
    );
  }
}
