import 'reconciliation_decision_support.dart';
import 'sync_error_type.dart';
import 'sync_feature_keys.dart';
import 'sync_queue_status.dart';
import 'sync_reconciliation_issue.dart';
import 'sync_reconciliation_status.dart';
import 'sync_repair_action_type.dart';
import 'sync_repair_decision.dart';
import 'sync_repair_target.dart';
import 'sync_repairability.dart';

class ReconciliationDecisionPolicy {
  const ReconciliationDecisionPolicy._();

  static SyncRepairDecision buildDecision(
    SyncReconciliationIssue issue,
    List<SyncReconciliationIssue> allIssues,
  ) {
    final remoteMatch =
        ReconciliationDecisionSupport.findSignatureMatchedRemoteIssue(
          issue,
          allIssues,
        );
    final target = SyncRepairTarget(
      featureKey: issue.featureKey,
      entityType: issue.entityType,
      entityLabel: issue.entityLabel,
      localEntityId: issue.localEntityId,
      localUuid: issue.localUuid,
      remoteId: issue.remoteId ?? remoteMatch?.remoteId,
    );
    final hasDependencyBlock =
        issue.queueStatus == SyncQueueStatus.blockedDependency ||
        issue.lastErrorType == SyncErrorType.dependency.storageValue;
    final isPurchase = issue.featureKey == SyncFeatureKeys.purchases;
    final isSale = issue.featureKey == SyncFeatureKeys.sales;
    final isFinancial = issue.featureKey == SyncFeatureKeys.financialEvents;
    final isSupplier = issue.featureKey == SyncFeatureKeys.suppliers;
    final isCategory = issue.featureKey == SyncFeatureKeys.categories;
    final isProduct = issue.featureKey == SyncFeatureKeys.products;
    final isCustomer = issue.featureKey == SyncFeatureKeys.customers;
    final isFinancialSensitive = isPurchase || isSale || isFinancial;

    SyncRepairability repairability = SyncRepairability.notRepairableYet;
    var confidence = 0.40;
    final availableActions = <SyncRepairActionType>[];
    SyncRepairActionType? suggestedActionType;
    var reason = issue.message;
    var requiresConfirmation = false;
    var isBatchSafe = false;

    if (hasDependencyBlock) {
      availableActions.add(SyncRepairActionType.retryDependencyChain);
      suggestedActionType = SyncRepairActionType.retryDependencyChain;
      reason =
          'A fila indica dependencia bloqueada. O repair pode revalidar a cadeia e reenfileirar os pre-requisitos seguros.';
      confidence = isFinancial
          ? 0.62
          : isPurchase
          ? 0.72
          : 0.90;
      repairability = isFinancialSensitive
          ? SyncRepairability.assistedSafe
          : SyncRepairability.autoSafe;
      requiresConfirmation = isFinancialSensitive;
      isBatchSafe = !isFinancialSensitive;
    }

    switch (issue.reasonCode) {
      case 'missing_link_uuid_match':
        availableActions
          ..clear()
          ..add(SyncRepairActionType.relinkRemoteId);
        suggestedActionType = SyncRepairActionType.relinkRemoteId;
        reason =
            'Existe forte evidencia de correspondencia remota segura para religar o remoteId local.';
        confidence = isSale || isFinancial
            ? 0.99
            : isPurchase
            ? 0.96
            : 0.98;
        repairability = isSale || isFinancial
            ? SyncRepairability.assistedSafe
            : isPurchase
            ? SyncRepairability.assistedSafe
            : SyncRepairability.autoSafe;
        requiresConfirmation = isFinancialSensitive;
        isBatchSafe = !isFinancialSensitive && !isPurchase;
        break;
      case 'linked_remote_uuid_mismatch':
      case 'missing_remote':
        availableActions
          ..clear()
          ..add(SyncRepairActionType.clearInvalidRemoteId)
          ..add(SyncRepairActionType.reenqueueForSync);
        suggestedActionType = SyncRepairActionType.clearInvalidRemoteId;
        reason =
            'O vinculo remoto local parece invalido. O repair pode limpar o remoteId quebrado e reclassificar para novo envio.';
        confidence = isSale || isFinancial
            ? 0.45
            : isPurchase
            ? 0.64
            : isSupplier || isCategory
            ? 0.90
            : 0.78;
        repairability = isSale || isFinancial
            ? SyncRepairability.manualReviewOnly
            : isPurchase
            ? SyncRepairability.assistedSafe
            : isSupplier || isCategory
            ? SyncRepairability.autoSafe
            : SyncRepairability.assistedSafe;
        requiresConfirmation = isFinancialSensitive || isPurchase;
        isBatchSafe = !isFinancialSensitive && !isPurchase;
        break;
      case 'missing_link_uuid_payload_diverged':
        availableActions
          ..clear()
          ..add(SyncRepairActionType.reenqueueForSync);
        suggestedActionType = SyncRepairActionType.reenqueueForSync;
        reason =
            'O registro remoto foi encontrado, mas o payload divergiu. O repair apenas prepara um novo envio seguro sem sobrescrever automaticamente o espelho.';
        confidence = isFinancialSensitive ? 0.50 : 0.82;
        repairability = isFinancialSensitive
            ? SyncRepairability.manualReviewOnly
            : SyncRepairability.assistedSafe;
        requiresConfirmation = true;
        isBatchSafe = false;
        break;
      case 'payload_mismatch':
        availableActions
          ..clear()
          ..add(SyncRepairActionType.reenqueueForSync);
        suggestedActionType = SyncRepairActionType.reenqueueForSync;
        reason =
            'Os payloads divergiram. O repair apenas reclassifica para novo envio quando isso nao traz risco operacional.';
        confidence = isSale || isFinancial
            ? 0.46
            : isPurchase
            ? 0.58
            : isCategory || isSupplier
            ? 0.86
            : 0.72;
        repairability = isSale || isFinancial
            ? SyncRepairability.manualReviewOnly
            : isPurchase
            ? SyncRepairability.manualReviewOnly
            : isCategory || isSupplier
            ? SyncRepairability.assistedSafe
            : SyncRepairability.assistedSafe;
        requiresConfirmation = !isCategory;
        isBatchSafe = isCategory;
        break;
      case 'conflict_open':
        availableActions
          ..clear()
          ..add(SyncRepairActionType.markConflictReviewed);
        suggestedActionType = SyncRepairActionType.markConflictReviewed;
        reason =
            'Existe um conflito aberto. Esta fase apenas registra a revisao manual sem tentar sobrescrever dados.';
        confidence = 0.99;
        repairability = SyncRepairability.manualReviewOnly;
        requiresConfirmation = true;
        isBatchSafe = false;
        break;
      case 'remote_only':
      case 'orphan_remote':
      case 'feature_not_supported':
      case 'remote_fetch_failed':
        availableActions.clear();
        suggestedActionType = null;
        reason = issue.message;
        confidence = 0.20;
        repairability = issue.reasonCode == 'remote_fetch_failed'
            ? SyncRepairability.blocked
            : SyncRepairability.notRepairableYet;
        requiresConfirmation = false;
        isBatchSafe = false;
        break;
      case 'local_only':
      case 'local_pending':
      case 'pending_with_remote_link':
        if (remoteMatch != null) {
          availableActions
            ..clear()
            ..add(SyncRepairActionType.relinkRemoteId);
          suggestedActionType = SyncRepairActionType.relinkRemoteId;
          reason =
              'Foi encontrada uma correspondencia remota segura pela assinatura do payload. O repair pode religar o remoteId local.';
          confidence = isPurchase
              ? 0.95
              : isSale || isFinancial
              ? 0.55
              : isSupplier || isCategory
              ? 0.94
              : 0.86;
          repairability = isSale || isFinancial
              ? SyncRepairability.manualReviewOnly
              : isPurchase
              ? SyncRepairability.assistedSafe
              : isSupplier || isCategory
              ? SyncRepairability.autoSafe
              : SyncRepairability.assistedSafe;
          requiresConfirmation = isFinancialSensitive || isPurchase;
          isBatchSafe = !isFinancialSensitive && !isPurchase;
          break;
        }

        if (issue.canMarkForResync) {
          availableActions
            ..clear()
            ..add(SyncRepairActionType.reenqueueForSync);
          suggestedActionType = SyncRepairActionType.reenqueueForSync;
          reason =
              'O item pode ser preparado novamente para a fila, preservando a fonte de verdade local.';
          confidence = isSale || isFinancial
              ? 0.66
              : isPurchase
              ? 0.78
              : isSupplier || isCategory
              ? 0.94
              : isProduct || isCustomer
              ? 0.86
              : 0.72;
          repairability = isSale || isFinancial
              ? SyncRepairability.assistedSafe
              : isPurchase
              ? SyncRepairability.assistedSafe
              : SyncRepairability.autoSafe;
          requiresConfirmation = isFinancialSensitive || isPurchase;
          isBatchSafe = !isFinancialSensitive && !isPurchase;
        }
        break;
    }

    if (availableActions.isEmpty &&
        (issue.status == SyncReconciliationStatus.invalidLink ||
            issue.status == SyncReconciliationStatus.missingRemote)) {
      availableActions.add(SyncRepairActionType.revalidateRemotePresence);
      suggestedActionType ??= SyncRepairActionType.revalidateRemotePresence;
      repairability = SyncRepairability.notRepairableYet;
      reason =
          'O item exige revalidacao antes de qualquer repair estrutural mais forte.';
      confidence = 0.35;
      requiresConfirmation = false;
      isBatchSafe = false;
    }

    return SyncRepairDecision(
      target: target,
      status: issue.status,
      repairability: repairability,
      reason: reason,
      confidence: confidence,
      availableActions: List<SyncRepairActionType>.unmodifiable(
        availableActions,
      ),
      suggestedActionType: suggestedActionType,
      isBatchSafe: isBatchSafe,
      requiresConfirmation: requiresConfirmation,
      queueStatus: issue.queueStatus,
      metadataStatus: issue.metadataStatus,
      lastError: issue.lastError,
      lastErrorType: issue.lastErrorType,
      localPayloadSignature: issue.localPayloadSignature,
      remotePayloadSignature:
          issue.remotePayloadSignature ?? remoteMatch?.remotePayloadSignature,
    );
  }
}
