import '../../../app/core/app_context/app_operational_context.dart';
import '../../../app/core/app_context/data_access_policy.dart';
import '../../../app/core/errors/app_exceptions.dart';
import '../../../app/core/sync/sync_conflict_info.dart';
import '../../../app/core/sync/sync_feature_processor.dart';
import '../../../app/core/sync/sync_queue_item.dart';
import 'datasources/sales_remote_datasource.dart';
import 'models/sale_cancellation_sync_payload.dart';
import 'sqlite_sale_repository.dart';

class SaleCancellationSyncProcessor implements SyncFeatureProcessor {
  const SaleCancellationSyncProcessor({
    required SqliteSaleRepository localRepository,
    required SalesRemoteDatasource remoteDatasource,
    required AppOperationalContext operationalContext,
    required DataAccessPolicy dataAccessPolicy,
  }) : _localRepository = localRepository,
       _remoteDatasource = remoteDatasource,
       _operationalContext = operationalContext,
       _dataAccessPolicy = dataAccessPolicy;

  final SqliteSaleRepository _localRepository;
  final SalesRemoteDatasource _remoteDatasource;
  final AppOperationalContext _operationalContext;
  final DataAccessPolicy _dataAccessPolicy;

  @override
  String get featureKey => SqliteSaleRepository.cancellationFeatureKey;

  @override
  String get displayName => 'Cancelamentos de venda';

  @override
  Future<void> ensureSyncAllowed() async {
    if (_dataAccessPolicy.allowRemoteWrite &&
        _operationalContext.canUseCloudWrites) {
      await _remoteDatasource.canReachRemote();
      return;
    }

    if (!_dataAccessPolicy.allowRemoteWrite) {
      throw const ValidationException(
        'Ative o modo hibrido pronto para sincronizar os cancelamentos de venda.',
      );
    }

    if (!_operationalContext.session.isRemoteAuthenticated ||
        _operationalContext.currentRemoteCompanyId == null) {
      throw const AuthenticationException(
        'Faca login remoto antes de sincronizar os cancelamentos de venda.',
      );
    }

    final licenseRestriction = _operationalContext.cloudSyncRestrictionReason;
    if (licenseRestriction != null) {
      throw ValidationException(licenseRestriction);
    }
  }

  @override
  Future<SyncFeatureProcessResult> processQueueItem(SyncQueueItem item) async {
    final sale = await _localRepository.findSaleCancellationForSync(
      item.localEntityId,
    );
    if (sale == null) {
      return const SyncFeatureProcessResult.synced();
    }

    final saleRemoteId = sale.saleRemoteId;
    if (saleRemoteId == null || saleRemoteId.isEmpty) {
      return const SyncFeatureProcessResult.blocked(
        reason:
            'Cancelamento aguardando a venda correspondente receber remoteId.',
      );
    }

    final conflict = await _detectConflict(sale);
    if (conflict != null) {
      await _localRepository.markCancellationConflict(
        sale: sale,
        message: conflict.reason,
        detectedAt: DateTime.now(),
      );
      return SyncFeatureProcessResult.conflict(conflict: conflict);
    }

    final remote = await _remoteDatasource.cancel(
      remoteSaleId: saleRemoteId,
      localUuid: sale.saleUuid,
      canceledAt: sale.canceledAt,
    );

    if (remote.status != 'canceled') {
      throw const ValidationException(
        'A API nao confirmou o cancelamento remoto da venda.',
      );
    }

    await _localRepository.markCancellationSynced(
      sale: sale,
      remoteId: remote.remoteId,
      syncedAt: DateTime.now(),
    );
    return SyncFeatureProcessResult.synced(remoteId: remote.remoteId);
  }

  @override
  Future<int> pullRemoteSnapshot() async {
    return 0;
  }

  Future<SyncConflictInfo?> _detectConflict(
    SaleCancellationSyncPayload sale,
  ) async {
    final lastSyncedAt = sale.lastSyncedAt;
    if (lastSyncedAt == null || sale.saleRemoteId == null) {
      return null;
    }

    final remote = await _remoteDatasource.fetchById(sale.saleRemoteId!);
    if (remote.status == 'canceled') {
      return null;
    }

    if (remote.updatedAt.isAfter(lastSyncedAt) &&
        sale.updatedAt.isAfter(lastSyncedAt)) {
      return SyncConflictInfo(
        reason:
            'A venda foi alterada remotamente depois do ultimo sync e o cancelamento local exige revisao.',
        localUpdatedAt: sale.updatedAt,
        remoteUpdatedAt: remote.updatedAt,
      );
    }

    return null;
  }
}
