import 'package:flutter/foundation.dart';

abstract final class AppLogger {
  static void info(String message) {
    _print('INFO', message);
  }

  static void warn(String message) {
    _print('WARN', message);
  }

  static void error(String message, {Object? error, StackTrace? stackTrace}) {
    final buffer = StringBuffer(message);
    if (error != null) {
      buffer.write(' | error=$error');
    }
    if (stackTrace != null) {
      buffer.write(' | stackTrace=$stackTrace');
    }
    _print('ERROR', buffer.toString());
  }

  static void _print(String level, String message) {
    debugPrint('[${DateTime.now().toIso8601String()}][$level] $message');
  }
}
