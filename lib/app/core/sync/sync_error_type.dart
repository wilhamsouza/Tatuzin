enum SyncErrorType {
  network,
  timeout,
  auth,
  validation,
  conflict,
  dependency,
  server,
  unknown,
}

extension SyncErrorTypeX on SyncErrorType {
  String get storageValue {
    switch (this) {
      case SyncErrorType.network:
        return 'network';
      case SyncErrorType.timeout:
        return 'timeout';
      case SyncErrorType.auth:
        return 'auth';
      case SyncErrorType.validation:
        return 'validation';
      case SyncErrorType.conflict:
        return 'conflict';
      case SyncErrorType.dependency:
        return 'dependency';
      case SyncErrorType.server:
        return 'server';
      case SyncErrorType.unknown:
        return 'unknown';
    }
  }

  String get label {
    switch (this) {
      case SyncErrorType.network:
        return 'Rede';
      case SyncErrorType.timeout:
        return 'Timeout';
      case SyncErrorType.auth:
        return 'Autenticacao';
      case SyncErrorType.validation:
        return 'Validacao';
      case SyncErrorType.conflict:
        return 'Conflito';
      case SyncErrorType.dependency:
        return 'Dependencia';
      case SyncErrorType.server:
        return 'Servidor';
      case SyncErrorType.unknown:
        return 'Desconhecido';
    }
  }

  bool get isRetryable {
    switch (this) {
      case SyncErrorType.network:
      case SyncErrorType.timeout:
      case SyncErrorType.server:
        return true;
      case SyncErrorType.auth:
      case SyncErrorType.validation:
      case SyncErrorType.conflict:
      case SyncErrorType.dependency:
      case SyncErrorType.unknown:
        return false;
    }
  }
}

SyncErrorType syncErrorTypeFromStorage(String? value) {
  switch (value) {
    case 'network':
      return SyncErrorType.network;
    case 'timeout':
      return SyncErrorType.timeout;
    case 'auth':
    case 'authentication':
      return SyncErrorType.auth;
    case 'validation':
      return SyncErrorType.validation;
    case 'conflict':
      return SyncErrorType.conflict;
    case 'dependency':
      return SyncErrorType.dependency;
    case 'server':
      return SyncErrorType.server;
    case 'application':
    case 'unexpected':
    case 'unknown':
    default:
      return SyncErrorType.unknown;
  }
}
