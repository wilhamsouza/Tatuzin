enum SyncReconciliationStatus {
  consistent,
  localOnly,
  remoteOnly,
  pendingSync,
  conflict,
  outOfSync,
  missingRemote,
  missingLocal,
  invalidLink,
  orphanRemote,
  unknown,
}

extension SyncReconciliationStatusX on SyncReconciliationStatus {
  String get label {
    switch (this) {
      case SyncReconciliationStatus.consistent:
        return 'Consistente';
      case SyncReconciliationStatus.localOnly:
        return 'Somente local';
      case SyncReconciliationStatus.remoteOnly:
        return 'Somente remoto';
      case SyncReconciliationStatus.pendingSync:
        return 'Pendente de sync';
      case SyncReconciliationStatus.conflict:
        return 'Conflito';
      case SyncReconciliationStatus.outOfSync:
        return 'Divergente';
      case SyncReconciliationStatus.missingRemote:
        return 'Ausente no remoto';
      case SyncReconciliationStatus.missingLocal:
        return 'Ausente no local';
      case SyncReconciliationStatus.invalidLink:
        return 'Vinculo invalido';
      case SyncReconciliationStatus.orphanRemote:
        return 'Remoto orfao';
      case SyncReconciliationStatus.unknown:
        return 'Desconhecido';
    }
  }

  bool get isHealthy => this == SyncReconciliationStatus.consistent;

  bool get canRepair {
    switch (this) {
      case SyncReconciliationStatus.localOnly:
      case SyncReconciliationStatus.pendingSync:
      case SyncReconciliationStatus.outOfSync:
      case SyncReconciliationStatus.missingRemote:
      case SyncReconciliationStatus.invalidLink:
        return true;
      case SyncReconciliationStatus.consistent:
      case SyncReconciliationStatus.remoteOnly:
      case SyncReconciliationStatus.conflict:
      case SyncReconciliationStatus.missingLocal:
      case SyncReconciliationStatus.orphanRemote:
      case SyncReconciliationStatus.unknown:
        return false;
    }
  }
}
