enum SyncDisplayState { syncing, pending, attention, synced }

extension SyncDisplayStateX on SyncDisplayState {
  String get label {
    switch (this) {
      case SyncDisplayState.syncing:
        return 'Sincronizando';
      case SyncDisplayState.pending:
        return 'Pendencias para sincronizar';
      case SyncDisplayState.attention:
        return 'Precisa de atencao';
      case SyncDisplayState.synced:
        return 'Sincronizado';
    }
  }
}
