import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:it4788_btl/core/errors/app_failure.dart';
import 'package:it4788_btl/core/network/connection_monitor.dart';
import 'package:it4788_btl/features/question_bank/paged_list_controller.dart';
import 'package:it4788_btl/features/question_bank/proposal_composer_controller.dart';
import 'package:it4788_btl/features/question_bank/proposal_draft.dart';
import 'package:it4788_btl/features/question_bank/question_bank_repository.dart';
import 'package:it4788_btl/features/question_bank/question_image_service.dart';
import 'package:it4788_btl/features/question_bank/question_models.dart';
import 'package:it4788_btl/features/question_bank/question_validation.dart';

import 'qb_fakes.dart';

/// Bản nháp hợp lệ với 3 câu, câu đầu có [images] ảnh.
ProposalDraft validDraft({int images = 0, int? sessionId}) {
  QuestionDraft question(int i) => QuestionDraft(
    content: 'Nội dung câu $i',
    source: i.isEven ? QuestionSource.human : QuestionSource.llm,
    confidence: i == 0 ? 0 : 3,
    options: [
      OptionDraft(text: 'Đáp án đúng $i', correct: true),
      OptionDraft(text: 'Đáp án sai $i'),
    ],
    images: [
      if (i == 0)
        for (var k = 0; k < images; k++)
          DraftImage(localPath: '/drafts/7/$k.jpg'),
    ],
  );
  return ProposalDraft(
    sessionId: sessionId,
    courseClass: CourseClassOption.fromJson(classJson()),
    title: 'Ôn tập chương 3',
    questions: [question(0), question(1), question(2)],
  );
}

void main() {
  group('Models', () {
    test(
      'lenient parsing: string numbers, missing optionals, unknown enums',
      () {
        final item = SubmissionSummary.fromJson({
          'session_id': '42',
          'status': 'ARCHIVED',
          'question_counts': '5',
          'created_at': 1728200000,
        });
        expect(item.sessionId, 42);
        expect(item.status, SessionStatus.unknown);
        expect(item.questionCount, 5);
        expect(item.approvedCount, isNull);
        expect(item.createdAt, isNotNull);
        expect(item.title, '');
      },
    );

    test('missing required ID is invalid data, not a crash', () {
      expect(
        () => SubmissionSummary.fromJson({'title': 'x'}),
        throwsFormatException,
      );
      expect(() => SubmissionDetail.fromJson('oops'), throwsFormatException);
    });

    test('hidden is_correct stays null instead of false', () {
      final q = PracticeQuestion.fromJson(practiceQuestionJson(1));
      expect(q.options.map((o) => o.isCorrect), [null, null]);
      expect(q.answered, isFalse);
      expect(q.correctAnswer, isNull);
      final answered = PracticeQuestion.fromJson(
        practiceQuestionJson(2, answered: true, correct: 'B', selected: ['A']),
      );
      expect(answered.correctAnswer, 'B');
      expect(answered.selectedKeys, ['A']);
    });

    test('pagination: has_next without cursor cannot load more', () {
      final p = CursorPage.parse(
        {
          'contents': [summaryJson(1)],
          'pagination': {'has_next': true},
        },
        'contents',
        SubmissionSummary.fromJson,
      );
      expect(p.hasNext, isFalse);
      expect(parseAnswerKeys('a, C'), {'A', 'C'});
    });

    test('per-question review status distinguishes partial results', () {
      final detail = SubmissionDetail.fromJson(
        detailJson(
          5,
          status: 'RESOLVED',
          questions: [
            questionJson(1, status: 'APPROVED'),
            questionJson(2, status: 'REJECTED', rejection: 'DUPLICATE'),
            questionJson(3, status: 'REJECTED', rejection: 'NEW_CODE'),
          ],
        ),
      );
      expect(detail.status, SessionStatus.resolved);
      expect(detail.editable, isFalse);
      expect(detail.countWith(QuestionReviewStatus.approved), 1);
      expect(detail.countWith(QuestionReviewStatus.rejected), 2);
      expect(rejectionLabel('NEW_CODE'), 'Lý do khác');
    });
  });

  group('Validation', () {
    test('valid draft has no errors; confidence 0 is valid', () {
      final draft = validDraft();
      expect(draft.questions.first.confidence, 0);
      expect(QuestionValidation.validate(draft), isEmpty);
    });

    test('requires class, title, 3 questions and complete questions', () {
      final draft = ProposalDraft(
        title: '   \n ',
        sourceUrl: 'ftp://x',
        questions: [QuestionDraft(content: '  ')],
      );
      final errors = QuestionValidation.validate(draft);
      expect(errors['class'], isNotNull);
      expect(errors['title'], isNotNull);
      expect(errors['source_url'], isNotNull);
      expect(errors['questions'], contains('3'));
      expect(errors['q0.content'], isNotNull);
      expect(errors['q0.o0'], isNotNull);
      expect(errors['q0.correct'], isNotNull);
      expect(errors['q0.source'], isNotNull);
      expect(errors['q0.confidence'], isNotNull);
    });

    test('duplicate options, closed class and too many images', () {
      final draft = validDraft(images: 5);
      draft.courseClass = CourseClassOption.fromJson(
        classJson(canPropose: false),
      );
      draft.questions[1].options[1].text = 'đáp án đúng 1';
      final errors = QuestionValidation.validate(draft);
      expect(errors['class'], contains('không còn nhận'));
      expect(errors['q1.o1'], contains('trùng'));
      expect(errors['q0.images'], isNotNull);
      // Khi sửa phiên PENDING, cờ can_propose không chặn.
      expect(
        QuestionValidation.validate(
          validDraft(sessionId: 3)..courseClass = draft.courseClass,
        )['class'],
        isNull,
      );
    });

    test('comment limit counts characters (500), rating range 0..4', () {
      expect(QuestionValidation.comment('a' * 500), isNull);
      expect(QuestionValidation.comment('a' * 501), isNotNull);
      expect(QuestionValidation.comment('  ', required: true), isNotNull);
      expect(QuestionValidation.rating(0), isNull);
      expect(QuestionValidation.rating(4), isNull);
      expect(QuestionValidation.rating(5), isNotNull);
      expect(QuestionValidation.rating(null), isNotNull);
    });

    test('image signature check ignores file extension; rejects GIF/empty', () {
      final png = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10, 0]);
      final gif = Uint8List.fromList('GIF89a....'.codeUnits);
      expect(detectImageKind(png), ImageKind.png);
      expect(detectImageKind(gif), isNull);
      expect(() => validateImageBytes(gif), throwsA(isA<AppFailure>()));
      expect(
        () => validateImageBytes(Uint8List(0)),
        throwsA(isA<AppFailure>()),
      );
      expect(
        () => validateImageBytes(
          Uint8List(QuestionValidation.maxImageBytes + 1)..[0] = 0xff,
        ),
        throwsA(isA<AppFailure>()),
      );
    });
  });

  group('Draft payloads', () {
    test('propose uses llm_generated, media_urls and option objects', () {
      final draft = validDraft(images: 1);
      draft.questions[0].images.first.remoteUrl = 'https://cdn.test/0.jpg';
      final json = draft.toProposeJson();
      expect(json['course_class_id'], 100);
      final questions = json['questions'] as List;
      final first = questions.first as Map<String, dynamic>;
      expect(first['llm_generated'], isFalse);
      expect((questions[1] as Map)['llm_generated'], isTrue);
      expect(first['confidence'], 0);
      expect(first['media_urls'], ['https://cdn.test/0.jpg']);
      expect(first['options'], [
        {'key': 'A', 'text': 'Đáp án đúng 0', 'is_correct': true},
        {'key': 'B', 'text': 'Đáp án sai 0', 'is_correct': false},
      ]);
      expect(first.containsKey('source'), isFalse);
    });

    test('update uses source enum and keeps question IDs', () {
      final detail = SubmissionDetail.fromJson(detailJson(9));
      final draft = ProposalDraft.fromSubmission(detail);
      final json = draft.toUpdateJson();
      final questions = json['questions'] as List;
      expect((questions.first as Map)['question_id'], 1001);
      expect((questions.first as Map)['source'], 'HOMO_SAPIENS');
      expect((questions.first as Map).containsKey('llm_generated'), isFalse);
      expect(draft.questions.first.confidence, 3);
    });

    test('draft JSON round-trip keeps upload state and pending flag', () {
      final draft = validDraft(images: 2)
        ..pending = PendingVerification(
          attemptedAt: DateTime.utc(2026, 11, 10),
          kind: 'propose',
        );
      draft.questions[0].images[0].remoteUrl = 'https://cdn.test/a.jpg';
      final restored = ProposalDraft.fromJson(draft.toJson());
      expect(
        restored.questions[0].images[0].remoteUrl,
        'https://cdn.test/a.jpg',
      );
      expect(restored.questions[0].images[1].uploaded, isFalse);
      expect(restored.pending?.kind, 'propose');
      expect(restored.questions[0].confidence, 0);
      expect(restored.courseClass?.courseClassId, 100);
    });
  });

  group('PagedListController', () {
    PagedListController<SubmissionSummary> controller(
      QbHarness h,
      Future<CursorPage<SubmissionSummary>> Function(int?) fetch,
    ) => PagedListController<SubmissionSummary>(
      fetch: fetch,
      idOf: (s) => s.sessionId,
      cache: h.cache,
      userId: '7',
      encode: (s) => s.toJson(),
      decode: SubmissionSummary.fromJson,
    )..setResource('list');

    test('cold offline shows cache; failed refresh keeps items', () async {
      final h = QbHarness();
      await h.cache.write(
        userId: '7',
        resource: 'list',
        data: [summaryJson(1)],
      );
      final c = controller(h, (_) async => throw AppFailure.offline);
      addTearDown(c.dispose);
      await c.refresh();
      expect(c.items.single.sessionId, 1);
      expect(c.isFromCache, isTrue);
      expect(c.failure?.kind, FailureKind.offline);
      expect(c.isRefreshing, isFalse);
      // Dữ liệu cache không có cursor tin cậy → không tải thêm.
      await c.loadMore();
      expect(c.isLoadingMore, isFalse);
    });

    test('403 removes cached content instead of showing it', () async {
      final h = QbHarness();
      await h.cache.write(
        userId: '7',
        resource: 'list',
        data: [summaryJson(1)],
      );
      final c = controller(
        h,
        (_) async => throw const AppFailure(FailureKind.forbidden, 'Denied'),
      );
      addTearDown(c.dispose);
      await c.refresh();
      expect(c.items, isEmpty);
      expect(await h.cache.read(userId: '7', resource: 'list'), isNull);
    });

    test('stale response after filter change is discarded', () async {
      final h = QbHarness();
      final slow = Completer<CursorPage<SubmissionSummary>>();
      final c = controller(h, (_) => slow.future);
      addTearDown(c.dispose);
      final first = c.refresh();
      final second = c.reset(
        (_) async =>
            CursorPage(items: [SubmissionSummary.fromJson(summaryJson(2))]),
        resource: 'list-2',
      );
      await second;
      slow.complete(
        CursorPage(items: [SubmissionSummary.fromJson(summaryJson(1))]),
      );
      await first;
      expect(c.items.map((s) => s.sessionId), [2]);
    });

    test('load more dedupes and stops when cursor repeats', () async {
      final h = QbHarness();
      var calls = 0;
      final c = controller(h, (after) async {
        calls++;
        return CursorPage(
          items: [
            SubmissionSummary.fromJson(summaryJson(after == null ? 1 : 2)),
            SubmissionSummary.fromJson(summaryJson(1)),
          ],
          after: 5,
          hasNext: true,
        );
      });
      addTearDown(c.dispose);
      await c.refresh();
      await c.loadMore();
      expect(c.items.map((s) => s.sessionId), [1, 2]);
      expect(c.hasNext, isFalse);
      await c.loadMore();
      expect(calls, 2);
    });
  });

  group('Repository', () {
    test('query params and business error mapping', () async {
      final h = QbHarness();
      await h.signIn();
      final repo = QuestionBankRepository(h.api);
      h.adapter.json('GET', 'sessions/my-submissions', page([summaryJson(1)]));
      await repo.mySubmissions(after: 9, status: SessionStatus.reviewing);
      final query = h.adapter.requests.last.queryParameters;
      expect(query['after'], 9);
      expect(query['status'], 'REVIEWING');
      expect(query['limit'], 20);

      h.adapter.json('GET', 'sessions/practice-catalog', page([]));
      await repo.practiceCatalog(query: '  ${'ă' * 130}  ');
      expect(
        (h.adapter.requests.last.queryParameters['q'] as String).runes.length,
        120,
      );

      h.adapter.on(
        'DELETE',
        'sessions/my-submissions/3',
        (_) async => envelope(null, status: 400, code: '2002'),
      );
      await expectLater(
        repo.deleteSubmission(3),
        throwsA(
          isA<AppFailure>().having(
            (f) => f.message,
            'message',
            contains('giảng viên xử lý'),
          ),
        ),
      );

      // HTTP 200 nhưng code nghiệp vụ lỗi vẫn là thất bại.
      h.adapter.on(
        'POST',
        'questions/5/rate',
        (_) async => envelope(null, code: '1004'),
      );
      await expectLater(repo.rate(5, 0), throwsA(isA<AppFailure>()));
      expect(bodyOf(h.adapter.requests.last)['rating'], 0);
    });
  });

  group('ProposalComposerController', () {
    late QbHarness h;
    late FakeImages images;
    setUp(() async {
      h = QbHarness();
      images = FakeImages();
      await h.signIn();
      h.adapter.json('GET', 'sessions/my-enrolled-course-classes', [
        classJson(),
      ]);
    });

    Future<ProposalComposerController> open({
      SubmissionDetail? editing,
      String user = '7',
    }) async {
      final c = ProposalComposerController(
        repository: QuestionBankRepository(h.api),
        drafts: h.drafts,
        cache: h.cache,
        images: images,
        userId: user,
        editing: editing,
      );
      addTearDown(c.dispose);
      await c.init();
      await Future<void>.delayed(Duration.zero);
      return c;
    }

    int posts() => h.adapter.called('POST', 'sessions/propose').length;

    test(
      'invalid input is reported before any network call, even offline',
      () async {
        h.connection.value = ConnectionStatus.offline;
        final c = await open();
        h.adapter.requests.clear();
        expect(await c.submit(), isNull);
        expect(c.errors['title'], isNotNull);
        expect(c.message, contains('kiểm tra lại'));
        expect(h.adapter.requests, isEmpty);
      },
    );

    test('offline submit keeps draft and sends nothing', () async {
      final c = await open();
      c.draft = validDraft();
      h.connection.value = ConnectionStatus.offline;
      h.adapter.requests.clear();
      expect(await c.submit(), isNull);
      expect(h.adapter.requests, isEmpty);
      expect(c.message, contains('Không có kết nối mạng'));
      expect(c.hasPendingVerification, isFalse);
      final saved = await h.drafts.read(userId: '7', name: 'qb-proposal-new');
      expect(ProposalDraft.fromJson(saved!).title, 'Ôn tập chương 3');
    });

    test('uploads images once, proposes, then removes draft', () async {
      h.adapter.json('POST', 'sessions/propose', {
        'session_id': 55,
        'status': 'PENDING',
      }, status: 201);
      final c = await open();
      c.draft = validDraft(images: 2);
      final outcome = await c.submit();
      expect(outcome, isA<ProposalCreated>());
      expect(outcome!.sessionId, 55);
      expect(images.uploads, ['/drafts/7/0.jpg', '/drafts/7/1.jpg']);
      final body = bodyOf(h.adapter.called('POST', 'sessions/propose').single);
      expect((body['questions'] as List).first['media_urls'], [
        'https://cdn.test/0.jpg',
        'https://cdn.test/1.jpg',
      ]);
      expect(await h.drafts.read(userId: '7', name: 'qb-proposal-new'), isNull);
      expect(images.discarded, hasLength(2));
    });

    test(
      'failed second upload keeps first URL; retry uploads only the rest',
      () async {
        images.failOnUpload[2] = AppFailure.offline;
        h.adapter.json('POST', 'sessions/propose', {'session_id': 56});
        final c = await open();
        c.draft = validDraft(images: 2);
        expect(await c.submit(), isNull);
        expect(posts(), 0);
        expect(c.message, contains('Đã tải 1/2'));
        final saved = ProposalDraft.fromJson(
          (await h.drafts.read(userId: '7', name: 'qb-proposal-new'))!,
        );
        expect(saved.questions[0].images[0].remoteUrl, isNotNull);
        expect(saved.questions[0].images[1].remoteUrl, isNull);
        expect(await c.submit(), isA<ProposalCreated>());
        expect(images.uploads, [
          '/drafts/7/0.jpg',
          '/drafts/7/1.jpg',
          '/drafts/7/1.jpg',
        ]);
      },
    );

    test('timeout keeps pending; retry finds created session without re-POST', () async {
      h.adapter.on('POST', 'sessions/propose', (o) async => timeout(o));
      final c = await open();
      c.draft = validDraft();
      expect(await c.submit(), isNull);
      expect(c.hasPendingVerification, isTrue);
      expect(c.message, contains('Chưa xác nhận'));
      expect(posts(), 1);

      // Mở lại màn (giả lập app bị đóng): cờ pending vẫn còn trong nháp.
      final reopened = await open();
      expect(reopened.hasPendingVerification, isTrue);
      h.adapter.json(
        'GET',
        'sessions/my-submissions',
        page([
          // Phiên cũ cùng tiêu đề (trước lần gửi rất lâu) không được nhận nhầm.
          summaryJson(
            70,
            title: 'Ôn tập chương 3',
            createdAt: '2026-01-01T00:00:00Z',
          ),
          summaryJson(
            77,
            title: 'Ôn tập chương 3',
            createdAt: DateTime.now().toUtc().toIso8601String(),
          ),
        ]),
      );
      final outcome = await reopened.submit();
      expect(outcome, isA<ProposalFoundExisting>());
      expect(outcome!.sessionId, 77);
      expect(posts(), 1, reason: 'Không gửi lại POST khi server đã tạo phiên');
      expect(
        h.adapter
            .called('GET', 'sessions/my-submissions')
            .last
            .queryParameters['q'],
        'Ôn tập chương 3',
      );
      expect(await h.drafts.read(userId: '7', name: 'qb-proposal-new'), isNull);
    });

    test(
      'verification offline does not resend; verified absent then resends',
      () async {
        h.adapter.on('POST', 'sessions/propose', (o) async => timeout(o));
        final c = await open();
        c.draft = validDraft();
        await c.submit();
        h.connection.value = ConnectionStatus.offline;
        expect(await c.submit(), isNull);
        expect(c.hasPendingVerification, isTrue);
        expect(c.message, contains('Chưa kiểm tra được'));
        expect(posts(), 1);

        h.connection.value = ConnectionStatus.available;
        h.adapter.json('GET', 'sessions/my-submissions', page([]));
        h.adapter.json('POST', 'sessions/propose', {'session_id': 90});
        expect(await c.submit(), isA<ProposalCreated>());
        expect(posts(), 2);
      },
    );

    test('server rejection (400) clears pending and keeps draft', () async {
      h.adapter.on(
        'POST',
        'sessions/propose',
        (_) async => envelope(null, status: 400, code: '1004'),
      );
      final c = await open();
      c.draft = validDraft();
      expect(await c.submit(), isNull);
      expect(c.hasPendingVerification, isFalse);
      expect(
        await h.drafts.read(userId: '7', name: 'qb-proposal-new'),
        isNotNull,
      );
    });

    test(
      'edit: session no longer PENDING locks form but keeps input',
      () async {
        final detail = SubmissionDetail.fromJson(detailJson(9));
        h.adapter.on(
          'PUT',
          'sessions/my-submissions/9',
          (_) async => envelope(null, status: 403, code: '1009'),
        );
        final c = await open(editing: detail);
        c.draft.title = 'Tiêu đề đã sửa';
        expect(await c.submit(), isNull);
        expect(c.locked, isTrue);
        expect(c.draft.title, 'Tiêu đề đã sửa');
        final saved = await h.drafts.read(
          userId: '7',
          name: 'qb-proposal-edit-9',
        );
        expect(saved?['title'], 'Tiêu đề đã sửa');
      },
    );

    test(
      'edit timeout: retry adopts server IDs so new question is not duplicated',
      () async {
        final detail = SubmissionDetail.fromJson(detailJson(9));
        h.adapter.on(
          'PUT',
          'sessions/my-submissions/9',
          (o) async => timeout(o),
        );
        final c = await open(editing: detail);
        c.draft.questions.add(
          QuestionDraft(
            content: 'Câu mới',
            source: QuestionSource.human,
            confidence: 2,
            options: [
              OptionDraft(text: 'X', correct: true),
              OptionDraft(text: 'Y'),
            ],
          ),
        );
        expect(await c.submit(), isNull);
        expect(c.hasPendingVerification, isTrue);
        h.adapter.json(
          'GET',
          'sessions/my-submissions/9',
          detailJson(
            9,
            questions: [
              questionJson(1001),
              questionJson(1002),
              questionJson(1003),
              {...questionJson(1004), 'content': 'Câu mới'},
            ],
          ),
        );
        h.adapter.json('PUT', 'sessions/my-submissions/9', {});
        expect(await c.submit(), isA<ProposalUpdated>());
        final body = bodyOf(
          h.adapter.called('PUT', 'sessions/my-submissions/9').last,
        );
        expect((body['questions'] as List).last['question_id'], 1004);
      },
    );

    test('drafts are isolated per account', () async {
      final a = await open();
      a.draft.title = 'Nháp của A';
      await a.saveDraft();
      final b = await open(user: '8');
      expect(b.draft.title, isEmpty);
      expect(b.restoredFromDraft, isFalse);
      final again = await open();
      expect(again.draft.title, 'Nháp của A');
      expect(again.restoredFromDraft, isTrue);
    });

    test('picker denial keeps draft and shows Vietnamese guidance', () async {
      final c = await open();
      images.pickFailure = const AppFailure(
        FailureKind.rejected,
        'Ứng dụng chưa được cấp quyền camera.',
      );
      await c.addImage(c.draft.questions.first, camera: true);
      expect(c.message, contains('quyền camera'));
      expect(c.pickingImage, isFalse);
      images.pickFailure = null;
      await c.addImage(c.draft.questions.first, camera: false);
      expect(c.draft.questions.first.images, hasLength(1));
    });
  });
}
