class AppConfig {
  AppConfig({
    this.apiBaseUrl = const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'https://snsqb.duckdns.org/api/v1/',
    ),
    this.successCode = const String.fromEnvironment(
      'API_SUCCESS_CODE',
      defaultValue: '1000',
    ),
    this.connectTimeout = const Duration(seconds: 10),
    this.receiveTimeout = const Duration(seconds: 20),
  }) {
    final uri = Uri.parse(apiBaseUrl);
    if (uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty) {
      throw ArgumentError('API_BASE_URL phải là URL HTTPS hợp lệ.');
    }
  }
  final String apiBaseUrl;
  final String successCode;
  final Duration connectTimeout;
  final Duration receiveTimeout;
  String get normalizedBaseUrl =>
      apiBaseUrl.endsWith('/') ? apiBaseUrl : '$apiBaseUrl/';
}
