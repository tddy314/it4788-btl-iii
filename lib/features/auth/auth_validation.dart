abstract final class AuthValidation {
  static String? email(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Vui lòng nhập email được cấp.';
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(text)) {
      return 'Email không đúng định dạng.';
    }
    return null;
  }

  // Đăng nhập/mật khẩu hiện tại: giữ nguyên mật khẩu tài khoản được cấp,
  // không tự trim hay đổi định dạng. Đặt mật khẩu mới dùng quy tắc PDF bên dưới.
  static String? password(String? value) =>
      value == null || value.isEmpty ? 'Vui lòng nhập mật khẩu.' : null;

  static String? newPassword(String? value, String old) {
    final missing = password(value);
    if (missing != null) return missing;
    // PDF p.23 excludes special characters. Swagger gives examples with them
    // but declares no pattern; an example does not override the business rule.
    if (!RegExp(r'^[A-Za-z0-9]+$').hasMatch(value!)) {
      return 'Mật khẩu mới chỉ gồm chữ cái A–Z, a–z và chữ số, không chứa khoảng trắng hoặc ký tự đặc biệt.';
    }
    return value == old ? 'Mật khẩu mới phải khác mật khẩu hiện tại.' : null;
  }
}
