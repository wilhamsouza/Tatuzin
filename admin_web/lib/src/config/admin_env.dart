abstract final class AdminEnv {
  static final String apiBaseUrl = _normalizeBaseUrl(
    const String.fromEnvironment(
      'TATUZIN_ADMIN_API_URL',
      defaultValue: 'http://localhost:4000/api',
    ),
  );

  static String _normalizeBaseUrl(String rawValue) {
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) {
      return 'http://localhost:4000/api';
    }
    return trimmed.endsWith('/') ? trimmed.substring(0, trimmed.length - 1) : trimmed;
  }
}
