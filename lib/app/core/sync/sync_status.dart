enum SyncStatus {
  localOnly,
  pendingUpload,
  synced,
  pendingUpdate,
  syncError,
  conflict,
}

extension SyncStatusX on SyncStatus {
  String get storageValue {
    switch (this) {
      case SyncStatus.localOnly:
        return 'local_only';
      case SyncStatus.pendingUpload:
        return 'pending_upload';
      case SyncStatus.synced:
        return 'synced';
      case SyncStatus.pendingUpdate:
        return 'pending_update';
      case SyncStatus.syncError:
        return 'sync_error';
      case SyncStatus.conflict:
        return 'conflict';
    }
  }

  String get label {
    switch (this) {
      case SyncStatus.localOnly:
        return 'Somente local';
      case SyncStatus.pendingUpload:
        return 'Pendente de envio';
      case SyncStatus.synced:
        return 'Sincronizado';
      case SyncStatus.pendingUpdate:
        return 'Pendente de atualização';
      case SyncStatus.syncError:
        return 'Erro de sync';
      case SyncStatus.conflict:
        return 'Conflito';
    }
  }
}

SyncStatus syncStatusFromStorage(String? value) {
  switch (value) {
    case 'pending_upload':
      return SyncStatus.pendingUpload;
    case 'synced':
      return SyncStatus.synced;
    case 'pending_update':
      return SyncStatus.pendingUpdate;
    case 'sync_error':
      return SyncStatus.syncError;
    case 'conflict':
      return SyncStatus.conflict;
    case 'local_only':
    default:
      return SyncStatus.localOnly;
  }
}
