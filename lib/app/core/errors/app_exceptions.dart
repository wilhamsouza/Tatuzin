sealed class AppException implements Exception {
  const AppException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => cause == null ? message : '$message: $cause';
}

final class DatabaseInitializationException extends AppException {
  const DatabaseInitializationException(super.message, {super.cause});
}

final class ValidationException extends AppException {
  const ValidationException(super.message, {super.cause});
}

final class StockConflictException extends AppException {
  const StockConflictException(super.message, {super.cause});
}

final class NetworkRequestException extends AppException {
  const NetworkRequestException(super.message, {super.cause});
}

final class AuthenticationException extends AppException {
  const AuthenticationException(super.message, {super.cause});
}

final class AppStartupException extends AppException {
  const AppStartupException(super.message, {super.cause});
}
