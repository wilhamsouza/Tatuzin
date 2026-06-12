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

final class TenantPendingDeletionException extends AppException {
  const TenantPendingDeletionException({
    this.statusCode = 423,
    this.requestPath,
    this.acknowledgementToken,
    this.tenantDeletionRequestId,
    this.companyId,
    this.clientInstanceId,
  }) : super(tenantPendingDeletionMessage, cause: statusCode);

  static const code = 'TENANT_PENDING_DELETION';

  final int statusCode;
  final String? requestPath;
  final String? acknowledgementToken;
  final String? tenantDeletionRequestId;
  final String? companyId;
  final String? clientInstanceId;
}

const tenantPendingDeletionMessage =
    'Esta empresa esta em processo de exclusao. O acesso operacional e a '
    'sincronizacao foram bloqueados. Os dados locais deste dispositivo nao '
    'foram apagados automaticamente.';

final class InitialPasswordChangeRequiredException extends AppException {
  const InitialPasswordChangeRequiredException(super.message, {super.cause});
}

final class AppStartupException extends AppException {
  const AppStartupException(super.message, {super.cause});
}
