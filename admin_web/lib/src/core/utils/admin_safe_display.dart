const String adminNotInformedLabel = 'Nao informado';
const String adminUnavailableLabel = 'Indisponivel';
const String adminRedactedLabel = '[redacted]';

String maskAdminEmail(
  String? value, {
  String fallback = adminNotInformedLabel,
}) {
  final normalized = _normalized(value);
  if (normalized == null) {
    return fallback;
  }

  final atIndex = normalized.indexOf('@');
  if (atIndex <= 0 || atIndex == normalized.length - 1) {
    return maskAdminIdentifier(normalized, fallback: fallback);
  }

  final local = normalized.substring(0, atIndex);
  final domain = normalized.substring(atIndex + 1);
  if (local.length == 1) {
    return '${local[0]}***@$domain';
  }

  return '${local[0]}***${local[local.length - 1]}@$domain';
}

String maskAdminIdentifier(
  String? value, {
  int prefix = 4,
  int suffix = 4,
  String fallback = adminUnavailableLabel,
}) {
  final normalized = _normalized(value);
  if (normalized == null) {
    return fallback;
  }

  final safePrefix = prefix.clamp(1, normalized.length).toInt();
  final safeSuffix = suffix.clamp(1, normalized.length).toInt();
  if (normalized.length <= safePrefix + safeSuffix + 3) {
    return normalized;
  }

  return '${normalized.substring(0, safePrefix)}...'
      '${normalized.substring(normalized.length - safeSuffix)}';
}

String safeAdminSensitiveText(
  String? value, {
  String fallback = adminUnavailableLabel,
}) {
  final normalized = _normalized(value);
  if (normalized == null) {
    return fallback;
  }

  if (_looksSensitive(normalized)) {
    return adminRedactedLabel;
  }

  if (normalized.length > 24) {
    return maskAdminIdentifier(normalized, fallback: fallback);
  }

  return normalized;
}

bool _looksSensitive(String value) {
  final lower = value.toLowerCase();
  if (lower.startsWith('bearer ') ||
      lower.contains('authorization') ||
      lower.contains('access_token') ||
      lower.contains('accesstoken') ||
      lower.contains('refresh_token') ||
      lower.contains('refreshtoken') ||
      lower.contains('password') ||
      lower.contains('secret') ||
      lower.contains('webhook') ||
      lower.contains('x-signature') ||
      lower.contains('api_key') ||
      lower.contains('apikey')) {
    return true;
  }

  return RegExp(r'^[A-Za-z0-9_=]{32,}$').hasMatch(value) ||
      RegExp(
        r'^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$',
      ).hasMatch(value);
}

String? _normalized(String? value) {
  final normalized = value?.trim();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }
  return normalized;
}
