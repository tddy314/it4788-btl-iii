import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/widgets/connection_banner.dart';
import 'app_dependencies.dart';
import 'app_scope.dart';
import 'app_shell.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

class SqbApp extends StatefulWidget {
  const SqbApp({
    super.key,
    required AppDependencies this.dependencies,
    this.loginBuilder,
    this.tabBuilders = const {},
    this.protectedRoutes = const {},
  }) : startingChild = null;
  const SqbApp.starting({super.key, required Widget child})
    : startingChild = child,
      dependencies = null,
      loginBuilder = null,
      tabBuilders = const {},
      protectedRoutes = const {};
  final AppDependencies? dependencies;
  final Widget? startingChild;
  final WidgetBuilder? loginBuilder;
  final Map<AppTab, WidgetBuilder> tabBuilders;
  final Map<String, WidgetBuilder> protectedRoutes;
  @override
  State<SqbApp> createState() => _SqbAppState();
}

class _SqbAppState extends State<SqbApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.dependencies?.connection.check());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dependencies = widget.dependencies;
    if (dependencies == null) {
      return _material(
        home: Scaffold(body: SafeArea(child: widget.startingChild!)),
      );
    }
    return AppScope(
      dependencies: dependencies,
      child: ListenableBuilder(
        listenable: dependencies.session,
        builder: (context, _) {
          final router = AppRouter(
            session: dependencies.session,
            loginBuilder: widget.loginBuilder,
            tabBuilders: widget.tabBuilders,
            protectedRoutes: widget.protectedRoutes,
          );
          // Đổi tài khoản/logout phải bỏ toàn bộ navigation stack của user cũ.
          return _material(
            key: ValueKey(dependencies.session.tokens?.userId),
            onGenerateRoute: router.onGenerateRoute,
            builder: (context, child) => Column(
              children: [
                ConnectionBanner(connection: dependencies.connection),
                Expanded(child: child ?? const SizedBox.shrink()),
              ],
            ),
          );
        },
      ),
    );
  }

  MaterialApp _material({
    Key? key,
    Widget? home,
    RouteFactory? onGenerateRoute,
    TransitionBuilder? builder,
  }) => MaterialApp(
    key: key,
    title: 'SQB',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    locale: const Locale('vi'),
    supportedLocales: const [Locale('vi')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: home,
    onGenerateRoute: onGenerateRoute,
    builder: builder,
  );
}
