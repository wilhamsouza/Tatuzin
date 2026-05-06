enum SyncDisplayState {
  syncing,
  pending,
  conflict,
  error,
  serverDataStale,
  synced,
}

extension SyncDisplayStateX on SyncDisplayState {
  String get label {
    switch (this) {
      case SyncDisplayState.syncing:
        return 'Sincronizando';
      case SyncDisplayState.pending:
        return 'Pendente';
      case SyncDisplayState.conflict:
        return 'Com conflito';
      case SyncDisplayState.error:
        return 'Erro de sincronizacao';
      case SyncDisplayState.serverDataStale:
        return 'Dados do servidor desatualizados';
      case SyncDisplayState.synced:
        return 'Sincronizado';
    }
  }
}
