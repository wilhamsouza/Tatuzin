import 'reconciliation_local_comparable_record.dart';
import 'sync_queue_item.dart';
import 'sync_queue_status.dart';
import 'sync_reconciliation_issue.dart';
import 'sync_reconciliation_result.dart';
import 'sync_reconciliation_status.dart';
import 'sync_repair_decision.dart';
import 'sync_repair_target.dart';
import 'sync_repairability.dart';
import 'sync_status.dart';

class ReconciliationDecisionSupport {
  const ReconciliationDecisionSupport._();

  static bool hasPendingMetadata(SyncStatus? status) {
    return status == SyncStatus.pendingUpload ||
        status == SyncStatus.pendingUpdate ||
        status == SyncStatus.syncError;
  }

  static bool hasPendingQueue(SyncQueueItem? item) {
    if (item == null) {
      return false;
    }

    return item.status == SyncQueueStatus.pendingUpload ||
        item.status == SyncQueueStatus.pendingUpdate ||
        item.status == SyncQueueStatus.processing ||
        item.status == SyncQueueStatus.syncError ||
        item.status == SyncQueueStatus.blockedDependency;
  }

  static String pendingMessage(ReconciliationLocalComparableRecord local) {
    final queueItem = local.queueItem;
    if (queueItem == null) {
      return 'O registro local ainda aguarda envio para o backend.';
    }

    switch (queueItem.status) {
      case SyncQueueStatus.pendingUpload:
      case SyncQueueStatus.pendingUpdate:
        return 'O item esta aguardando a proxima rodada da fila de sincronizacao.';
      case SyncQueueStatus.processing:
        return 'O item esta em processamento pela fila de sincronizacao.';
      case SyncQueueStatus.syncError:
        return local.lastError ??
            queueItem.lastError ??
            'O item falhou na ultima tentativa e aguarda novo processamento.';
      case SyncQueueStatus.blockedDependency:
        return queueItem.lastError ??
            local.lastError ??
            'O item aguarda uma dependencia remota antes de ser reenviado.';
      case SyncQueueStatus.conflict:
        return queueItem.conflictReason ??
            local.lastError ??
            'Existe um conflito em aberto para este item.';
      case SyncQueueStatus.synced:
        return 'O item ainda nao foi revalidado contra o espelho remoto.';
    }
  }

  static int severityOf(SyncReconciliationStatus status) {
    switch (status) {
      case SyncReconciliationStatus.conflict:
        return 100;
      case SyncReconciliationStatus.invalidLink:
        return 90;
      case SyncReconciliationStatus.missingRemote:
      case SyncReconciliationStatus.missingLocal:
        return 80;
      case SyncReconciliationStatus.outOfSync:
        return 70;
      case SyncReconciliationStatus.orphanRemote:
      case SyncReconciliationStatus.remoteOnly:
        return 60;
      case SyncReconciliationStatus.pendingSync:
        return 50;
      case SyncReconciliationStatus.localOnly:
        return 40;
      case SyncReconciliationStatus.unknown:
        return 30;
      case SyncReconciliationStatus.consistent:
        return 0;
    }
  }

  static SyncReconciliationIssue? findIssue(
    List<SyncReconciliationResult> results,
    SyncRepairTarget target,
  ) {
    for (final result in results) {
      for (final issue in result.issues) {
        final localKey =
            issue.localEntityId?.toString() ??
            issue.localUuid ??
            issue.remoteId ??
            'na';
        final stableKey = '${issue.featureKey}:${issue.entityType}:$localKey';
        if (stableKey == target.stableKey) {
          return issue;
        }
      }
    }

    return null;
  }

  static SyncRepairDecision? findDecision(
    List<SyncRepairDecision> decisions,
    SyncRepairTarget target,
  ) {
    for (final decision in decisions) {
      if (decision.stableKey == target.stableKey) {
        return decision;
      }
    }

    return null;
  }

  static int repairPriority(SyncRepairDecision decision) {
    final repairabilityWeight = switch (decision.repairability) {
      SyncRepairability.autoSafe => 50,
      SyncRepairability.assistedSafe => 40,
      SyncRepairability.manualReviewOnly => 20,
      SyncRepairability.blocked => 10,
      SyncRepairability.notRepairableYet => 0,
    };

    return severityOf(decision.status) +
        repairabilityWeight +
        (decision.isBatchSafe ? 5 : 0);
  }

  static SyncReconciliationIssue? findSignatureMatchedRemoteIssue(
    SyncReconciliationIssue issue,
    List<SyncReconciliationIssue> allIssues,
  ) {
    final localSignature = issue.localPayloadSignature;
    if (localSignature == null || localSignature.isEmpty) {
      return null;
    }

    final candidates = allIssues
        .where(
          (candidate) =>
              candidate.featureKey == issue.featureKey &&
              (candidate.status == SyncReconciliationStatus.remoteOnly ||
                  candidate.status == SyncReconciliationStatus.orphanRemote) &&
              candidate.remotePayloadSignature == localSignature,
        )
        .toList();
    if (candidates.length != 1) {
      return null;
    }

    return candidates.first;
  }
}
