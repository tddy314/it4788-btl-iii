// DTO của ngân hàng câu hỏi theo Swagger ngày 10/11/2026.
//
// Đọc dữ liệu một cách phòng thủ: số có thể là chuỗi, trường không bắt buộc có
// thể null, enum lạ không làm crash. Trường bắt buộc thiếu thì ném
// FormatException để ApiClient chuyển thành lỗi "dữ liệu không hợp lệ".

Map<String, dynamic> qbObject(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.map((k, v) => MapEntry(k.toString(), v));
  throw const FormatException('Expected object');
}

List<Object?> qbList(Object? value) {
  if (value == null) return const [];
  if (value is List) return value;
  throw const FormatException('Expected list');
}

int? qbIntOrNull(Object? value) => switch (value) {
  final int v => v,
  final double v when v == v.roundToDouble() => v.toInt(),
  final String v => int.tryParse(v.trim()),
  _ => null,
};

int qbRequiredInt(Object? value) {
  final result = qbIntOrNull(value);
  if (result == null) throw const FormatException('Missing integer');
  return result;
}

double? qbDoubleOrNull(Object? value) => switch (value) {
  final num v => v.toDouble(),
  final String v => double.tryParse(v.trim()),
  _ => null,
};

String? qbStringOrNull(Object? value) => switch (value) {
  null => null,
  final String v => v,
  final num v => v.toString(),
  final bool v => v.toString(),
  _ => null,
};

/// Chỉ nhận true/"true"/1 là true; mọi giá trị khác là false. Dùng [qbBoolOrNull]
/// khi cần phân biệt "không có dữ liệu" với false.
bool? qbBoolOrNull(Object? value) => switch (value) {
  final bool v => v,
  final num v => v != 0,
  final String v when v.toLowerCase() == 'true' || v == '1' => true,
  final String v when v.toLowerCase() == 'false' || v == '0' => false,
  _ => null,
};

DateTime? qbDateOrNull(Object? value) {
  if (value is String) return DateTime.tryParse(value);
  final seconds = qbIntOrNull(value);
  if (seconds == null) return null;
  // Unix giây (PDF cũ) hoặc mili giây.
  return DateTime.fromMillisecondsSinceEpoch(
    seconds > 100000000000 ? seconds : seconds * 1000,
    isUtc: true,
  );
}

List<String> qbStringList(Object? value) => [
  for (final item in qbList(value))
    if (qbStringOrNull(item) case final String s when s.trim().isNotEmpty) s,
];

String qbFormatDate(DateTime? value) {
  if (value == null) return '';
  final local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} '
      '${two(local.hour)}:${two(local.minute)}';
}

/// Trạng thái của phiên đề xuất (không phải phiên đăng nhập).
enum SessionStatus {
  pending('PENDING', 'Chờ duyệt'),
  reviewing('REVIEWING', 'Đang duyệt'),
  resolved('RESOLVED', 'Đã xử lý'),
  unknown('', 'Không xác định');

  const SessionStatus(this.wire, this.label);
  final String wire;
  final String label;
  static const filters = [pending, reviewing, resolved];
  static SessionStatus parse(Object? value) {
    final text = qbStringOrNull(value)?.toUpperCase();
    return values.firstWhere(
      (s) => s != unknown && s.wire == text,
      orElse: () => unknown,
    );
  }
}

/// Kết quả duyệt từng câu. RESOLVED của phiên không có nghĩa mọi câu APPROVED.
enum QuestionReviewStatus {
  pending('PENDING', 'Chưa có kết quả'),
  approved('APPROVED', 'Được chọn'),
  rejected('REJECTED', 'Không được chọn'),
  unknown('', 'Không xác định');

  const QuestionReviewStatus(this.wire, this.label);
  final String wire;
  final String label;
  static QuestionReviewStatus? parse(Object? value) {
    final text = qbStringOrNull(value)?.toUpperCase();
    if (text == null || text.isEmpty) return null;
    return values.firstWhere(
      (s) => s != unknown && s.wire == text,
      orElse: () => unknown,
    );
  }
}

enum QuestionSource {
  human('HOMO_SAPIENS', 'Tự biên soạn'),
  llm('LLM', 'Do AI tạo');

  const QuestionSource(this.wire, this.label);
  final String wire;
  final String label;
  static QuestionSource? parse(Object? value) {
    final text = qbStringOrNull(value)?.toUpperCase();
    for (final source in values) {
      if (source.wire == text) return source;
    }
    return null;
  }
}

String rejectionLabel(String? code) => switch (code?.toUpperCase()) {
  null || '' => '',
  'DUPLICATE' => 'Trùng với câu hỏi đã có',
  'INCORRECT_ANSWER' => 'Đáp án chưa đúng',
  'AMBIGUOUS_OR_INCOMPLETE' => 'Câu hỏi mơ hồ hoặc thiếu thông tin',
  'OUT_OF_SCOPE' => 'Ngoài phạm vi môn học',
  'LOW_QUALITY' => 'Chất lượng chưa đạt',
  'OTHER' => 'Lý do khác',
  'UNSPECIFIED' => 'Không nêu lý do',
  'AUTO_REJECTED_ON_COMPLETION' => 'Không được chọn khi kết thúc đợt duyệt',
  _ => 'Lý do khác',
};

/// Mức tự tin của tác giả theo mô tả Swagger, thang 0–4.
const confidenceLabels = [
  'Sai hoàn toàn',
  'Có thể do AI bịa',
  'Chưa nắm vững',
  'Cơ bản',
  'Câu hỏi hay',
];

class CursorPage<T> {
  const CursorPage({required this.items, this.after, this.hasNext = false});
  final List<T> items;
  final int? after;
  final bool hasNext;

  static CursorPage<T> parse<T>(
    Object? value,
    String listKey,
    T Function(Object?) item,
  ) {
    final json = qbObject(value);
    final items = [for (final raw in qbList(json[listKey])) item(raw)];
    final pagination = json['pagination'] == null
        ? const <String, dynamic>{}
        : qbObject(json['pagination']);
    final after = qbIntOrNull(pagination['after']);
    // Không có cursor thì không thể tải tiếp dù server báo has_next.
    final hasNext =
        (qbBoolOrNull(pagination['has_next']) ?? false) &&
        after != null &&
        items.isNotEmpty;
    return CursorPage(items: items, after: after, hasNext: hasNext);
  }
}

class CourseClassOption {
  const CourseClassOption({
    required this.courseClassId,
    required this.classCode,
    required this.subjectId,
    required this.subjectCode,
    required this.subjectName,
    required this.semesterName,
    required this.canPropose,
  });
  final int courseClassId;
  final String classCode;
  final int? subjectId;
  final String subjectCode;
  final String subjectName;
  final String semesterName;
  final bool canPropose;

  String get label {
    final subject = [
      subjectCode,
      subjectName,
    ].where((s) => s.isNotEmpty).join(' - ');
    final klass = classCode.isEmpty ? '' : 'Lớp $classCode';
    return [subject, klass].where((s) => s.isNotEmpty).join(' · ');
  }

  factory CourseClassOption.fromJson(Object? value) {
    final json = qbObject(value);
    return CourseClassOption(
      courseClassId: qbRequiredInt(json['course_class_id']),
      classCode: qbStringOrNull(json['class_code']) ?? '',
      subjectId: qbIntOrNull(json['subject_id']),
      subjectCode: qbStringOrNull(json['subject_code']) ?? '',
      subjectName: qbStringOrNull(json['subject_name']) ?? '',
      semesterName: qbStringOrNull(json['semester_name']) ?? '',
      // Thiếu cờ thì không cho đề xuất; server mới là nơi quyết định quyền.
      canPropose: qbBoolOrNull(json['can_propose']) ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'course_class_id': courseClassId,
    'class_code': classCode,
    'subject_id': subjectId,
    'subject_code': subjectCode,
    'subject_name': subjectName,
    'semester_name': semesterName,
    'can_propose': canPropose,
  };
}

class SubjectItem {
  const SubjectItem({required this.id, required this.code, required this.name});
  final int id;
  final String code;
  final String name;
  String get label =>
      [code, name].where((s) => s.isNotEmpty).join(' - ').ifEmpty('Môn $id');
  factory SubjectItem.fromJson(Object? value) {
    final json = qbObject(value);
    return SubjectItem(
      id: qbRequiredInt(json['subject_id']),
      code: qbStringOrNull(json['code']) ?? '',
      name: qbStringOrNull(json['name']) ?? '',
    );
  }
  Map<String, dynamic> toJson() => {
    'subject_id': id,
    'code': code,
    'name': name,
  };
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

class SubmissionSummary {
  const SubmissionSummary({
    required this.sessionId,
    required this.sessionCode,
    required this.title,
    required this.content,
    required this.subjectCode,
    required this.subjectName,
    required this.classCode,
    required this.status,
    required this.questionCount,
    required this.approvedCount,
    required this.createdAt,
    required this.reactCount,
    required this.commentCount,
  });
  final int sessionId;
  final String sessionCode;
  final String title;
  final String content;
  final String subjectCode;
  final String subjectName;
  final String classCode;
  final SessionStatus status;
  final int? questionCount;
  final int? approvedCount;
  final DateTime? createdAt;
  final int reactCount;
  final int commentCount;

  String get subjectLabel =>
      [subjectCode, subjectName].where((s) => s.isNotEmpty).join(' - ');

  factory SubmissionSummary.fromJson(Object? value) {
    final json = qbObject(value);
    return SubmissionSummary(
      sessionId: qbRequiredInt(json['session_id']),
      sessionCode: qbStringOrNull(json['session_code']) ?? '',
      title: qbStringOrNull(json['title']) ?? '',
      content: qbStringOrNull(json['content']) ?? '',
      subjectCode: qbStringOrNull(json['subject_code']) ?? '',
      subjectName: qbStringOrNull(json['subject_name']) ?? '',
      classCode: qbStringOrNull(json['class_code']) ?? '',
      status: SessionStatus.parse(json['status']),
      questionCount:
          qbIntOrNull(json['question_counts']) ??
          qbIntOrNull(json['question_count']),
      approvedCount: qbIntOrNull(json['approved_question_count']),
      createdAt: qbDateOrNull(json['created_at']),
      reactCount: qbIntOrNull(json['react_count']) ?? 0,
      commentCount: qbIntOrNull(json['comment_count']) ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'session_id': sessionId,
    'session_code': sessionCode,
    'title': title,
    'content': content,
    'subject_code': subjectCode,
    'subject_name': subjectName,
    'class_code': classCode,
    'status': status.wire,
    'question_counts': questionCount,
    'approved_question_count': approvedCount,
    'created_at': createdAt?.toUtc().toIso8601String(),
    'react_count': reactCount,
    'comment_count': commentCount,
  };
}

class QuestionOptionData {
  const QuestionOptionData({
    required this.key,
    required this.text,
    this.isCorrect,
    this.mediaUrl,
    this.mediaId,
  });
  final String key;
  final String text;

  /// null nghĩa là server ẩn đáp án; không được hiểu là "sai".
  final bool? isCorrect;
  final String? mediaUrl;
  final int? mediaId;

  factory QuestionOptionData.fromJson(Object? value, int index) {
    final json = qbObject(value);
    final key = qbStringOrNull(json['key'])?.trim();
    return QuestionOptionData(
      key: key == null || key.isEmpty ? optionKey(index) : key,
      text: qbStringOrNull(json['text']) ?? '',
      isCorrect: qbBoolOrNull(json['is_correct']),
      mediaUrl: qbStringOrNull(json['media_url']),
      mediaId: qbIntOrNull(json['media_id']),
    );
  }

  Map<String, dynamic> toJson() => {
    'key': key,
    'text': text,
    if (isCorrect != null) 'is_correct': isCorrect,
    if (mediaUrl != null) 'media_url': mediaUrl,
    if (mediaId != null) 'media_id': mediaId,
  };
}

String optionKey(int index) {
  // A..Z, sau đó A1, B1... để không trùng khóa khi có rất nhiều đáp án.
  final letter = String.fromCharCode(65 + index % 26);
  return index < 26 ? letter : '$letter${index ~/ 26}';
}

List<QuestionOptionData> _options(Object? value) {
  final raw = qbList(value);
  return [
    for (var i = 0; i < raw.length; i++) QuestionOptionData.fromJson(raw[i], i),
  ];
}

class SubmissionQuestion {
  const SubmissionQuestion({
    required this.questionId,
    required this.content,
    required this.imageUrls,
    required this.options,
    required this.explanation,
    required this.source,
    required this.confidence,
    required this.status,
    required this.rejectionCode,
    required this.rejectionReason,
  });
  final int questionId;
  final String content;
  final List<String> imageUrls;
  final List<QuestionOptionData> options;
  final String explanation;
  final QuestionSource? source;
  final double? confidence;
  final QuestionReviewStatus? status;
  final String? rejectionCode;
  final String? rejectionReason;

  factory SubmissionQuestion.fromJson(Object? value) {
    final json = qbObject(value);
    return SubmissionQuestion(
      questionId: qbRequiredInt(json['question_id']),
      content: qbStringOrNull(json['content']) ?? '',
      imageUrls: qbStringList(json['image_urls'] ?? json['media_urls']),
      options: _options(json['options']),
      explanation: qbStringOrNull(json['explanation']) ?? '',
      source: QuestionSource.parse(json['source']),
      confidence:
          qbDoubleOrNull(json['confidence_score']) ??
          qbDoubleOrNull(json['confidence']),
      status: QuestionReviewStatus.parse(json['status']),
      rejectionCode: qbStringOrNull(json['rejection_code']),
      rejectionReason: qbStringOrNull(json['rejection_reason']),
    );
  }

  Map<String, dynamic> toJson() => {
    'question_id': questionId,
    'content': content,
    'image_urls': imageUrls,
    'options': [for (final o in options) o.toJson()],
    'explanation': explanation,
    'source': source?.wire,
    'confidence_score': confidence,
    'status': status?.wire,
    'rejection_code': rejectionCode,
    'rejection_reason': rejectionReason,
  };
}

class SubmissionDetail {
  const SubmissionDetail({
    required this.sessionId,
    required this.sessionCode,
    required this.title,
    required this.content,
    required this.sourceUrl,
    required this.subjectCode,
    required this.subjectName,
    required this.courseClassId,
    required this.classCode,
    required this.semesterName,
    required this.status,
    required this.reviewedBy,
    required this.reviewedAt,
    required this.createdAt,
    required this.questions,
  });
  final int sessionId;
  final String sessionCode;
  final String title;
  final String content;
  final String? sourceUrl;
  final String subjectCode;
  final String subjectName;
  final int? courseClassId;
  final String classCode;
  final String semesterName;
  final SessionStatus status;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final DateTime? createdAt;
  final List<SubmissionQuestion> questions;

  /// Mô tả server: chỉ sửa/xóa khi PENDING. Server vẫn là nơi quyết định.
  bool get editable => status == SessionStatus.pending;

  String get subjectLabel =>
      [subjectCode, subjectName].where((s) => s.isNotEmpty).join(' - ');

  int countWith(QuestionReviewStatus status) =>
      questions.where((q) => q.status == status).length;

  factory SubmissionDetail.fromJson(Object? value) {
    final json = qbObject(value);
    return SubmissionDetail(
      sessionId: qbRequiredInt(json['session_id']),
      sessionCode: qbStringOrNull(json['session_code']) ?? '',
      title: qbStringOrNull(json['title']) ?? '',
      content: qbStringOrNull(json['content']) ?? '',
      sourceUrl: qbStringOrNull(json['source_url']),
      subjectCode: qbStringOrNull(json['subject_code']) ?? '',
      subjectName: qbStringOrNull(json['subject_name']) ?? '',
      courseClassId: qbIntOrNull(json['course_class_id']),
      classCode: qbStringOrNull(json['class_code']) ?? '',
      semesterName: qbStringOrNull(json['semester_name']) ?? '',
      status: SessionStatus.parse(json['status']),
      reviewedBy: qbStringOrNull(json['reviewed_by_lecturer']),
      reviewedAt: qbDateOrNull(json['reviewed_at']),
      createdAt: qbDateOrNull(json['created_at']),
      questions: [
        for (final q in qbList(json['questions']))
          SubmissionQuestion.fromJson(q),
      ],
    );
  }

  Map<String, dynamic> toJson() => {
    'session_id': sessionId,
    'session_code': sessionCode,
    'title': title,
    'content': content,
    'source_url': sourceUrl,
    'subject_code': subjectCode,
    'subject_name': subjectName,
    'course_class_id': courseClassId,
    'class_code': classCode,
    'semester_name': semesterName,
    'status': status.wire,
    'reviewed_by_lecturer': reviewedBy,
    'reviewed_at': reviewedAt?.toUtc().toIso8601String(),
    'created_at': createdAt?.toUtc().toIso8601String(),
    'questions': [for (final q in questions) q.toJson()],
  };
}

class ProposeResult {
  const ProposeResult({required this.sessionId, required this.status});
  final int sessionId;
  final SessionStatus status;
  factory ProposeResult.fromJson(Object? value) {
    final json = qbObject(value);
    return ProposeResult(
      sessionId: qbRequiredInt(json['session_id']),
      status: SessionStatus.parse(json['status']),
    );
  }
}

class PracticeSetSummary {
  const PracticeSetSummary({
    required this.sessionId,
    required this.sessionCode,
    required this.title,
    required this.content,
    required this.subjectCode,
    required this.subjectName,
    required this.questionCount,
    required this.createdAt,
  });
  final int sessionId;
  final String sessionCode;
  final String title;
  final String content;
  final String subjectCode;
  final String subjectName;
  final int? questionCount;
  final DateTime? createdAt;

  String get subjectLabel =>
      [subjectCode, subjectName].where((s) => s.isNotEmpty).join(' - ');

  factory PracticeSetSummary.fromJson(Object? value) {
    final json = qbObject(value);
    return PracticeSetSummary(
      sessionId: qbRequiredInt(json['session_id']),
      sessionCode: qbStringOrNull(json['session_code']) ?? '',
      title: qbStringOrNull(json['title']) ?? '',
      content: qbStringOrNull(json['content']) ?? '',
      subjectCode: qbStringOrNull(json['subject_code']) ?? '',
      subjectName: qbStringOrNull(json['subject_name']) ?? '',
      questionCount:
          qbIntOrNull(json['question_counts']) ??
          qbIntOrNull(json['total_questions']),
      createdAt: qbDateOrNull(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() => {
    'session_id': sessionId,
    'session_code': sessionCode,
    'title': title,
    'content': content,
    'subject_code': subjectCode,
    'subject_name': subjectName,
    'question_counts': questionCount,
    'created_at': createdAt?.toUtc().toIso8601String(),
  };
}

class PracticeQuestion {
  const PracticeQuestion({
    required this.questionId,
    required this.questionCode,
    required this.content,
    required this.imageUrls,
    required this.options,
    required this.updatedAt,
    required this.rawUpdatedAt,
    required this.answered,
    required this.rated,
    required this.myRating,
    required this.ratingComment,
    required this.reported,
    required this.correctAnswer,
    required this.explanation,
    required this.selectedKeys,
    required this.wasCorrect,
    required this.updatedSinceAnswer,
    required this.ratingCount,
  });
  final int questionId;
  final String questionCode;
  final String content;
  final List<String> imageUrls;
  final List<QuestionOptionData> options;
  final DateTime? updatedAt;

  /// Gửi lại đúng chuỗi server trả để kiểm tra dữ liệu cũ (HTTP 412).
  final String? rawUpdatedAt;
  final bool answered;
  final bool rated;
  final double? myRating;
  final String? ratingComment;
  final bool reported;
  final String? correctAnswer;
  final String? explanation;
  final List<String> selectedKeys;
  final bool? wasCorrect;
  final bool updatedSinceAnswer;
  final int ratingCount;

  factory PracticeQuestion.fromJson(Object? value) {
    final json = qbObject(value);
    final mine = json['my_interaction'] == null
        ? const <String, dynamic>{}
        : qbObject(json['my_interaction']);
    final hidden = json['hidden_fields'] == null
        ? const <String, dynamic>{}
        : qbObject(json['hidden_fields']);
    return PracticeQuestion(
      questionId: qbRequiredInt(json['question_id']),
      questionCode: qbStringOrNull(json['question_code']) ?? '',
      content: qbStringOrNull(json['content']) ?? '',
      imageUrls: qbStringList(json['image_urls']),
      options: _options(json['options']),
      updatedAt: qbDateOrNull(json['updated_at']),
      rawUpdatedAt: qbStringOrNull(json['updated_at']),
      answered: qbBoolOrNull(mine['answered']) ?? false,
      rated: qbBoolOrNull(mine['rated']) ?? false,
      myRating: qbDoubleOrNull(mine['my_rating']),
      ratingComment: qbStringOrNull(mine['rating_comment']),
      reported: qbBoolOrNull(mine['reported']) ?? false,
      correctAnswer: qbStringOrNull(hidden['correct_answer']),
      explanation: qbStringOrNull(hidden['explanation']),
      selectedKeys: [
        for (final item in qbList(hidden['selected_options']))
          if (item is Map)
            ?qbStringOrNull(item['key'])
          else
            ?qbStringOrNull(item),
      ],
      wasCorrect: qbBoolOrNull(hidden['was_correct']),
      updatedSinceAnswer:
          qbBoolOrNull(hidden['question_updated_since_answer']) ?? false,
      ratingCount: qbIntOrNull(json['rating_count']) ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'question_id': questionId,
    'question_code': questionCode,
    'content': content,
    'image_urls': imageUrls,
    'options': [for (final o in options) o.toJson()],
    'updated_at': rawUpdatedAt,
    'my_interaction': {
      'answered': answered,
      'rated': rated,
      'my_rating': myRating,
      'rating_comment': ratingComment,
      'reported': reported,
    },
    'hidden_fields': {
      'correct_answer': correctAnswer,
      'explanation': explanation,
      'selected_options': [
        for (final k in selectedKeys) {'key': k},
      ],
      'was_correct': wasCorrect,
      'question_updated_since_answer': updatedSinceAnswer,
    },
    'rating_count': ratingCount,
  };
}

class PracticeSession {
  const PracticeSession({
    required this.sessionId,
    required this.sessionCode,
    required this.title,
    required this.content,
    required this.subjectCode,
    required this.subjectName,
    required this.questions,
  });
  final int sessionId;
  final String sessionCode;
  final String title;
  final String content;
  final String subjectCode;
  final String subjectName;
  final List<PracticeQuestion> questions;

  String get subjectLabel =>
      [subjectCode, subjectName].where((s) => s.isNotEmpty).join(' - ');

  factory PracticeSession.fromJson(Object? value) {
    final json = qbObject(value);
    return PracticeSession(
      sessionId: qbRequiredInt(json['session_id']),
      sessionCode: qbStringOrNull(json['session_code']) ?? '',
      title: qbStringOrNull(json['title']) ?? '',
      content: qbStringOrNull(json['content']) ?? '',
      subjectCode: qbStringOrNull(json['subject_code']) ?? '',
      subjectName: qbStringOrNull(json['subject_name']) ?? '',
      questions: [
        for (final q in qbList(json['questions'])) PracticeQuestion.fromJson(q),
      ],
    );
  }

  Map<String, dynamic> toJson() => {
    'session_id': sessionId,
    'session_code': sessionCode,
    'title': title,
    'content': content,
    'subject_code': subjectCode,
    'subject_name': subjectName,
    'questions': [for (final q in questions) q.toJson()],
  };
}

class AnswerResult {
  const AnswerResult({
    required this.isCorrect,
    required this.correctAnswer,
    required this.explanation,
  });

  /// null khi server không trả cờ; không tự kết luận đúng/sai.
  final bool? isCorrect;
  final String? correctAnswer;
  final String? explanation;
  factory AnswerResult.fromJson(Object? value) {
    final json = qbObject(value);
    return AnswerResult(
      isCorrect: qbBoolOrNull(json['is_correct']),
      correctAnswer: qbStringOrNull(json['correct_answer']),
      explanation: qbStringOrNull(json['explanation']),
    );
  }
}

/// Đáp án đúng có thể là "A" hoặc "A,C"; tách để tô màu phương án.
Set<String> parseAnswerKeys(String? value) => {
  for (final part in (value ?? '').split(RegExp(r'[\s,;|]+')))
    if (part.trim().isNotEmpty) part.trim().toUpperCase(),
};

class RateResult {
  const RateResult({required this.average, required this.count});
  final double? average;
  final int? count;
  factory RateResult.fromJson(Object? value) {
    if (value == null) return const RateResult(average: null, count: null);
    final json = qbObject(value);
    return RateResult(
      average: qbDoubleOrNull(json['new_avg_rating']),
      count: qbIntOrNull(json['new_rating_count']),
    );
  }
}

class RatingItem {
  const RatingItem({
    required this.userId,
    required this.reviewerName,
    required this.rating,
    required this.comment,
    required this.createdAt,
  });
  final int? userId;
  final String reviewerName;
  final double? rating;
  final String comment;
  final DateTime? createdAt;
  factory RatingItem.fromJson(Object? value) {
    final json = qbObject(value);
    return RatingItem(
      userId: qbIntOrNull(json['user_id']),
      reviewerName: qbStringOrNull(json['reviewer_name']) ?? '',
      rating: qbDoubleOrNull(json['rating']),
      comment: qbStringOrNull(json['comment']) ?? '',
      createdAt: qbDateOrNull(json['created_at']),
    );
  }
}
