import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/app_dependencies.dart';
import 'app/app_shell.dart';
import 'core/widgets/app_states.dart';
import 'features/auth/auth_application.dart';
import 'features/chat/chat_feature.dart';
import 'features/notifications/notifications_feature.dart';
import 'features/settings/presentation/push_settings_screen.dart';
import 'features/settings/settings_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AppBootstrap());
}

class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key});
  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  late Future<AppDependencies> _dependencies = _create();
  AppDependencies? _resolved;

  Future<AppDependencies> _create() async {
    final dependencies = await AppDependencies.create();
    if (!mounted) {
      dependencies.dispose();
    } else {
      _resolved = dependencies;
    }
    return dependencies;
  }

  @override
  void dispose() {
    _resolved?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<AppDependencies>(
    future: _dependencies,
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        return AuthApplication(
          dependencies: snapshot.requireData,
          tabBuilders: {
            AppTab.notifications: (_) => const NotificationsTab(),
          },
          protectedRoutes: {
            '/conversations': (_) => const ConversationsScreen(),
            '/chat': (_) => const ChatDetailScreen(),
            SettingsRoutes.pushSettings: (_) => const PushSettingsScreen(),
          },
        );
      }
      return SqbApp.starting(
        child: snapshot.hasError
            ? AppErrorState(
                message: 'Không thể khởi tạo ứng dụng. Vui lòng thử lại.',
                onRetry: () => setState(() {
                  _dependencies = _create();
                }),
              )
            : const AppLoadingState(message: 'Đang mở ứng dụng…'),
      );
    },
  );
}
