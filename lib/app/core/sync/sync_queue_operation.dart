enum SyncQueueOperation { create, update, delete, cancel }

extension SyncQueueOperationX on SyncQueueOperation {
  String get storageValue {
    switch (this) {
      case SyncQueueOperation.create:
        return 'create';
      case SyncQueueOperation.update:
        return 'update';
      case SyncQueueOperation.delete:
        return 'delete';
      case SyncQueueOperation.cancel:
        return 'cancel';
    }
  }

  String get label {
    switch (this) {
      case SyncQueueOperation.create:
        return 'Criacao';
      case SyncQueueOperation.update:
        return 'Atualizacao';
      case SyncQueueOperation.delete:
        return 'Exclusao';
      case SyncQueueOperation.cancel:
        return 'Cancelamento';
    }
  }
}

SyncQueueOperation syncQueueOperationFromStorage(String? value) {
  switch (value) {
    case 'create':
      return SyncQueueOperation.create;
    case 'delete':
      return SyncQueueOperation.delete;
    case 'cancel':
      return SyncQueueOperation.cancel;
    case 'update':
    default:
      return SyncQueueOperation.update;
  }
}
