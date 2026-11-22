import 'package:flutter/material.dart';

import '../../../../app/app_scope.dart';
import '../../../../core/errors/app_failure.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/storage/json_cache.dart';
import '../../../../core/widgets/app_states.dart';
import '../../../question_bank/practice_screen.dart';
import '../../../question_bank/question_bank_cache.dart';
import '../../../question_bank/question_bank_repository.dart';
import '../../../question_bank/question_models.dart';
import '../../../question_bank/submission_detail_screen.dart';

/// A SESSION target need not belong to the current student. Only server
/// permission checks decide whether to open submission tools or practice.
Future<bool> resolveNotificationSession(
  ApiClient api,
  int sessionId, {
  JsonCache? cache,
}) async {
  if (sessionId <= 0) throw AppFailure.invalidData;
  final session = api.session.tokens;
  if (session == null) throw AppFailure.unauthorized;
  bool current() => api.session.tokens?.userId == session.userId;
  Future<bool> cached(bool own) async {
    try {
      final entry = await cache?.read(
        userId: session.userId,
        resource: 'qb.${own ? 'submission' : 'practice'}.$sessionId',
      );
      if (!current() || entry == null) return false;
      return (own
              ? SubmissionDetail.fromJson(entry.data).sessionId
              : PracticeSession.fromJson(entry.data).sessionId) ==
          sessionId;
    } catch (_) {
      return false;
    }
  }

  final repository = QuestionBankRepository(api);
  try {
    await repository.submissionDetail(sessionId);
    if (!current()) {
      throw AppFailure.unauthorized;
    }
    return true;
  } on AppFailure catch (error) {
    if (!current()) {
      throw AppFailure.unauthorized;
    }
    if (error.canUseCache) {
      if (await cached(true)) return true;
      if (await cached(false)) return false;
    }
    if (error.statusCode != 403 && error.statusCode != 404) rethrow;
  }
  try {
    await repository.practiceQuestions(sessionId);
  } on AppFailure catch (error) {
    if (!current()) throw AppFailure.unauthorized;
    if (!error.canUseCache || !await cached(false)) rethrow;
  }
  if (!current()) {
    throw AppFailure.unauthorized;
  }
  return false;
}

class SessionNotificationScreen extends StatefulWidget {
  const SessionNotificationScreen({super.key, required this.sessionId});
  final int sessionId;

  @override
  State<SessionNotificationScreen> createState() =>
      _SessionNotificationScreenState();
}

class _SessionNotificationScreenState extends State<SessionNotificationScreen> {
  Future<bool>? _target;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _target ??= _resolve();
  }

  Future<bool> _resolve() {
    final dependencies = AppScope.of(context);
    return resolveNotificationSession(
      dependencies.api,
      widget.sessionId,
      cache: QuestionBankCache(
        drafts: dependencies.drafts,
        legacy: dependencies.cache,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: _target,
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        return snapshot.data!
            ? SubmissionDetailScreen(sessionId: widget.sessionId)
            : PracticeScreen(sessionId: widget.sessionId);
      }
      return Scaffold(
        appBar: AppBar(title: const Text('Bộ câu hỏi')),
        body: snapshot.hasError
            ? AppErrorState(
                message: snapshot.error is AppFailure
                    ? (snapshot.error! as AppFailure).message
                    : 'Không mở được bộ câu hỏi. Vui lòng thử lại.',
                onRetry: () => setState(() => _target = _resolve()),
              )
            : const AppLoadingState(message: 'Đang mở bộ câu hỏi…'),
      );
    },
  );
}
