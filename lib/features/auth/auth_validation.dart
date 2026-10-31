abstract final class AuthValidation {
  static String? email(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Vui lòng nhập email được cấp.';
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(text)) {
      return 'Email không đúng định dạng.';
    }
    return null;
  }

  // Không trim hoặc chặn ký tự đặc biệt: tài khoản do giảng viên cấp,
  // và Swagger hiện có ví dụ mật khẩu chứa ký tự đặc biệt.
  static String? password(String? value) =>
      value == null || value.isEmpty ? 'Vui lòng nhập mật khẩu.' : null;

  static String? newPassword(String? value, String old) {
    final missing = password(value);
    if (missing != null) return missing;
    return value == old ? 'Mật khẩu mới phải khác mật khẩu hiện tại.' : null;
  }
}
