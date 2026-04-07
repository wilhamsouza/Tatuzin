enum SyncAuditEventType {
  queued,
  queueCompacted,
  processingStarted,
  synced,
  blockedDependency,
  failed,
  conflictDetected,
  remoteIdentityLost,
  remoteIdCleared,
  metadataReclassifiedForReupload,
  queueReenqueuedAsCreate,
  dependencyRevalidationTriggered,
  reconciliationChecked,
  repairQueued,
  repairRequested,
  repairApplied,
  repairSkipped,
  repairFailed,
  relinkApplied,
  relinkRejected,
  statusReclassified,
  dependencyChainRetried,
  staleBlockCleared,
  reenqueueRequested,
  repairManualReviewRequired,
}

extension SyncAuditEventTypeX on SyncAuditEventType {
  String get storageValue {
    switch (this) {
      case SyncAuditEventType.queued:
        return 'queued';
      case SyncAuditEventType.queueCompacted:
        return 'queue_compacted';
      case SyncAuditEventType.processingStarted:
        return 'processing_started';
      case SyncAuditEventType.synced:
        return 'synced';
      case SyncAuditEventType.blockedDependency:
        return 'blocked_dependency';
      case SyncAuditEventType.failed:
        return 'failed';
      case SyncAuditEventType.conflictDetected:
        return 'conflict_detected';
      case SyncAuditEventType.remoteIdentityLost:
        return 'remote_identity_lost';
      case SyncAuditEventType.remoteIdCleared:
        return 'remote_id_cleared';
      case SyncAuditEventType.metadataReclassifiedForReupload:
        return 'metadata_reclassified_for_reupload';
      case SyncAuditEventType.queueReenqueuedAsCreate:
        return 'queue_reenqueued_as_create';
      case SyncAuditEventType.dependencyRevalidationTriggered:
        return 'dependency_revalidation_triggered';
      case SyncAuditEventType.reconciliationChecked:
        return 'reconciliation_checked';
      case SyncAuditEventType.repairQueued:
        return 'repair_queued';
      case SyncAuditEventType.repairRequested:
        return 'repair_requested';
      case SyncAuditEventType.repairApplied:
        return 'repair_applied';
      case SyncAuditEventType.repairSkipped:
        return 'repair_skipped';
      case SyncAuditEventType.repairFailed:
        return 'repair_failed';
      case SyncAuditEventType.relinkApplied:
        return 'relink_applied';
      case SyncAuditEventType.relinkRejected:
        return 'relink_rejected';
      case SyncAuditEventType.statusReclassified:
        return 'status_reclassified';
      case SyncAuditEventType.dependencyChainRetried:
        return 'dependency_chain_retried';
      case SyncAuditEventType.staleBlockCleared:
        return 'stale_block_cleared';
      case SyncAuditEventType.reenqueueRequested:
        return 'reenqueue_requested';
      case SyncAuditEventType.repairManualReviewRequired:
        return 'repair_manual_review_required';
    }
  }

  String get label {
    switch (this) {
      case SyncAuditEventType.queued:
        return 'Enfileirado';
      case SyncAuditEventType.queueCompacted:
        return 'Fila consolidada';
      case SyncAuditEventType.processingStarted:
        return 'Processamento iniciado';
      case SyncAuditEventType.synced:
        return 'Sincronizado';
      case SyncAuditEventType.blockedDependency:
        return 'Bloqueado por dependencia';
      case SyncAuditEventType.failed:
        return 'Falhou';
      case SyncAuditEventType.conflictDetected:
        return 'Conflito detectado';
      case SyncAuditEventType.remoteIdentityLost:
        return 'Identidade remota perdida';
      case SyncAuditEventType.remoteIdCleared:
        return 'RemoteId limpo';
      case SyncAuditEventType.metadataReclassifiedForReupload:
        return 'Metadata reclassificada';
      case SyncAuditEventType.queueReenqueuedAsCreate:
        return 'Fila reenfileirada como criacao';
      case SyncAuditEventType.dependencyRevalidationTriggered:
        return 'Dependencias revalidadas';
      case SyncAuditEventType.reconciliationChecked:
        return 'Reconciliacao';
      case SyncAuditEventType.repairQueued:
        return 'Marcado para reenvio';
      case SyncAuditEventType.repairRequested:
        return 'Repair solicitado';
      case SyncAuditEventType.repairApplied:
        return 'Repair aplicado';
      case SyncAuditEventType.repairSkipped:
        return 'Repair ignorado';
      case SyncAuditEventType.repairFailed:
        return 'Repair falhou';
      case SyncAuditEventType.relinkApplied:
        return 'Relink aplicado';
      case SyncAuditEventType.relinkRejected:
        return 'Relink rejeitado';
      case SyncAuditEventType.statusReclassified:
        return 'Status reclassificado';
      case SyncAuditEventType.dependencyChainRetried:
        return 'Dependencia reprocessada';
      case SyncAuditEventType.staleBlockCleared:
        return 'Bloqueio limpo';
      case SyncAuditEventType.reenqueueRequested:
        return 'Reenvio solicitado';
      case SyncAuditEventType.repairManualReviewRequired:
        return 'Revisao manual';
    }
  }
}

SyncAuditEventType syncAuditEventTypeFromStorage(String? value) {
  switch (value) {
    case 'queued':
      return SyncAuditEventType.queued;
    case 'queue_compacted':
      return SyncAuditEventType.queueCompacted;
    case 'processing_started':
      return SyncAuditEventType.processingStarted;
    case 'synced':
      return SyncAuditEventType.synced;
    case 'blocked_dependency':
      return SyncAuditEventType.blockedDependency;
    case 'failed':
      return SyncAuditEventType.failed;
    case 'conflict_detected':
      return SyncAuditEventType.conflictDetected;
    case 'remote_identity_lost':
      return SyncAuditEventType.remoteIdentityLost;
    case 'remote_id_cleared':
      return SyncAuditEventType.remoteIdCleared;
    case 'metadata_reclassified_for_reupload':
      return SyncAuditEventType.metadataReclassifiedForReupload;
    case 'queue_reenqueued_as_create':
      return SyncAuditEventType.queueReenqueuedAsCreate;
    case 'dependency_revalidation_triggered':
      return SyncAuditEventType.dependencyRevalidationTriggered;
    case 'repair_queued':
      return SyncAuditEventType.repairQueued;
    case 'repair_requested':
      return SyncAuditEventType.repairRequested;
    case 'repair_applied':
      return SyncAuditEventType.repairApplied;
    case 'repair_skipped':
      return SyncAuditEventType.repairSkipped;
    case 'repair_failed':
      return SyncAuditEventType.repairFailed;
    case 'relink_applied':
      return SyncAuditEventType.relinkApplied;
    case 'relink_rejected':
      return SyncAuditEventType.relinkRejected;
    case 'status_reclassified':
      return SyncAuditEventType.statusReclassified;
    case 'dependency_chain_retried':
      return SyncAuditEventType.dependencyChainRetried;
    case 'stale_block_cleared':
      return SyncAuditEventType.staleBlockCleared;
    case 'reenqueue_requested':
      return SyncAuditEventType.reenqueueRequested;
    case 'repair_manual_review_required':
      return SyncAuditEventType.repairManualReviewRequired;
    case 'reconciliation_checked':
    default:
      return SyncAuditEventType.reconciliationChecked;
  }
}
