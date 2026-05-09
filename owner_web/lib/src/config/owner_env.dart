import 'package:flutter/foundation.dart';

abstract final class OwnerEnv {
  static final String apiBaseUrl = normalizeBaseUrl(
    const String.fromEnvironment(
      'TATUZIN_OWNER_API_URL',
      defaultValue: 'https://api.tatuzin.com.br/api',
    ),
  );

  static String normalizeBaseUrl(String rawValue) {
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) {
      if (kReleaseMode) {
        throw StateError(
          'TATUZIN_OWNER_API_URL precisa ser informado no build de producao do Tatuzin Owner.',
        );
      }
      return 'https://api.tatuzin.com.br/api';
    }
    return trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
  }
}
