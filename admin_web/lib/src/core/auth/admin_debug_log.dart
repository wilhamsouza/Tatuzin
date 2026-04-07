import 'dart:convert';

import 'package:flutter/foundation.dart';

void adminDebugLog(String event, [Map<String, Object?> context = const {}]) {
  if (!kDebugMode) {
    return;
  }

  final payload = <String, Object?>{
    'event': event,
    if (context.isNotEmpty) 'context': _sanitizeContext(context),
  };
  debugPrint('[Tatuzin Admin] ${jsonEncode(payload)}');
}

Map<String, Object?> _sanitizeContext(Map<String, Object?> context) {
  return context.map((key, value) {
    final lowerKey = key.toLowerCase();
    final shouldMask =
        lowerKey.contains('token') || lowerKey.contains('authorization');
    return MapEntry(
      key,
      shouldMask ? summarizeToken(value?.toString()) : _sanitizeValue(value),
    );
  });
}

Object? _sanitizeValue(Object? value) {
  if (value is String) {
    final lower = value.toLowerCase();
    if (lower.contains('token') || lower.contains('bearer')) {
      return summarizeToken(value);
    }
    return value;
  }

  if (value is Map<String, Object?>) {
    return _sanitizeContext(value);
  }

  if (value is Iterable<Object?>) {
    return value.map(_sanitizeValue).toList(growable: false);
  }

  return value;
}

String summarizeToken(String? token) {
  final normalized = token?.trim();
  if (normalized == null || normalized.isEmpty) {
    return 'empty';
  }

  final preview = normalized.length <= 12
      ? normalized
      : '${normalized.substring(0, 6)}...${normalized.substring(normalized.length - 4)}';
  return '$preview(len=${normalized.length})';
}
