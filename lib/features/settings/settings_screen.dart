import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../auth/auth_controller.dart';

abstract final class SettingsRoutes {
  static const settings = '/settings';
  static const changePassword = '/settings/change-password';
}

/// Menu cài đặt tài khoản, không thay thế màn hồ sơ của thành viên 4.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.auth, this.embedded = false});
  final AuthController auth;
  final bool embedded;
  Future<void> _logout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Đăng xuất?'),
        content: const Text(
          'Bạn sẽ cần đăng nhập lại để truy cập nội dung. Nếu mất mạng, ứng dụng chỉ có thể đăng xuất trên máy này.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Đăng xuất'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) await auth.logout();
  }

  @override
  Widget build(BuildContext context) {
    final body = ListenableBuilder(
      listenable: auth,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Cài đặt tài khoản',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: const Text('Đổi mật khẩu'),
                  trailing: const Icon(Icons.chevron_right),
                  enabled: !auth.busy,
                  onTap: () =>
                      Navigator.of(context)
                          .pushNamed(SettingsRoutes.changePassword),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('Đăng xuất'),
                  enabled: !auth.busy,
                  onTap: () => _logout(context),
                ),
              ],
            ),
          ),
          if (auth.busy) const LinearProgressIndicator(),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Về SQB'),
            onTap: () => showAboutDialog(
              context: context,
              applicationName: 'SQB',
              children: [
                const Text(
                  'Cộng đồng học tập và đóng góp ngân hàng câu hỏi cho sinh viên.',
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.close),
            title: const Text('Đóng ứng dụng'),
            enabled: !auth.busy,
            onTap: () => SystemNavigator.pop(),
          ),
        ],
      ),
    );
    return embedded
        ? body
        : Scaffold(
            appBar: AppBar(title: const Text('Cài đặt')),
            body: SafeArea(child: body),
          );
  }
}
