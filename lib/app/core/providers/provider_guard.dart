import 'dart:async';

import '../utils/app_logger.dart';

const defaultProviderTimeout = Duration(seconds: 15);
const localProviderTimeout = Duration(seconds: 12);
const syncProviderTimeout = Duration(seconds: 10);

Future<T> runProviderGuarded<T>(
  String label,
  Future<T> Function() action, {
  Duration timeout = defaultProviderTimeout,
}) async {
  final stopwatch = Stopwatch()..start();
  AppLogger.info('$label started | timeout_seconds=${timeout.inSeconds}');
  try {
    final result = await action().timeout(timeout);
    AppLogger.info(
      '$label finished | duration_ms=${stopwatch.elapsedMilliseconds}',
    );
    return result;
  } on TimeoutException catch (error, stackTrace) {
    AppLogger.error(
      '$label timeout | duration_ms=${stopwatch.elapsedMilliseconds} | '
      'timeout_seconds=${timeout.inSeconds}',
      error: error,
      stackTrace: stackTrace,
    );
    rethrow;
  } catch (error, stackTrace) {
    AppLogger.error(
      '$label failed | duration_ms=${stopwatch.elapsedMilliseconds}',
      error: error,
      stackTrace: stackTrace,
    );
    rethrow;
  }
}
