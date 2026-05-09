import 'package:flutter/foundation.dart';

void ownerDebugLog(String event, [Map<String, Object?> data = const {}]) {
  if (!kDebugMode) {
    return;
  }
  debugPrint('owner_web.$event ${sanitizeOwnerDebugData(data)}');
}

Map<String, Object?> sanitizeOwnerDebugData(Map<String, Object?> data) {
  return data.map((key, value) {
    final normalized = key.toLowerCase();
    if (normalized.startsWith('has') && value is bool) {
      return MapEntry(key, value);
    }
    if (normalized.contains('token') ||
        normalized == 'authorization' ||
        normalized.contains('password')) {
      return MapEntry(key, value is String ? value.trim().isNotEmpty : false);
    }
    return MapEntry(key, value);
  });
}
