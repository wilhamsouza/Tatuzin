import '../../../../app/core/sync/sync_queue_feature_summary.dart';
import '../../../../app/core/sync/sync_reconciliation_result.dart';

SyncQueueFeatureSummary? findQueueSummary(
  List<SyncQueueFeatureSummary> summaries,
  String featureKey,
) {
  for (final summary in summaries) {
    if (summary.featureKey == featureKey) {
      return summary;
    }
  }

  return null;
}

SyncReconciliationResult? findReconciliationResult(
  List<SyncReconciliationResult> results,
  String featureKey,
) {
  for (final result in results) {
    if (result.featureKey == featureKey) {
      return result;
    }
  }

  return null;
}

(int, int, int, int) buildReconciliationOverview(
  List<SyncReconciliationResult> results,
) {
  var consistent = 0;
  var pending = 0;
  var divergent = 0;
  var conflicts = 0;

  for (final result in results) {
    consistent += result.consistentCount;
    pending += result.pendingSyncCount;
    divergent +=
        result.outOfSyncCount +
        result.missingRemoteCount +
        result.invalidLinkCount +
        result.remoteOnlyCount +
        result.orphanRemoteCount;
    conflicts += result.conflictCount;
  }

  return (consistent, pending, divergent, conflicts);
}

String displayNameForSystemFeature(String featureKey) {
  switch (featureKey) {
    case 'suppliers':
      return 'Fornecedores';
    case 'categories':
      return 'Categorias';
    case 'products':
      return 'Produtos';
    case 'customers':
      return 'Clientes';
    case 'purchases':
      return 'Compras';
    case 'sales':
      return 'Vendas';
    case 'financial_events':
      return 'Eventos financeiros';
    default:
      return featureKey;
  }
}
