import 'package:flutter/foundation.dart';

abstract final class AdminEnv {
  static final String apiBaseUrl = _normalizeBaseUrl(
    const String.fromEnvironment(
      'TATUZIN_ADMIN_API_URL',
      defaultValue: 'https://api.tatuzin.com.br/api',
    ),
  );

  static String _normalizeBaseUrl(String rawValue) {
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) {
      if (kReleaseMode) {
        throw StateError(
          'TATUZIN_ADMIN_API_URL precisa ser informado no build de producao do Tatuzin Admin.',
        );
      }
      return 'https://api.tatuzin.com.br/api';
    }
    return trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
  }
}
