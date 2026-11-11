import 'package:flutter/material.dart';

import '../../core/widgets/app_states.dart';
import 'practice_screen.dart';
import 'proposal_composer_screen.dart';
import 'question_models.dart';
import 'question_ratings_screen.dart';
import 'submission_detail_screen.dart';

/// Route bảo vệ của ngân hàng câu hỏi, đăng ký qua `protectedRoutes`.
abstract final class QuestionBankRoutes {
  static const compose = '/question-bank/compose';
  static const submission = '/question-bank/submission';
  static const practice = '/question-bank/practice';
  static const ratings = '/question-bank/ratings';

  static Map<String, WidgetBuilder> get routes => {
    compose: (context) {
      final args = ModalRoute.of(context)?.settings.arguments;
      return ProposalComposerScreen(
        editing: args is SubmissionDetail ? args : null,
      );
    },
    submission: (context) =>
        _withId(context, (id) => SubmissionDetailScreen(sessionId: id)),
    practice: (context) =>
        _withId(context, (id) => PracticeScreen(sessionId: id)),
    ratings: (context) =>
        _withId(context, (id) => QuestionRatingsScreen(questionId: id)),
  };

  static Widget _withId(BuildContext context, Widget Function(int) builder) {
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is int) return builder(args);
    return Scaffold(
      appBar: AppBar(),
      body: const AppEmptyState(
        title: 'Không tìm thấy trang',
        icon: Icons.search_off,
      ),
    );
  }
}
