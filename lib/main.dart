import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/app_dependencies.dart';
import 'core/widgets/app_states.dart';

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
        return SqbApp(dependencies: snapshot.requireData);
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
