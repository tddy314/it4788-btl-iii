import 'package:flutter/material.dart';

import '../../core/storage/session_store.dart';
import '../../core/widgets/app_states.dart';
import '../app_shell.dart';

abstract final class AppRoutes {
  static const home = '/';
  static const login = '/login';
}

class AppRouter {
  AppRouter({
    required this.session,
    this.loginBuilder,
    this.tabBuilders = const {},
    this.protectedRoutes = const {},
  });
  final SessionStore session;
  final WidgetBuilder? loginBuilder;
  final Map<AppTab, WidgetBuilder> tabBuilders;
  final Map<String, WidgetBuilder> protectedRoutes;

  Route<void> onGenerateRoute(RouteSettings settings) {
    final isLogin = settings.name == AppRoutes.login;
    WidgetBuilder builder;
    if (!session.hasSession) {
      builder =
          loginBuilder ??
          (_) => const Scaffold(
            body: SafeArea(
              child: AppEmptyState(
                icon: Icons.lock_outline,
                title: 'Đăng nhập',
                message:
                    'Sử dụng tài khoản được giảng viên cấp để truy cập SQB.',
              ),
            ),
          );
    } else if (settings.name == AppRoutes.home || isLogin) {
      builder = (_) => AppShell(builders: tabBuilders);
    } else {
      builder =
          protectedRoutes[settings.name] ??
          (_) => const Scaffold(
            body: AppEmptyState(
              title: 'Không tìm thấy trang',
              icon: Icons.search_off,
            ),
          );
    }
    return MaterialPageRoute<void>(settings: settings, builder: builder);
  }
}
