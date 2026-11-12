import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../../app/app_dependencies.dart';
import '../../app/app_shell.dart';
import '../../core/storage/key_value_store.dart';
import '../../core/widgets/app_states.dart';
import '../profile/profile_models.dart';
import '../profile/profile_screen.dart';
import '../question_bank/question_bank_routes.dart';
import '../question_bank/question_bank_tab.dart';
import '../relationships/friend_finder_screen.dart';
import '../relationships/relationships_screen.dart';
import '../relationships/social_models.dart';
import '../relationships/social_state.dart';
import '../settings/change_password_screen.dart';
import '../settings/settings_screen.dart';
import 'auth_controller.dart';
import 'auth_repository.dart';
import 'device_identity.dart';
import 'login_screen.dart';

/// Điểm nối feature qua API công khai của khung app; không sửa core/router/theme.
class AuthApplication extends StatefulWidget {
  const AuthApplication({
    super.key,
    required this.dependencies,
    this.tabBuilders = const {},
    this.protectedRoutes = const {},
  });
  final AppDependencies dependencies;
  final Map<AppTab, WidgetBuilder> tabBuilders;
  final Map<String, WidgetBuilder> protectedRoutes;

  @override
  State<AuthApplication> createState() => _AuthApplicationState();
}

class _AuthApplicationState extends State<AuthApplication> {
  late final AuthRepository _repository;
  late final AuthController _auth;
  late final SocialChanges _social;
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
    _social = SocialChanges(widget.dependencies.session);
  }

  @override
  void dispose() {
    widget.dependencies.api.refreshTokens = null;
    _social.dispose();
    _auth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SqbApp(
    dependencies: widget.dependencies,
    loginBuilder: (_) => LoginScreen(auth: _auth),
    tabBuilders: {
      AppTab.profile: (_) => ProfileScreen(changes: _social, embedded: true),
      AppTab.friends: (_) =>
          RelationshipsScreen(changes: _social, embedded: true),
      AppTab.questionBank: (_) => const QuestionBankTab(),
      ...widget.tabBuilders,
    },
    protectedRoutes: {
      RelationshipRoutes.findFriends: (_) =>
          FriendFinderScreen(changes: _social),
      ProfileRoutes.user: (context) {
        final argument = ModalRoute.of(context)?.settings.arguments;
        final id = argument?.toString();
        if (id == null || !RegExp(r'^[1-9][0-9]*$').hasMatch(id)) {
          return const Scaffold(
            body: AppErrorState(message: 'Hồ sơ không hợp lệ.'),
          );
        }
        return ProfileScreen(changes: _social, userId: id);
      },
      SettingsRoutes.settings: (_) => Scaffold(
        appBar: AppBar(title: const Text('Cài đặt')),
        body: SafeArea(
          child: Column(
            children: [
              Builder(
                builder: (context) => ListTile(
                  leading: const Icon(Icons.block_outlined),
                  title: const Text('Danh sách chặn'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => RelationshipsScreen(
                        changes: _social,
                        initial: RelationshipList.blocked,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(child: SettingsScreen(auth: _auth, embedded: true)),
            ],
          ),
        ),
      ),
      SettingsRoutes.changePassword: (_) =>
          ChangePasswordScreen(repository: _repository),
      ...QuestionBankRoutes.routes,
      ...widget.protectedRoutes,
    },
  );
}
