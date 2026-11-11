import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:it4788_btl/core/network/connection_monitor.dart';
import 'package:it4788_btl/features/auth/auth_application.dart';
import 'package:it4788_btl/features/question_bank/practice_screen.dart';
import 'package:it4788_btl/features/question_bank/proposal_composer_screen.dart';
import 'package:it4788_btl/features/question_bank/submission_detail_screen.dart';

import 'qb_fakes.dart';

Future<QbHarness> pumpApp(
  WidgetTester tester, {
  void Function(QbHarness)? setup,
  bool openTab = true,
}) async {
  FlutterSecureStorage.setMockInitialValues({});
  final h = QbHarness();
  await h.signIn();
  h.adapter.json('GET', 'sessions/my-submissions', page([]));
  h.adapter.json('GET', 'sessions/practice-catalog', page([]));
  h.adapter.json('GET', 'subjects', [
    {'subject_id': 10, 'code': 'IT3080', 'name': 'Hệ điều hành'},
  ]);
  h.adapter.json('GET', 'sessions/my-enrolled-course-classes', [classJson()]);
  setup?.call(h);
  await tester.pumpWidget(AuthApplication(dependencies: h.dependencies));
  await tester.pumpAndSettle();
  if (openTab) {
    await tester.tap(find.text('Ngân hàng'));
    await tester.pumpAndSettle();
  }
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    h.dependencies.dispose();
  });
  return h;
}

/// Scrollable chính của màn đang hiển thị (ListView hoặc SingleChildScrollView),
/// bỏ qua Scrollable bên trong ô nhập nhiều dòng.
Finder mainList() => find
    .descendant(
      of: find
          .byWidgetPredicate((w) => w is ListView || w is SingleChildScrollView)
          .first,
      matching: find.byType(Scrollable),
    )
    .first;

Future<void> reveal(
  WidgetTester tester,
  Finder finder, {
  double delta = 250,
}) async {
  await tester.scrollUntilVisible(finder, delta, scrollable: mainList());
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('My submissions: list, status filter and partial result detail', (
    tester,
  ) async {
    final h = await pumpApp(
      tester,
      setup: (h) {
        h.adapter.json(
          'GET',
          'sessions/my-submissions',
          page([
            summaryJson(
              1,
              title: 'Ôn tập chương 1',
              status: 'RESOLVED',
              approved: 1,
            ),
            summaryJson(2, title: 'Ôn tập chương 2'),
          ]),
        );
        h.adapter.json(
          'GET',
          'sessions/my-submissions/1',
          detailJson(
            1,
            status: 'RESOLVED',
            questions: [
              questionJson(11, status: 'APPROVED'),
              questionJson(12, status: 'REJECTED', rejection: 'DUPLICATE'),
              questionJson(13, status: 'REJECTED', rejection: 'LOW_QUALITY'),
            ],
          ),
        );
      },
    );
    expect(find.text('Ôn tập chương 1'), findsOneWidget);
    expect(find.text('Được chọn 1/3'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Đang duyệt'));
    await tester.pumpAndSettle();
    expect(
      h.adapter
          .called('GET', 'sessions/my-submissions')
          .last
          .queryParameters['status'],
      'REVIEWING',
    );

    await tester.tap(find.widgetWithText(ChoiceChip, 'Tất cả'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ôn tập chương 1'));
    await tester.pumpAndSettle();
    expect(find.byType(SubmissionDetailScreen), findsOneWidget);
    expect(
      find.textContaining('được chọn 1 · không được chọn 2'),
      findsOneWidget,
    );
    expect(
      find.textContaining('không có nghĩa mọi câu đều được chọn'),
      findsOneWidget,
    );
    await reveal(tester, find.textContaining('Trùng với câu hỏi đã có'));
    expect(find.textContaining('Trùng với câu hỏi đã có'), findsOneWidget);
    // RESOLVED: không cho sửa/xóa.
    expect(find.byTooltip('Sửa đề xuất'), findsNothing);
    expect(find.byTooltip('Xóa đề xuất'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Offline cold start shows cached list and does not fake data', (
    tester,
  ) async {
    await pumpApp(
      tester,
      setup: (h) {
        h.connection.value = ConnectionStatus.offline;
        h.cache.write(
          userId: '7',
          resource: 'qb.my-submissions.ALL',
          data: [summaryJson(3, title: 'Đã lưu trên máy')],
        );
      },
    );
    expect(find.text('Đã lưu trên máy'), findsOneWidget);
    expect(find.textContaining('Không thể kết nối mạng'), findsWidgets);
    // Kho luyện tập chưa có cache → trạng thái lỗi có nút Thử lại, không bịa dữ liệu.
    await tester.tap(find.text('Luyện tập'));
    await tester.pumpAndSettle();
    expect(find.text('Thử lại'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Composer validates before network; fits small screen + large font',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      final h = await pumpApp(tester);
      await tester.tap(find.text('Đề xuất câu hỏi'));
      await tester.pumpAndSettle();
      expect(find.byType(ProposalComposerScreen), findsOneWidget);
      h.adapter.requests.clear();
      final submit = find.text('Gửi đề xuất');
      await reveal(tester, submit, delta: 300);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(h.adapter.called('POST', 'sessions/propose'), isEmpty);
      expect(find.textContaining('kiểm tra lại các mục'), findsOneWidget);
      await reveal(
        tester,
        find.text('Vui lòng nhập tiêu đề bộ câu hỏi.'),
        delta: -300,
      );
      expect(find.text('Vui lòng chọn lớp học phần.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Composer submits a full proposal and opens its detail', (
    tester,
  ) async {
    final h = await pumpApp(
      tester,
      setup: (h) {
        h.adapter.json('POST', 'sessions/propose', {
          'session_id': 40,
          'status': 'PENDING',
        }, status: 201);
        h.adapter.json('GET', 'sessions/my-submissions/40', detailJson(40));
      },
    );
    await tester.tap(find.text('Đề xuất câu hỏi'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Lớp 1717100').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Tiêu đề bộ câu hỏi *'),
      'Ôn tập',
    );
    for (var i = 0; i < 3; i++) {
      final card = find.ancestor(
        of: find.text('Câu ${i + 1}'),
        matching: find.byType(Card),
      );
      await reveal(tester, find.text('Câu ${i + 1}'), delta: 300);
      await tester.enterText(
        find.descendant(
          of: card,
          matching: find.widgetWithText(TextFormField, 'Nội dung câu hỏi *'),
        ),
        'Câu hỏi số $i',
      );
      await tester.enterText(
        find.descendant(
          of: card,
          matching: find.widgetWithText(TextFormField, 'Đáp án A'),
        ),
        'Đúng $i',
      );
      await tester.enterText(
        find.descendant(
          of: card,
          matching: find.widgetWithText(TextFormField, 'Đáp án B'),
        ),
        'Sai $i',
      );
      await tapVisible(
        tester,
        find.descendant(of: card, matching: find.byType(Checkbox)).first,
      );
      final human = find.descendant(
        of: card,
        matching: find.text('Tự biên soạn'),
      );
      await tapVisible(tester, human);
      final zero = find.descendant(
        of: card,
        matching: find.text('0 · Sai hoàn toàn'),
      );
      await tapVisible(tester, zero);
    }
    await tapVisible(tester, find.text('Gửi đề xuất'));
    final post = h.adapter.called('POST', 'sessions/propose').single;
    final body = bodyOf(post);
    expect(body['course_class_id'], 100);
    expect(body['title'], 'Ôn tập');
    final first = (body['questions'] as List).first as Map;
    expect(first['confidence'], 0);
    expect(first['llm_generated'], isFalse);
    expect(first['options'], [
      {'key': 'A', 'text': 'Đúng 0', 'is_correct': true},
      {'key': 'B', 'text': 'Sai 0', 'is_correct': false},
    ]);
    expect(find.byType(SubmissionDetailScreen), findsOneWidget);
    expect(find.textContaining('Đã gửi đề xuất'), findsOneWidget);
    expect(await h.drafts.read(userId: '7', name: 'qb-proposal-new'), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Practice: answer graded by server, 409 reloads, rating 0 allowed',
    (tester) async {
      var answeredOnServer = false;
      final h = await pumpApp(
        tester,
        setup: (h) {
          h.adapter.json(
            'GET',
            'sessions/practice-catalog',
            page([
              {
                'session_id': 8,
                'title': 'Ôn tập HĐH',
                'subject_name': 'Hệ điều hành',
                'subject_code': 'IT3080',
                'question_counts': 2,
              },
            ]),
          );
          h.adapter.on(
            'GET',
            'sessions/8/questions',
            (_) async => envelope(
              practiceJson(8, [
                practiceQuestionJson(81),
                practiceQuestionJson(
                  82,
                  answered: answeredOnServer,
                  correct: 'A',
                  wasCorrect: false,
                  selected: ['B'],
                ),
              ]),
            ),
          );
          h.adapter.json('POST', 'questions/81/answer', {
            'is_correct': false,
            'correct_answer': 'A',
            'explanation': 'A mới đúng',
          });
          h.adapter.on('POST', 'questions/82/answer', (_) async {
            answeredOnServer = true;
            return envelope(null, status: 409, code: '1010');
          });
          h.adapter.json('POST', 'questions/81/rate', {
            'new_avg_rating': 1.0,
            'new_rating_count': 3,
          });
        },
      );
      await tester.tap(find.text('Luyện tập'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ôn tập HĐH'));
      await tester.pumpAndSettle();
      expect(find.byType(PracticeScreen), findsOneWidget);
      // Nguồn câu hỏi (LLM) không bị lộ trên màn luyện tập.
      expect(find.textContaining('AI'), findsNothing);

      // Chưa chọn đáp án → báo lỗi, không gọi mạng.
      await tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'Trả lời').first,
      );
      expect(find.text('Hãy chọn ít nhất một đáp án.'), findsOneWidget);
      expect(h.adapter.called('POST', 'questions/81/answer'), isEmpty);

      await tapVisible(tester, find.text('B. Phương án B').first);
      await tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'Trả lời').first,
      );
      expect(
        bodyOf(h.adapter.called('POST', 'questions/81/answer').single),
        containsPair('selected_options', ['B']),
      );
      expect(find.text('Chưa đúng'), findsOneWidget);
      expect(find.text('Đáp án đúng: A'), findsOneWidget);
      expect(find.text('Giải thích: A mới đúng'), findsOneWidget);

      // Câu 2: server báo đã trả lời → tải lại và hiện kết quả server.
      final second = find.text('A. Phương án A').last;
      await reveal(tester, second, delta: 200);
      await tapVisible(tester, second);
      final answer2 = find.widgetWithText(FilledButton, 'Trả lời');
      await reveal(tester, answer2, delta: 200);
      await tapVisible(tester, answer2);
      expect(h.adapter.called('GET', 'sessions/8/questions'), hasLength(2));
      expect(find.text('Đáp án đúng: A'), findsWidgets);

      // Đánh giá 0 là giá trị hợp lệ.
      final rate = find.text('Đánh giá').first;
      await reveal(tester, rate, delta: -200);
      await tapVisible(tester, rate);
      await tester.tap(find.text('0 · Rất kém'));
      await tester.tap(find.text('Lưu đánh giá'));
      await tester.pumpAndSettle();
      final rateBody = bodyOf(
        h.adapter.called('POST', 'questions/81/rate').single,
      );
      expect(rateBody['rating'], 0);
      expect(rateBody.containsKey('comment'), isFalse);
      expect(find.text('Đã lưu đánh giá.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Delete timeout is verified by reloading, not by resending', (
    tester,
  ) async {
    final h = await pumpApp(
      tester,
      setup: (h) {
        h.adapter.json(
          'GET',
          'sessions/my-submissions',
          page([summaryJson(5, title: 'Sẽ xóa')]),
        );
        h.adapter.json('GET', 'sessions/my-submissions/5', detailJson(5));
        h.adapter.on('DELETE', 'sessions/my-submissions/5', (o) async {
          // Server đã xóa nhưng phản hồi bị mất.
          h.adapter.json('GET', 'sessions/my-submissions/5', null, status: 404);
          return timeout(o);
        });
      },
    );
    await tester.tap(find.text('Sẽ xóa'));
    await tester.pumpAndSettle();
    h.adapter.json('GET', 'sessions/my-submissions', page([]));
    await tester.tap(find.byTooltip('Xóa đề xuất'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Xóa'));
    await tester.pumpAndSettle();
    expect(
      h.adapter.called('DELETE', 'sessions/my-submissions/5'),
      hasLength(1),
    );
    expect(find.byType(SubmissionDetailScreen), findsNothing);
    expect(find.text('Đã xóa đề xuất.'), findsOneWidget);
    expect(find.text('Sẽ xóa'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
