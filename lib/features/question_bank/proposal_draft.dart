import 'question_models.dart';

int _localIds = 0;
String _newLocalId() =>
    '${DateTime.now().microsecondsSinceEpoch}-${_localIds++}';

/// Ảnh của câu hỏi trong bản nháp: tệp đã sao chép vào thư mục của app
/// (chưa upload) hoặc URL server đã xác nhận.
class DraftImage {
  DraftImage({this.localPath, this.remoteUrl, String? id})
    : id = id ?? _newLocalId();
  final String id;
  final String? localPath;
  String? remoteUrl;
  bool get uploaded => remoteUrl != null;

  Map<String, dynamic> toJson() => {
    'id': id,
    'local_path': localPath,
    'remote_url': remoteUrl,
  };
  static DraftImage? fromJson(Object? value) {
    if (value is! Map) return null;
    final local = qbStringOrNull(value['local_path']);
    final remote = qbStringOrNull(value['remote_url']);
    if (local == null && remote == null) return null;
    return DraftImage(
      id: qbStringOrNull(value['id']),
      localPath: local,
      remoteUrl: remote,
    );
  }
}

class OptionDraft {
  OptionDraft({this.text = '', this.correct = false, this.mediaUrl, String? id})
    : id = id ?? _newLocalId();
  final String id;
  String text;
  bool correct;

  /// Giữ ảnh đáp án đã có trên server khi sửa; app chưa hỗ trợ thêm mới.
  final String? mediaUrl;

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'correct': correct,
    'media_url': mediaUrl,
  };
  factory OptionDraft.fromJson(Object? value) {
    final json = qbObject(value);
    return OptionDraft(
      id: qbStringOrNull(json['id']),
      text: qbStringOrNull(json['text']) ?? '',
      correct: qbBoolOrNull(json['correct']) ?? false,
      mediaUrl: qbStringOrNull(json['media_url']),
    );
  }
}

class QuestionDraft {
  QuestionDraft({
    this.questionId,
    this.content = '',
    this.explanation = '',
    this.source,
    this.confidence,
    List<OptionDraft>? options,
    List<DraftImage>? images,
    String? id,
  }) : id = id ?? _newLocalId(),
       options = options ?? [OptionDraft(), OptionDraft()],
       images = images ?? [];
  final String id;

  /// ID server khi sửa phiên; null là câu mới.
  int? questionId;
  String content;
  String explanation;

  /// Bắt buộc chọn; không mặc định để người dùng khai báo trung thực.
  QuestionSource? source;

  /// Thang 0–4, bắt buộc chọn. 0 là giá trị hợp lệ.
  int? confidence;
  final List<OptionDraft> options;
  final List<DraftImage> images;

  Map<String, dynamic> toJson() => {
    'id': id,
    'question_id': questionId,
    'content': content,
    'explanation': explanation,
    'source': source?.wire,
    'confidence': confidence,
    'options': [for (final o in options) o.toJson()],
    'images': [for (final i in images) i.toJson()],
  };

  factory QuestionDraft.fromJson(Object? value) {
    final json = qbObject(value);
    final confidence = qbIntOrNull(json['confidence']);
    return QuestionDraft(
      id: qbStringOrNull(json['id']),
      questionId: qbIntOrNull(json['question_id']),
      content: qbStringOrNull(json['content']) ?? '',
      explanation: qbStringOrNull(json['explanation']) ?? '',
      source: QuestionSource.parse(json['source']),
      confidence: confidence != null && confidence >= 0 && confidence <= 4
          ? confidence
          : null,
      options: [
        for (final o in qbList(json['options'])) OptionDraft.fromJson(o),
      ],
      images: [for (final i in qbList(json['images'])) ?DraftImage.fromJson(i)],
    );
  }

  factory QuestionDraft.fromSubmission(SubmissionQuestion question) =>
      QuestionDraft(
        questionId: question.questionId,
        content: question.content,
        explanation: question.explanation,
        source: question.source,
        confidence: question.confidence?.round().clamp(0, 4),
        options: [
          for (final o in question.options)
            OptionDraft(
              text: o.text,
              correct: o.isCorrect ?? false,
              mediaUrl: o.mediaUrl,
            ),
        ],
        images: [
          for (final url in question.imageUrls) DraftImage(remoteUrl: url),
        ],
      );

  List<Map<String, dynamic>> _optionsJson() => [
    for (var i = 0; i < options.length; i++)
      {
        'key': optionKey(i),
        'text': options[i].text.trim(),
        'is_correct': options[i].correct,
        'media_url': ?options[i].mediaUrl,
      },
  ];

  List<String> get _mediaUrls => [for (final image in images) ?image.remoteUrl];

  Map<String, dynamic> toProposeJson() => {
    'content': content.trim(),
    'media_urls': _mediaUrls,
    'options': _optionsJson(),
    if (explanation.trim().isNotEmpty) 'explanation': explanation.trim(),
    'llm_generated': source == QuestionSource.llm,
    'confidence': confidence,
  };

  Map<String, dynamic> toUpdateJson() => {
    'question_id': questionId,
    'content': content.trim(),
    'media_urls': _mediaUrls,
    'options': _optionsJson(),
    'explanation': explanation.trim(),
    'source': source?.wire,
    'confidence': confidence,
  };
}

/// Trạng thái gửi chưa xác nhận: request có thể đã được server xử lý.
class PendingVerification {
  const PendingVerification({required this.attemptedAt, required this.kind});
  final DateTime attemptedAt;

  /// 'propose' hoặc 'update'.
  final String kind;
  Map<String, dynamic> toJson() => {
    'attempted_at': attemptedAt.toUtc().toIso8601String(),
    'kind': kind,
  };
  static PendingVerification? fromJson(Object? value) {
    if (value is! Map) return null;
    final at = qbDateOrNull(value['attempted_at']);
    final kind = qbStringOrNull(value['kind']);
    if (at == null || kind == null) return null;
    return PendingVerification(attemptedAt: at, kind: kind);
  }
}

class ProposalDraft {
  ProposalDraft({
    this.sessionId,
    this.courseClass,
    this.title = '',
    this.content = '',
    this.sourceUrl = '',
    List<QuestionDraft>? questions,
    this.pending,
  }) : questions =
           questions ?? [QuestionDraft(), QuestionDraft(), QuestionDraft()];

  /// null: đề xuất mới; có giá trị: đang sửa phiên này.
  final int? sessionId;
  CourseClassOption? courseClass;
  String title;
  String content;
  String sourceUrl;
  final List<QuestionDraft> questions;
  PendingVerification? pending;

  bool get isEdit => sessionId != null;
  String get draftName =>
      sessionId == null ? 'qb-proposal-new' : 'qb-proposal-edit-$sessionId';

  static String draftNameFor(int? sessionId) =>
      sessionId == null ? 'qb-proposal-new' : 'qb-proposal-edit-$sessionId';

  Iterable<DraftImage> get allImages => questions.expand((q) => q.images);

  Map<String, dynamic> toJson() => {
    'version': 1,
    'session_id': sessionId,
    'course_class': courseClass?.toJson(),
    'title': title,
    'content': content,
    'source_url': sourceUrl,
    'questions': [for (final q in questions) q.toJson()],
    'pending': pending?.toJson(),
  };

  factory ProposalDraft.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) throw const FormatException('Draft version');
    final klass = json['course_class'];
    return ProposalDraft(
      sessionId: qbIntOrNull(json['session_id']),
      courseClass: klass == null ? null : CourseClassOption.fromJson(klass),
      title: qbStringOrNull(json['title']) ?? '',
      content: qbStringOrNull(json['content']) ?? '',
      sourceUrl: qbStringOrNull(json['source_url']) ?? '',
      questions: [
        for (final q in qbList(json['questions'])) QuestionDraft.fromJson(q),
      ],
      pending: PendingVerification.fromJson(json['pending']),
    );
  }

  factory ProposalDraft.fromSubmission(SubmissionDetail detail) =>
      ProposalDraft(
        sessionId: detail.sessionId,
        courseClass: detail.courseClassId == null
            ? null
            : CourseClassOption(
                courseClassId: detail.courseClassId!,
                classCode: detail.classCode,
                subjectId: null,
                subjectCode: detail.subjectCode,
                subjectName: detail.subjectName,
                semesterName: detail.semesterName,
                canPropose: true,
              ),
        title: detail.title,
        content: detail.content,
        sourceUrl: detail.sourceUrl ?? '',
        questions: [
          for (final q in detail.questions) QuestionDraft.fromSubmission(q),
        ],
      );

  Map<String, dynamic> toProposeJson() => {
    'title': title.trim(),
    if (content.trim().isNotEmpty) 'content': content.trim(),
    if (sourceUrl.trim().isNotEmpty) 'source_url': sourceUrl.trim(),
    'course_class_id': courseClass?.courseClassId,
    'questions': [for (final q in questions) q.toProposeJson()],
  };

  Map<String, dynamic> toUpdateJson() => {
    'title': title.trim(),
    'content': content.trim(),
    'source_url': sourceUrl.trim(),
    'course_class_id': ?courseClass?.courseClassId,
    'questions': [for (final q in questions) q.toUpdateJson()],
  };
}
