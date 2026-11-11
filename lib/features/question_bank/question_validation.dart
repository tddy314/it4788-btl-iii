import 'proposal_draft.dart';

/// Validate bản nháp trước khi kiểm tra mạng hoặc upload.
///
/// Theo Swagger: tối thiểu 3 câu, mỗi câu có nội dung, đáp án, nguồn
/// (`llm_generated`/`source`) và mức tự tin 0–4. Ứng dụng yêu cầu thêm tối thiểu
/// 2 đáp án và ít nhất 1 đáp án đúng cho câu trắc nghiệm.
abstract final class QuestionValidation {
  static const minQuestions = 3;
  static const minOptions = 2;
  static const maxOptions = 8;
  static const maxImagesPerQuestion = 4;
  static const maxImageBytes = 4 * 1024 * 1024;
  static const maxCommentLength = 500;

  static String? title(String value) =>
      value.trim().isEmpty ? 'Vui lòng nhập tiêu đề bộ câu hỏi.' : null;

  static String? sourceUrl(String value) {
    final text = value.trim();
    if (text.isEmpty) return null;
    final uri = Uri.tryParse(text);
    if (uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.host.isEmpty) {
      return 'Đường dẫn tham khảo phải bắt đầu bằng http:// hoặc https://.';
    }
    return null;
  }

  /// Khóa lỗi: `class`, `title`, `source_url`, `questions`, `q{i}.content`,
  /// `q{i}.options`, `q{i}.o{j}`, `q{i}.correct`, `q{i}.source`,
  /// `q{i}.confidence`, `q{i}.images`.
  static Map<String, String> validate(ProposalDraft draft) {
    final errors = <String, String>{};
    final klass = draft.courseClass;
    if (klass == null) {
      errors['class'] = 'Vui lòng chọn lớp học phần.';
    } else if (!draft.isEdit && !klass.canPropose) {
      errors['class'] = 'Lớp học phần này không còn nhận đề xuất.';
    }
    if (title(draft.title) case final message?) errors['title'] = message;
    if (sourceUrl(draft.sourceUrl) case final message?) {
      errors['source_url'] = message;
    }
    if (draft.questions.length < minQuestions) {
      errors['questions'] =
          'Mỗi lần đề xuất cần tối thiểu $minQuestions câu hỏi.';
    }
    for (var i = 0; i < draft.questions.length; i++) {
      final q = draft.questions[i];
      final key = 'q$i';
      if (q.content.trim().isEmpty) {
        errors['$key.content'] = 'Vui lòng nhập nội dung câu hỏi.';
      }
      if (q.options.length < minOptions) {
        errors['$key.options'] = 'Cần ít nhất $minOptions đáp án.';
      } else if (q.options.length > maxOptions) {
        errors['$key.options'] = 'Tối đa $maxOptions đáp án cho một câu.';
      }
      final texts = <String>{};
      for (var j = 0; j < q.options.length; j++) {
        final text = q.options[j].text.trim();
        if (text.isEmpty) {
          errors['$key.o$j'] = 'Vui lòng nhập nội dung đáp án.';
        } else if (!texts.add(text.toLowerCase())) {
          errors['$key.o$j'] = 'Đáp án bị trùng với đáp án khác.';
        }
      }
      if (!q.options.any((o) => o.correct)) {
        errors['$key.correct'] = 'Hãy đánh dấu ít nhất một đáp án đúng.';
      }
      if (q.source == null) {
        errors['$key.source'] =
            'Hãy khai báo câu hỏi tự biên soạn hay do AI tạo.';
      }
      final confidence = q.confidence;
      if (confidence == null || confidence < 0 || confidence > 4) {
        errors['$key.confidence'] = 'Hãy chọn mức tự tin từ 0 đến 4.';
      }
      if (q.images.length > maxImagesPerQuestion) {
        errors['$key.images'] =
            'Mỗi câu hỏi đính kèm tối đa $maxImagesPerQuestion ảnh.';
      }
    }
    return errors;
  }

  /// Số ký tự theo UTF-16 như Java String.length phía server.
  static String? comment(String value, {bool required = false}) {
    final text = value.trim();
    if (required && text.isEmpty) return 'Vui lòng nhập mô tả.';
    if (text.length > maxCommentLength) {
      return 'Nội dung tối đa $maxCommentLength ký tự '
          '(hiện có ${text.length}).';
    }
    return null;
  }

  static String? rating(int? value) => value == null || value < 0 || value > 4
      ? 'Hãy chọn mức đánh giá từ 0 đến 4.'
      : null;
}
