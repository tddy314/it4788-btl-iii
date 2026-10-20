import 'package:flutter/widgets.dart';

import 'app_dependencies.dart';

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.dependencies, required super.child});
  final AppDependencies dependencies;
  static AppDependencies of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope chưa được gắn vào widget tree.');
    return scope!.dependencies;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      !identical(oldWidget.dependencies, dependencies);
}
