import '../utils/app_logger.dart';

class SyncDateFallback {
  const SyncDateFallback({required this.label, required this.value});

  final String label;
  final Object? value;
}

class SyncDateNormalizationResult {
  const SyncDateNormalizationResult({
    required this.value,
    required this.source,
    required this.fallbackUsed,
    required this.rawType,
  });

  final DateTime value;
  final String source;
  final bool fallbackUsed;
  final String rawType;

  String toIsoUtc() => value.toUtc().toIso8601String();
}

SyncDateNormalizationResult normalizeSyncDate(
  Object? value, {
  required String entity,
  required String field,
  required List<SyncDateFallback> fallbacks,
  DateTime? now,
}) {
  final parsed = _parseSyncDate(value);
  if (parsed != null) {
    final result = SyncDateNormalizationResult(
      value: parsed.value.toUtc(),
      source: parsed.source,
      fallbackUsed: false,
      rawType: _rawTypeOf(value),
    );
    AppLogger.info(
      '[SyncDate] normalized entity=$entity field=$field '
      'source=${result.source} fallback=false',
    );
    return result;
  }

  for (final fallback in fallbacks) {
    final parsedFallback = _parseSyncDate(fallback.value);
    if (parsedFallback == null) {
      continue;
    }

    final result = SyncDateNormalizationResult(
      value: parsedFallback.value.toUtc(),
      source: fallback.label,
      fallbackUsed: true,
      rawType: _rawTypeOf(value),
    );
    AppLogger.warn(
      '[SyncDate] invalid entity=$entity field=$field '
      'rawType=${result.rawType} fallbackUsed=${fallback.label}',
    );
    AppLogger.info(
      '[SyncDate] normalized entity=$entity field=$field '
      'source=${result.source} fallback=true',
    );
    return result;
  }

  final generatedFallback = (now ?? DateTime.now()).toUtc();
  final result = SyncDateNormalizationResult(
    value: generatedFallback,
    source: 'now',
    fallbackUsed: true,
    rawType: _rawTypeOf(value),
  );
  AppLogger.warn(
    '[SyncDate] invalid entity=$entity field=$field '
    'rawType=${result.rawType} fallbackUsed=now',
  );
  AppLogger.info(
    '[SyncDate] normalized entity=$entity field=$field '
    'source=${result.source} fallback=true',
  );
  return result;
}

_ParsedSyncDate? _parseSyncDate(Object? value) {
  if (value == null) {
    return null;
  }

  if (value is DateTime) {
    return _ParsedSyncDate(
      value,
      value.isUtc ? 'datetime_utc' : 'datetime_local',
    );
  }

  if (value is int) {
    return _parseEpoch(value);
  }

  if (value is double && value.isFinite) {
    return _parseEpoch(value.round());
  }

  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final numericValue = int.tryParse(trimmed);
    if (numericValue != null) {
      return _parseEpoch(numericValue);
    }

    final parsedIso = DateTime.tryParse(trimmed);
    if (parsedIso != null) {
      return _ParsedSyncDate(
        parsedIso,
        parsedIso.isUtc ? 'iso_utc' : 'iso_without_timezone',
      );
    }

    final parsedBrazilian = _parseBrazilianLocalDate(trimmed);
    if (parsedBrazilian != null) {
      return _ParsedSyncDate(parsedBrazilian, 'brazilian_local');
    }
  }

  return null;
}

_ParsedSyncDate? _parseEpoch(int value) {
  final absValue = value.abs();
  if (absValue >= 1000000000000) {
    return _ParsedSyncDate(
      DateTime.fromMillisecondsSinceEpoch(value, isUtc: true),
      'epoch_milliseconds',
    );
  }

  if (absValue >= 1000000000) {
    return _ParsedSyncDate(
      DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true),
      'epoch_seconds',
    );
  }

  return null;
}

DateTime? _parseBrazilianLocalDate(String value) {
  final match = RegExp(
    r'^(\d{1,2})/(\d{1,2})/(\d{4})(?:[ T](\d{1,2}):(\d{2})(?::(\d{2}))?)?$',
  ).firstMatch(value);
  if (match == null) {
    return null;
  }

  final day = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final year = int.parse(match.group(3)!);
  final hour = int.tryParse(match.group(4) ?? '0') ?? 0;
  final minute = int.tryParse(match.group(5) ?? '0') ?? 0;
  final second = int.tryParse(match.group(6) ?? '0') ?? 0;

  final parsed = DateTime(year, month, day, hour, minute, second);
  if (parsed.year != year || parsed.month != month || parsed.day != day) {
    return null;
  }
  return parsed;
}

String _rawTypeOf(Object? value) {
  if (value == null) {
    return 'null';
  }
  if (value is String && value.trim().isEmpty) {
    return 'empty_string';
  }
  return value.runtimeType.toString();
}

class _ParsedSyncDate {
  const _ParsedSyncDate(this.value, this.source);

  final DateTime value;
  final String source;
}
