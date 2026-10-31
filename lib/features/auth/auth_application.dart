import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../../app/app_dependencies.dart';
import '../../app/app_shell.dart';
import '../../core/storage/key_value_store.dart';
import '../settings/change_password_screen.dart';
import '../settings/settings_screen.dart';
import 'auth_controller.dart';
import 'auth_repository.dart';
import 'device_identity.dart';
import 'login_screen.dart';

/// Điểm nối feature qua API công khai của khung app; không sửa core/router/theme.
class AuthApplication extends StatefulWidget {
  const AuthApplication({super.key, required this.dependencies});
  final AppDependencies dependencies;
  @override
  State<AuthApplication> createState() => _AuthApplicationState();
}

class _AuthApplicationState extends State<AuthApplication> {
  late final AuthRepository _repository;
  late final AuthController _auth;
  @override
  void initState() {
    super.initState();
    _repository = AuthRepository(
      api: widget.dependencies.api,
      device: DeviceIdentity(SecureKeyValueStore()),
    );
    _auth = AuthController(
      repository: _repository,
      session: widget.dependencies.session,
    );
    widget.dependencies.api.refreshTokens = _auth.refresh;
  }

  @override
  void dispose() {
    widget.dependencies.api.refreshTokens = null;
    _auth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SqbApp(
    dependencies: widget.dependencies,
    loginBuilder: (_) => LoginScreen(auth: _auth),
    // Tạm đặt menu cài đặt vào tab Cá nhân; người làm hồ sơ có thể thay builder,
    // mở menu qua SettingsRoutes.settings, không cần viết lại auth.
    tabBuilders: {
      AppTab.profile: (_) => SettingsScreen(auth: _auth, embedded: true),
    },
    protectedRoutes: {
      SettingsRoutes.settings: (_) => SettingsScreen(auth: _auth),
      SettingsRoutes.changePassword: (_) =>
          ChangePasswordScreen(repository: _repository),
    },
  );
}
