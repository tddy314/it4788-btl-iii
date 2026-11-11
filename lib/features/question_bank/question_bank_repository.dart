import 'package:dio/dio.dart';

import '../../core/errors/app_failure.dart';
import '../../core/network/api_client.dart';
import 'question_models.dart';

/// Gọi API ngân hàng câu hỏi qua ApiClient chung. Không retry thao tác ghi.
/// Không gọi API giảng viên/admin (`lecturer/*`, `admin/*`).
class QuestionBankRepository {
  QuestionBankRepository(this.api);
  final ApiClient api;

  static const pageSize = 20;

  Future<List<CourseClassOption>> enrolledClasses({CancelToken? cancelToken}) =>
      _describe(
        () => api.get(
          'sessions/my-enrolled-course-classes',
          cancelToken: cancelToken,
          decode: (data) => [
            for (final item in qbList(data)) CourseClassOption.fromJson(item),
          ],
        ),
      );

  Future<List<SubjectItem>> subjects({CancelToken? cancelToken}) => _describe(
    () => api.get(
      'subjects',
      cancelToken: cancelToken,
      decode: (data) => [
        for (final item in qbList(data)) SubjectItem.fromJson(item),
      ],
    ),
  );

  Future<CursorPage<SubmissionSummary>> mySubmissions({
    int? after,
    SessionStatus? status,
    String? query,
    int limit = pageSize,
    CancelToken? cancelToken,
  }) => _describe(
    () => api.get(
      'sessions/my-submissions',
      cancelToken: cancelToken,
      query: {
        'limit': limit,
        'after': ?after,
        if (status != null && status != SessionStatus.unknown)
          'status': status.wire,
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
      },
      decode: (data) =>
          CursorPage.parse(data, 'contents', SubmissionSummary.fromJson),
    ),
  );

  Future<SubmissionDetail> submissionDetail(
    int sessionId, {
    CancelToken? cancelToken,
  }) => _describe(
    () => api.get(
      'sessions/my-submissions/$sessionId',
      cancelToken: cancelToken,
      decode: SubmissionDetail.fromJson,
    ),
  );

  Future<ProposeResult> propose(
    Map<String, dynamic> body, {
    CancelToken? cancelToken,
  }) => _describe(
    () => api.request(
      'sessions/propose',
      method: 'POST',
      data: body,
      cancelToken: cancelToken,
      decode: ProposeResult.fromJson,
    ),
    write: true,
  );

  Future<void> updateSubmission(
    int sessionId,
    Map<String, dynamic> body, {
    CancelToken? cancelToken,
  }) => _describe(
    () => api.request<void>(
      'sessions/my-submissions/$sessionId',
      method: 'PUT',
      data: body,
      cancelToken: cancelToken,
      decode: (_) {},
    ),
    write: true,
  );

  Future<void> deleteSubmission(int sessionId, {CancelToken? cancelToken}) =>
      _describe(
        () => api.request<void>(
          'sessions/my-submissions/$sessionId',
          method: 'DELETE',
          cancelToken: cancelToken,
          decode: (_) {},
        ),
        write: true,
      );

  Future<CursorPage<PracticeSetSummary>> practiceCatalog({
    int? after,
    int? subjectId,
    String? query,
    int limit = pageSize,
    CancelToken? cancelToken,
  }) => _describe(
    () => api.get(
      'sessions/practice-catalog',
      cancelToken: cancelToken,
      query: {
        'limit': limit,
        'after': ?after,
        'subject_id': ?subjectId,
        // Swagger giới hạn 120 ký tự; cắt theo rune để không vỡ ký tự.
        if (query != null && query.trim().isNotEmpty)
          'q': String.fromCharCodes(query.trim().runes.take(120)),
      },
      decode: (data) =>
          CursorPage.parse(data, 'contents', PracticeSetSummary.fromJson),
    ),
  );

  Future<PracticeSession> practiceQuestions(
    int sessionId, {
    CancelToken? cancelToken,
  }) => _describe(
    () => api.get(
      'sessions/$sessionId/questions',
      cancelToken: cancelToken,
      decode: PracticeSession.fromJson,
    ),
  );

  Future<AnswerResult> answer(
    int questionId,
    List<String> selected, {
    String? questionUpdatedAt,
    CancelToken? cancelToken,
  }) => _describe(
    () => api.request(
      'questions/$questionId/answer',
      method: 'POST',
      cancelToken: cancelToken,
      data: {
        'selected_options': selected,
        'question_updated_at': ?questionUpdatedAt,
      },
      decode: AnswerResult.fromJson,
    ),
    write: true,
  );

  Future<RateResult> rate(
    int questionId,
    int rating, {
    String? comment,
    CancelToken? cancelToken,
  }) => _describe(
    () => api.request(
      'questions/$questionId/rate',
      method: 'POST',
      cancelToken: cancelToken,
      data: {
        'rating': rating,
        if (comment != null && comment.trim().isNotEmpty)
          'comment': comment.trim(),
      },
      decode: RateResult.fromJson,
    ),
    write: true,
  );

  Future<CursorPage<RatingItem>> ratings(
    int questionId, {
    int? after,
    int limit = pageSize,
    CancelToken? cancelToken,
  }) => _describe(
    () => api.get(
      'questions/$questionId/ratings',
      cancelToken: cancelToken,
      query: {'limit': limit, 'after': ?after},
      decode: (data) => CursorPage.parse(data, 'items', RatingItem.fromJson),
    ),
  );

  Future<void> report(
    int questionId,
    String description, {
    CancelToken? cancelToken,
  }) => _describe(
    () => api.request<void>(
      'questions/$questionId/report',
      method: 'PUT',
      cancelToken: cancelToken,
      data: {'description': description.trim()},
      decode: (_) {},
    ),
    write: true,
  );

  /// Bổ sung thông báo nghiệp vụ cho mã lỗi trong PDF, không sửa core.
  static Future<T> _describe<T>(
    Future<T> Function() call, {
    bool write = false,
  }) async {
    try {
      return await call();
    } on AppFailure catch (failure) {
      throw describeFailure(failure, write: write);
    }
  }

  static AppFailure describeFailure(AppFailure failure, {bool write = false}) {
    String? message = switch (failure.code) {
      '2001' => 'Không tìm thấy câu hỏi. Câu hỏi có thể đã bị xóa.',
      '2002' => 'Phiên đã được giảng viên xử lý nên không thể sửa hoặc xóa.',
      '2003' =>
        'Hệ thống phát hiện câu hỏi trùng với câu đã có trong ngân hàng.',
      '2007' => 'Câu hỏi đã bị tác giả ẩn hoặc xóa.',
      '2008' => 'Không tìm thấy phiên đề xuất hoặc đợt đề xuất đã kết thúc.',
      '1009' || '2006' => 'Bạn không có quyền thực hiện thao tác này.',
      '1011' => 'Nội dung vi phạm tiêu chuẩn cộng đồng.',
      _ => null,
    };
    if (message == null && failure.kind == FailureKind.timeout && write) {
      message =
          'Chưa xác nhận được kết quả từ máy chủ. Ứng dụng không tự gửi lại; '
          'hãy kiểm tra trước khi thử lại.';
    }
    if (message == null) return failure;
    return AppFailure(
      failure.kind,
      message,
      code: failure.code,
      statusCode: failure.statusCode,
    );
  }
}

/// Thao tác ghi có thể đã được server xử lý dù app không nhận được phản hồi.
bool isUncertainWrite(AppFailure failure) => switch (failure.kind) {
  FailureKind.timeout ||
  FailureKind.server ||
  FailureKind.unknown ||
  FailureKind.invalidData => true,
  _ => false,
};
