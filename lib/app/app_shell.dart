import 'package:flutter/material.dart';

import '../core/widgets/app_states.dart';

enum AppTab { feed, questionBank, friends, notifications, profile }

/// Chỉ khung điều hướng. Các feature cung cấp nội dung qua builders.
class AppShell extends StatefulWidget {
  const AppShell({super.key, this.builders = const {}});
  final Map<AppTab, WidgetBuilder> builders;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selected = 0;
  final _visited = <int>{0};
  static const _labels = [
    'Bảng tin',
    'Ngân hàng',
    'Bạn bè',
    'Thông báo',
    'Cá nhân',
  ];
  static const _icons = [
    Icons.home_outlined,
    Icons.menu_book_outlined,
    Icons.people_outline,
    Icons.notifications_outlined,
    Icons.person_outline,
  ];
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_selected == 0 ? 'SQB' : _labels[_selected])),
    body: IndexedStack(
      index: _selected,
      children: [
        for (final tab in AppTab.values)
          if (!_visited.contains(tab.index))
            const SizedBox.shrink()
          else
            widget.builders[tab]?.call(context) ??
                const AppEmptyState(
                  message: 'Nội dung sẽ được hiển thị tại đây.',
                ),
      ],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _selected,
      onDestinationSelected: (index) => setState(() {
        _selected = index;
        _visited.add(index);
      }),
      destinations: [
        for (var i = 0; i < _labels.length; i++)
          NavigationDestination(icon: Icon(_icons[i]), label: _labels[i]),
      ],
    ),
  );
}
