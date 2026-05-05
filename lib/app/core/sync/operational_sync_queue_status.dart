enum OperationalSyncQueueStatus {
  pending,
  pushing,
  accepted,
  duplicate,
  rejected,
  conflict,
  failed,
}

extension OperationalSyncQueueStatusX on OperationalSyncQueueStatus {
  String get storageValue {
    switch (this) {
      case OperationalSyncQueueStatus.pending:
        return 'pending';
      case OperationalSyncQueueStatus.pushing:
        return 'pushing';
      case OperationalSyncQueueStatus.accepted:
        return 'accepted';
      case OperationalSyncQueueStatus.duplicate:
        return 'duplicate';
      case OperationalSyncQueueStatus.rejected:
        return 'rejected';
      case OperationalSyncQueueStatus.conflict:
        return 'conflict';
      case OperationalSyncQueueStatus.failed:
        return 'failed';
    }
  }

  bool get canBePushed {
    switch (this) {
      case OperationalSyncQueueStatus.pending:
      case OperationalSyncQueueStatus.failed:
        return true;
      case OperationalSyncQueueStatus.pushing:
      case OperationalSyncQueueStatus.accepted:
      case OperationalSyncQueueStatus.duplicate:
      case OperationalSyncQueueStatus.rejected:
      case OperationalSyncQueueStatus.conflict:
        return false;
    }
  }
}

OperationalSyncQueueStatus operationalSyncQueueStatusFromStorage(
  String? value,
) {
  switch (value) {
    case 'pushing':
      return OperationalSyncQueueStatus.pushing;
    case 'accepted':
      return OperationalSyncQueueStatus.accepted;
    case 'duplicate':
      return OperationalSyncQueueStatus.duplicate;
    case 'rejected':
      return OperationalSyncQueueStatus.rejected;
    case 'conflict':
      return OperationalSyncQueueStatus.conflict;
    case 'failed':
      return OperationalSyncQueueStatus.failed;
    case 'pending':
    default:
      return OperationalSyncQueueStatus.pending;
  }
}
