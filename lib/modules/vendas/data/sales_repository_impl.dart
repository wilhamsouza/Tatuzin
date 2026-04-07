import '../../../app/core/app_context/app_operational_context.dart';
import '../../../app/core/app_context/data_access_policy.dart';
import '../../../app/core/errors/app_exceptions.dart';
import '../../../app/core/sync/sync_conflict_info.dart';
import '../../../app/core/sync/sync_feature_processor.dart';
import '../../../app/core/sync/sync_queue_item.dart';
import '../domain/entities/checkout_input.dart';
import '../domain/entities/completed_sale.dart';
import '../domain/repositories/sale_repository.dart';
import 'datasources/sales_remote_datasource.dart';
import 'models/remote_sale_record.dart';
import 'models/sale_sync_payload.dart';
import 'sqlite_sale_repository.dart';

class SalesRepositoryImpl implements SaleRepository, SyncFeatureProcessor {
  const SalesRepositoryImpl({
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
  String get featureKey => SqliteSaleRepository.featureKey;

  @override
  String get displayName => 'Vendas';

  @override
  Future<void> cancelSale({required int saleId, required String reason}) async {
    await _localRepository.cancelSale(saleId: saleId, reason: reason);
  }

  @override
  Future<CompletedSale> completeCashSale({required CheckoutInput input}) async {
    return _localRepository.completeCashSale(input: input);
  }

  @override
  Future<CompletedSale> completeCreditSale({
    required CheckoutInput input,
  }) async {
    return _localRepository.completeCreditSale(input: input);
  }

  @override
  Future<void> ensureSyncAllowed() async {
    if (_dataAccessPolicy.allowRemoteWrite &&
        _operationalContext.canUseCloudWrites) {
      await _remoteDatasource.canReachRemote();
      return;
    }

    if (!_dataAccessPolicy.allowRemoteWrite) {
      throw const ValidationException(
        'Ative o modo hibrido pronto para sincronizar as vendas.',
      );
    }

    if (!_operationalContext.session.isRemoteAuthenticated ||
        _operationalContext.currentRemoteCompanyId == null) {
      throw const AuthenticationException(
        'Faca login remoto antes de sincronizar as vendas.',
      );
    }

    final licenseRestriction = _operationalContext.cloudSyncRestrictionReason;
    if (licenseRestriction != null) {
      throw ValidationException(licenseRestriction);
    }
  }

  @override
  Future<SyncFeatureProcessResult> processQueueItem(SyncQueueItem item) async {
    final sale = await _localRepository.findSaleForSync(item.localEntityId);
    if (sale == null) {
      return const SyncFeatureProcessResult.synced();
    }

    if (sale.status.name == 'cancelled') {
      return const SyncFeatureProcessResult.blocked(
        reason: 'Cancelamento remoto de venda ainda nao esta habilitado.',
      );
    }

    final conflict = await _detectConflict(sale);
    if (conflict != null) {
      await _localRepository.markConflict(
        sale: sale,
        message: conflict.reason,
        detectedAt: DateTime.now(),
      );
      return SyncFeatureProcessResult.conflict(conflict: conflict);
    }

    final remoteRecord = RemoteSaleRecord.fromSyncPayload(sale);
    final persisted = await _remoteDatasource.create(remoteRecord);
    await _localRepository.markSynced(
      sale: sale,
      remoteId: persisted.remoteId,
      syncedAt: DateTime.now(),
    );
    return SyncFeatureProcessResult.synced(remoteId: persisted.remoteId);
  }

  @override
  Future<int> pullRemoteSnapshot() async {
    return 0;
  }

  Future<SyncConflictInfo?> _detectConflict(SaleSyncPayload sale) async {
    final lastSyncedAt = sale.lastSyncedAt;
    final remoteId = sale.remoteId;
    if (lastSyncedAt == null || remoteId == null) {
      return null;
    }

    final remote = await _remoteDatasource.fetchById(remoteId);
    final remoteIsNewer = remote.updatedAt.isAfter(lastSyncedAt);
    final localChangedSinceSync = sale.updatedAt.isAfter(lastSyncedAt);
    if (!remoteIsNewer || !localChangedSinceSync) {
      return null;
    }

    return SyncConflictInfo(
      reason:
          'Venda divergiu entre o app local e o backend desde o ultimo sync.',
      localUpdatedAt: sale.updatedAt,
      remoteUpdatedAt: remote.updatedAt,
    );
  }
}
