import 'sync_error_type.dart';

class SyncRetryPolicy {
  const SyncRetryPolicy({this.maxAttempts = 5});

  final int maxAttempts;

  DateTime? nextRetryAt({
    required int attemptCount,
    required SyncErrorType errorType,
    required DateTime now,
  }) {
    if (!errorType.isRetryable || attemptCount >= maxAttempts) {
      return null;
    }

    final minutes = switch (attemptCount) {
      <= 1 => 1,
      2 => 3,
      3 => 10,
      4 => 30,
      _ => 60,
    };

    return now.add(Duration(minutes: minutes));
  }
}
