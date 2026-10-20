abstract final class Validators {
  static String? requiredText(String? value) =>
      value == null || value.trim().isEmpty
      ? 'Vui lòng nhập đầy đủ thông tin.'
      : null;

  static int wordCount(String value) =>
      value.trim().isEmpty ? 0 : value.trim().split(RegExp(r'\s+')).length;

  static String? maxWords(String? value, int limit) =>
      wordCount(value ?? '') > limit
      ? 'Nội dung không được vượt quá $limit từ.'
      : null;
}
