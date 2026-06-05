import 'package:flutter/foundation.dart';

abstract final class AppLogger {
  static void info(String message) {
    _print('INFO', _sanitize(message));
  }

  static void warn(String message) {
    _print('WARN', _sanitize(message));
  }

  static void error(String message, {Object? error, StackTrace? stackTrace}) {
    final buffer = StringBuffer(message);
    if (error != null) {
      buffer.write(' | error=$error');
    }
    if (stackTrace != null) {
      buffer.write(' | stackTrace=$stackTrace');
    }
    _print('ERROR', _sanitize(buffer.toString()));
  }

  static void _print(String level, String message) {
    if (kReleaseMode) {
      return;
    }
    debugPrint('[${DateTime.now().toIso8601String()}][$level] $message');
  }

  static String sanitizeForTesting(String message) => _sanitize(message);

  static String _sanitize(String message) {
    return _redactAfterPrefix(
      _redactAfterPrefix(
        _redactAfterPrefix(
          message,
          RegExp(
            r'(Authorization\s*[:=]\s*Bearer\s+)[^\s|,;}]+',
            caseSensitive: false,
          ),
        ),
        RegExp(
          r'((?:access|refresh)[_-]?token\s*[:=]\s*)[^\s|,;}]+',
          caseSensitive: false,
        ),
      ),
      RegExp(
        r'((?:password|senha|secret)\s*[:=]\s*)[^\s|,;}]+',
        caseSensitive: false,
      ),
    );
  }

  static String _redactAfterPrefix(String message, RegExp pattern) {
    return message.replaceAllMapped(pattern, (match) {
      return '${match.group(1)}<redacted>';
    });
  }
}
