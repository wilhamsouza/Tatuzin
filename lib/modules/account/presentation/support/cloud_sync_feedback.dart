import '../../../../app/core/sync/sync_batch_result.dart';
import '../providers/account_cloud_providers.dart';

String cloudSyncResultMessage(
  SyncBatchResult result,
  AccountCloudStatusSnapshot cloudStatus,
) {
  final hasAttention =
      result.failedCount > 0 ||
      result.blockedCount > 0 ||
      result.conflictCount > 0 ||
      result.pullFailed ||
      result.snapshotFailed ||
      cloudStatus.hasAttention;
  if (!hasAttention) {
    return 'Nuvem atualizada. Enviados: ${result.syncedCount}.';
  }
  return 'A nuvem precisa de atenção. Seus dados continuam salvos neste aparelho.';
}
