import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:it4788_btl/app/app_dependencies.dart';
import 'package:it4788_btl/core/config/app_config.dart';
import 'package:it4788_btl/core/errors/app_failure.dart';
import 'package:it4788_btl/core/network/api_client.dart';
import 'package:it4788_btl/core/storage/draft_store.dart';
import 'package:it4788_btl/core/storage/json_cache.dart';
import 'package:it4788_btl/core/storage/session_store.dart';
import 'package:it4788_btl/features/question_bank/question_image_service.dart';

import '../../support/fakes.dart';

typedef Handler = Future<ResponseBody> Function(RequestOptions options);

/// Giả lập server theo "METHOD path" (path sau /api/v1/). Ghi lại mọi request.
class RouteAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  final routes = <String, Handler>{};

  void on(String method, String path, Handler handler) =>
      routes['${method.toUpperCase()} $path'] = handler;

  void json(String method, String path, Object? data, {int status = 200}) =>
      on(method, path, (_) async => envelope(data, status: status));

  List<RequestOptions> called(String method, String path) => [
    for (final r in requests)
      if (r.method == method.toUpperCase() && _path(r) == path) r,
  ];

  static String _path(RequestOptions options) =>
      options.uri.path.replaceFirst('/api/v1/', '');

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final handler = routes['${options.method} ${_path(options)}'];
    if (handler == null) return envelope(null, status: 404, code: '9999');
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody envelope(Object? data, {int status = 200, String code = '1000'}) =>
    ResponseBody.fromString(
      jsonEncode({'code': code, 'message': 'msg', 'data': data}),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

Never timeout(RequestOptions options) => throw DioException(
  requestOptions: options,
  type: DioExceptionType.receiveTimeout,
);

Map<String, dynamic> bodyOf(RequestOptions options) => options.data is String
    ? jsonDecode(options.data as String) as Map<String, dynamic>
    : options.data as Map<String, dynamic>;

class QbHarness {
  QbHarness() {
    api = ApiClient(
      config: config,
      session: session,
      connection: connection,
      dio: Dio()..httpClientAdapter = adapter,
    );
    dependencies = AppDependencies(
      config: config,
      session: session,
      connection: connection,
      cache: cache,
      drafts: drafts,
      api: api,
    );
  }
  final config = AppConfig();
  final adapter = RouteAdapter();
  final session = SessionStore(MemoryStore());
  final connection = FakeConnection();
  final cacheStore = MemoryStore();
  final draftStore = MemoryStore();
  late final cache = JsonCache(cacheStore);
  late final drafts = DraftStore(draftStore);
  late final ApiClient api;
  late final AppDependencies dependencies;

  Future<void> signIn([String userId = '7']) => session.save(
    SessionTokens(
      userId: userId,
      accessToken: 'test-access-$userId',
      refreshToken: 'test-refresh-$userId',
    ),
  );
}

/// Ảnh giả: không mở picker, ghi lại upload.
class FakeImages implements QuestionImageService {
  final uploads = <String>[];
  final discarded = <String>[];
  var _next = 0;
  String? pickResult;
  AppFailure? pickFailure;

  /// Trả lỗi cho lần upload thứ n (bắt đầu từ 1) rồi gỡ.
  final failOnUpload = <int, AppFailure>{};

  @override
  Future<String?> pick({required bool camera, required String userId}) async {
    if (pickFailure case final failure?) throw failure;
    return pickResult ?? '/drafts/$userId/${_next++}.jpg';
  }

  @override
  Future<String> upload(String localPath, {CancelToken? cancelToken}) async {
    final attempt = uploads.length + 1;
    uploads.add(localPath);
    final failure = failOnUpload.remove(attempt);
    if (failure != null) throw failure;
    return 'https://cdn.test/${localPath.split('/').last}';
  }

  @override
  Future<void> discard(String localPath) async => discarded.add(localPath);
}

Map<String, Object?> classJson({
  int id = 100,
  bool canPropose = true,
  String code = 'IT4788',
}) => {
  'course_class_id': id,
  'class_code': '1717$id',
  'subject_id': 10,
  'subject_code': code,
  'subject_name': 'Phát triển ứng dụng đa nền tảng',
  'semester_id': 2,
  'semester_name': '20261',
  'active_semester': canPropose,
  'can_propose': canPropose,
};

Map<String, Object?> summaryJson(
  int id, {
  String status = 'PENDING',
  String? title,
  int questions = 3,
  int? approved,
  String createdAt = '2026-11-10T08:00:00Z',
}) => {
  'session_id': id,
  'session_code': 'IT4788_$id',
  'title': title ?? 'Bộ câu hỏi $id',
  'content': 'Mô tả $id',
  'subject_id': 10,
  'subject_name': 'Phát triển ứng dụng đa nền tảng',
  'subject_code': 'IT4788',
  'course_class_id': 100,
  'class_code': '171746',
  'status': status,
  'question_counts': questions,
  'approved_question_count': approved,
  'created_at': createdAt,
  'react_count': 0,
  'comment_count': 0,
};

Map<String, Object?> page(
  List<Object?> items, {
  int? after,
  bool hasNext = false,
  String key = 'contents',
}) => {
  key: items,
  'pagination': {'after': after, 'has_next': hasNext},
};

Map<String, Object?> questionJson(
  int id, {
  String? status,
  String? rejection,
  String content = 'Câu hỏi',
}) => {
  'question_id': id,
  'content': '$content $id',
  'image_urls': <String>[],
  'options': [
    {'key': 'A', 'text': 'Đúng', 'is_correct': true},
    {'key': 'B', 'text': 'Sai', 'is_correct': false},
  ],
  'explanation': 'Vì A đúng',
  'source': 'HOMO_SAPIENS',
  'confidence_score': 3.0,
  'status': status,
  'rejection_code': rejection,
  'rejection_reason': rejection == null ? null : 'Trùng câu 12',
};

Map<String, Object?> detailJson(
  int id, {
  String status = 'PENDING',
  List<Map<String, Object?>>? questions,
}) => {
  ...summaryJson(id, status: status),
  'source_url': null,
  'reviewed_by_lecturer': status == 'PENDING' ? null : 'TS. Nguyễn Văn B',
  'reviewed_at': status == 'PENDING' ? null : '2026-11-11T08:00:00Z',
  'questions':
      questions ?? [questionJson(1001), questionJson(1002), questionJson(1003)],
};

Map<String, Object?> practiceQuestionJson(
  int id, {
  bool answered = false,
  String? correct,
  bool? wasCorrect,
  List<String> selected = const [],
}) => {
  'question_id': id,
  'question_code': 'Q$id',
  'content': 'Câu luyện tập $id',
  'image_urls': <String>[],
  'options': [
    {'key': 'A', 'text': 'Phương án A'},
    {'key': 'B', 'text': 'Phương án B'},
  ],
  'source': 'LLM',
  'updated_at': '2026-11-10T09:00:00Z',
  'my_interaction': {'answered': answered, 'rated': false, 'reported': false},
  'hidden_fields': answered
      ? {
          'correct_answer': correct,
          'explanation': 'Giải thích $id',
          'selected_options': [
            for (final k in selected) {'key': k, 'text': ''},
          ],
          'was_correct': wasCorrect,
        }
      : null,
  'rating_count': 2,
};

Map<String, Object?> practiceJson(
  int id,
  List<Map<String, Object?>> questions,
) => {
  'session_id': id,
  'session_code': 'S$id',
  'title': 'Ôn tập chương $id',
  'content': '',
  'subject_name': 'Hệ điều hành',
  'subject_code': 'IT3080',
  'total_questions': questions.length,
  'questions': questions,
};
