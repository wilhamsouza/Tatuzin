import 'package:flutter/material.dart';

import '../../../../app/core/sync/sync_batch_result.dart';
import '../../../../app/core/sync/sync_repair_result.dart';
import 'system_page_helpers.dart';

void showSystemSnackbar(ScaffoldMessengerState messenger, String message) {
  messenger.showSnackBar(SnackBar(content: Text(message)));
}

String buildFeatureSyncMessage({
  required String featureLabel,
  required String syncedLabel,
  required String blockedLabel,
  required SyncBatchResult result,
}) {
  return '$featureLabel processados: ${result.processedCount}, $syncedLabel: ${result.syncedCount}, $blockedLabel: ${result.blockedCount}, conflitos: ${result.conflictCount}, falhas: ${result.failedCount}.';
}

String buildFinancialSyncMessage(SyncBatchResult result) {
  return 'Eventos financeiros processados. Processados: ${result.processedCount}, sync: ${result.syncedCount}, bloqueados: ${result.blockedCount}, conflitos: ${result.conflictCount}, falhas: ${result.failedCount}.';
}

String buildRetryMessage(SyncBatchResult result) {
  return '${result.message} Processados: ${result.processedCount}, sync: ${result.syncedCount}, bloqueados: ${result.blockedCount}, conflitos: ${result.conflictCount}, falhas: ${result.failedCount}.';
}

String buildReconciliationMessage((int, int, int, int) overview) {
  return 'Reconciliacao concluida. Consistentes: ${overview.$1}, pendentes: ${overview.$2}, divergentes: ${overview.$3}, conflitos: ${overview.$4}.';
}

String buildRepairMessage(SyncRepairResult result) {
  return '${result.message} Solicitados: ${result.requestedCount}, aplicados: ${result.appliedCount}, ignorados: ${result.skippedCount}, falhas: ${result.failedCount}.';
}

String buildFeatureRepairMessage({
  required String featureKey,
  required SyncRepairResult result,
}) {
  return '${displayNameForSystemFeature(featureKey)}: ${result.message} Aplicados: ${result.appliedCount}, ignorados: ${result.skippedCount}, falhas: ${result.failedCount}.';
}

String buildRepairActionMessage({
  required String actionLabel,
  required SyncRepairResult result,
}) {
  return '$actionLabel: ${result.message} Aplicados: ${result.appliedCount}, ignorados: ${result.skippedCount}, falhas: ${result.failedCount}.';
}

String buildRepairFeatureQueueMessage({
  required String featureKey,
  required int repairedCount,
}) {
  final featureLabel = displayNameForSystemFeature(featureKey).toLowerCase();
  return repairedCount == 0
      ? 'Nenhum item elegivel para reenvio em $featureLabel.'
      : '$repairedCount item(ns) de $featureLabel foram marcados para reenvio.';
}
