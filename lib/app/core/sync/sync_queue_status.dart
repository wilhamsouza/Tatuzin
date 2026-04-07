enum SyncQueueStatus {
  pendingUpload,
  pendingUpdate,
  processing,
  synced,
  syncError,
  blockedDependency,
  conflict,
}

extension SyncQueueStatusX on SyncQueueStatus {
  String get storageValue {
    switch (this) {
      case SyncQueueStatus.pendingUpload:
        return 'pending_upload';
      case SyncQueueStatus.pendingUpdate:
        return 'pending_update';
      case SyncQueueStatus.processing:
        return 'processing';
      case SyncQueueStatus.synced:
        return 'synced';
      case SyncQueueStatus.syncError:
        return 'sync_error';
      case SyncQueueStatus.blockedDependency:
        return 'blocked_dependency';
      case SyncQueueStatus.conflict:
        return 'conflict';
    }
  }

  String get label {
    switch (this) {
      case SyncQueueStatus.pendingUpload:
        return 'Pendente de envio';
      case SyncQueueStatus.pendingUpdate:
        return 'Pendente de atualizacao';
      case SyncQueueStatus.processing:
        return 'Processando';
      case SyncQueueStatus.synced:
        return 'Sincronizado';
      case SyncQueueStatus.syncError:
        return 'Erro';
      case SyncQueueStatus.blockedDependency:
        return 'Bloqueado';
      case SyncQueueStatus.conflict:
        return 'Conflito';
    }
  }

  bool get isActive {
    switch (this) {
      case SyncQueueStatus.pendingUpload:
      case SyncQueueStatus.pendingUpdate:
      case SyncQueueStatus.processing:
      case SyncQueueStatus.syncError:
      case SyncQueueStatus.blockedDependency:
      case SyncQueueStatus.conflict:
        return true;
      case SyncQueueStatus.synced:
        return false;
    }
  }
}

SyncQueueStatus syncQueueStatusFromStorage(String? value) {
  switch (value) {
    case 'pending_upload':
      return SyncQueueStatus.pendingUpload;
    case 'processing':
      return SyncQueueStatus.processing;
    case 'synced':
      return SyncQueueStatus.synced;
    case 'sync_error':
      return SyncQueueStatus.syncError;
    case 'blocked_dependency':
      return SyncQueueStatus.blockedDependency;
    case 'conflict':
      return SyncQueueStatus.conflict;
    case 'pending_update':
    default:
      return SyncQueueStatus.pendingUpdate;
  }
}
