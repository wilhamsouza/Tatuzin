import '../errors/app_exceptions.dart';
import 'sync_error_type.dart';

class SyncErrorInfo {
  const SyncErrorInfo({required this.message, required this.type});

  final String message;
  final SyncErrorType type;
}

SyncErrorInfo resolveSyncError(Object error) {
  if (error is AuthenticationException) {
    return SyncErrorInfo(message: error.message, type: SyncErrorType.auth);
  }

  if (error is NetworkRequestException) {
    final statusCode = error.cause is int ? error.cause! as int : null;
    if (statusCode != null) {
      if (statusCode == 408) {
        return SyncErrorInfo(
          message: error.message,
          type: SyncErrorType.timeout,
        );
      }
      if (statusCode == 409) {
        return SyncErrorInfo(
          message: error.message,
          type: SyncErrorType.conflict,
        );
      }
      if (statusCode >= 500) {
        return SyncErrorInfo(
          message: error.message,
          type: SyncErrorType.server,
        );
      }
    }

    if (error.message.toLowerCase().contains('demorou')) {
      return SyncErrorInfo(message: error.message, type: SyncErrorType.timeout);
    }

    return SyncErrorInfo(message: error.message, type: SyncErrorType.network);
  }

  if (error is ValidationException) {
    return SyncErrorInfo(
      message: error.message,
      type: SyncErrorType.validation,
    );
  }

  if (error is StockConflictException) {
    return SyncErrorInfo(message: error.message, type: SyncErrorType.conflict);
  }

  if (error is AppException) {
    return SyncErrorInfo(message: error.message, type: SyncErrorType.unknown);
  }

  return SyncErrorInfo(message: error.toString(), type: SyncErrorType.unknown);
}
