import 'package:flutter/widgets.dart';

import 'social_state.dart';

class SocialScope extends InheritedNotifier<SocialChanges> {
  const SocialScope({
    super.key,
    required SocialChanges changes,
    required super.child,
  }) : super(notifier: changes);
  static SocialChanges? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SocialScope>()?.notifier;
}
