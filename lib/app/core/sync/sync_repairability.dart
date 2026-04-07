enum SyncRepairability {
  autoSafe,
  assistedSafe,
  manualReviewOnly,
  blocked,
  notRepairableYet,
}

extension SyncRepairabilityX on SyncRepairability {
  String get label {
    switch (this) {
      case SyncRepairability.autoSafe:
        return 'Seguro';
      case SyncRepairability.assistedSafe:
        return 'Assistido';
      case SyncRepairability.manualReviewOnly:
        return 'Revisao manual';
      case SyncRepairability.blocked:
        return 'Bloqueado';
      case SyncRepairability.notRepairableYet:
        return 'Nao reparavel ainda';
    }
  }

  bool get isActionable {
    switch (this) {
      case SyncRepairability.autoSafe:
      case SyncRepairability.assistedSafe:
        return true;
      case SyncRepairability.manualReviewOnly:
      case SyncRepairability.blocked:
      case SyncRepairability.notRepairableYet:
        return false;
    }
  }

  bool get requiresConfirmation => this == SyncRepairability.assistedSafe;

  bool get isReviewOnly => this == SyncRepairability.manualReviewOnly;
}
