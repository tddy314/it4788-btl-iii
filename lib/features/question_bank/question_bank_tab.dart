import 'package:flutter/material.dart';

import 'my_submissions_view.dart';
import 'practice_catalog_view.dart';

/// Nội dung tab "Ngân hàng": đề xuất của tôi và kho luyện tập.
class QuestionBankTab extends StatelessWidget {
  const QuestionBankTab({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surface,
          child: const TabBar(
            tabs: [
              Tab(text: 'Đề xuất của tôi'),
              Tab(text: 'Luyện tập'),
            ],
          ),
        ),
        const Expanded(
          child: TabBarView(
            children: [MySubmissionsView(), PracticeCatalogView()],
          ),
        ),
      ],
    ),
  );
}
