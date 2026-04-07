import '../../../modules/fiado/data/models/fiado_payment_sync_payload.dart';
import '../../../modules/fiado/data/sqlite_fiado_repository.dart';
import '../../../modules/vendas/data/datasources/sales_remote_datasource.dart';
import '../../../modules/vendas/data/models/sale_cancellation_sync_payload.dart';
import '../../../modules/vendas/data/sqlite_sale_repository.dart';
import '../../../modules/vendas/domain/entities/sale_enums.dart';
import '../app_context/app_operational_context.dart';
import '../app_context/data_access_policy.dart';
import '../errors/app_exceptions.dart';
import 'financial_events_remote_datasource.dart';
import 'remote_financial_event_record.dart';
import 'sync_conflict_info.dart';
import 'sync_feature_keys.dart';
import 'sync_feature_processor.dart';
import 'sync_queue_item.dart';

class FinancialEventSyncProcessor implements SyncFeatureProcessor {
  const FinancialEventSyncProcessor({
    required SqliteSaleRepository saleRepository,
    required SqliteFiadoRepository fiadoRepository,
    required SalesRemoteDatasource salesRemoteDatasource,
    required FinancialEventsRemoteDatasource financialEventsRemoteDatasource,
    required AppOperationalContext operationalContext,
    required DataAccessPolicy dataAccessPolicy,
  }) : _saleRepository = saleRepository,
       _fiadoRepository = fiadoRepository,
       _salesRemoteDatasource = salesRemoteDatasource,
       _financialEventsRemoteDatasource = financialEventsRemoteDatasource,
       _operationalContext = operationalContext,
       _dataAccessPolicy = dataAccessPolicy;

  final SqliteSaleRepository _saleRepository;
  final SqliteFiadoRepository _fiadoRepository;
  final SalesRemoteDatasource _salesRemoteDatasource;
  final FinancialEventsRemoteDatasource _financialEventsRemoteDatasource;
  final AppOperationalContext _operationalContext;
  final DataAccessPolicy _dataAccessPolicy;

  @override
  String get featureKey => SyncFeatureKeys.financialEvents;

  @override
  String get displayName => 'Eventos financeiros';

  @override
  Future<void> ensureSyncAllowed() async {
    if (_dataAccessPolicy.allowRemoteWrite &&
        _operationalContext.canUseCloudWrites) {
      await _financialEventsRemoteDatasource.canReachRemote();
      return;
    }

    if (!_dataAccessPolicy.allowRemoteWrite) {
      throw const ValidationException(
        'Ative o modo hibrido pronto para sincronizar os eventos financeiros.',
      );
    }

    if (!_operationalContext.session.isRemoteAuthenticated ||
        _operationalContext.currentRemoteCompanyId == null) {
      throw const AuthenticationException(
        'Faca login remoto antes de sincronizar os eventos financeiros.',
      );
    }

    final licenseRestriction = _operationalContext.cloudSyncRestrictionReason;
    if (licenseRestriction != null) {
      throw ValidationException(licenseRestriction);
    }
  }

  @override
  Future<SyncFeatureProcessResult> processQueueItem(SyncQueueItem item) async {
    switch (item.entityType) {
      case 'sale_canceled_event':
        return _processSaleCanceled(item);
      case 'fiado_payment_event':
        return _processFiadoPayment(item);
      default:
        return const SyncFeatureProcessResult.synced();
    }
  }

  @override
  Future<int> pullRemoteSnapshot() async {
    return 0;
  }

  Future<SyncFeatureProcessResult> _processSaleCanceled(
    SyncQueueItem item,
  ) async {
    final sale = await _saleRepository.findSaleCancellationForSync(
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

    final canceledSale = await _salesRemoteDatasource.cancel(
      remoteSaleId: saleRemoteId,
      localUuid: sale.saleUuid,
      canceledAt: sale.canceledAt,
    );
    if (canceledSale.status != 'canceled') {
      throw const ValidationException(
        'A API nao confirmou o cancelamento remoto da venda.',
      );
    }

    final remote = await _createFinancialEvent(
      RemoteFinancialEventRecord(
        remoteId: sale.remoteId ?? '',
        companyId: _operationalContext.currentRemoteCompanyId ?? '',
        saleId: saleRemoteId,
        fiadoId: null,
        eventType: 'sale_canceled',
        localUuid: sale.saleUuid,
        amountCents: sale.amountCents,
        paymentType: sale.paymentType,
        createdAt: sale.canceledAt,
        updatedAt: sale.updatedAt,
        metadata: <String, dynamic>{
          'saleLocalId': sale.saleId,
          if (sale.notes != null && sale.notes!.trim().isNotEmpty)
            'notes': sale.notes!.trim(),
        },
      ),
    );

    if (remote == null) {
      final conflict = SyncConflictInfo(
        reason:
            'Ja existe um evento remoto divergente para este cancelamento de venda.',
        localUpdatedAt: sale.updatedAt,
        remoteUpdatedAt: DateTime.now(),
      );
      await _saleRepository.markCancellationConflict(
        sale: sale,
        message: conflict.reason,
        detectedAt: DateTime.now(),
      );
      return SyncFeatureProcessResult.conflict(conflict: conflict);
    }

    if (!_matchesSaleCancellation(sale, remote)) {
      final conflict = SyncConflictInfo(
        reason:
            'O evento remoto de cancelamento divergiu do cancelamento local da venda.',
        localUpdatedAt: sale.updatedAt,
        remoteUpdatedAt: remote.updatedAt,
      );
      await _saleRepository.markCancellationConflict(
        sale: sale,
        message: conflict.reason,
        detectedAt: DateTime.now(),
      );
      return SyncFeatureProcessResult.conflict(conflict: conflict);
    }

    await _saleRepository.markCancellationSynced(
      sale: sale,
      remoteId: remote.remoteId,
      syncedAt: DateTime.now(),
    );
    return SyncFeatureProcessResult.synced(remoteId: remote.remoteId);
  }

  Future<SyncFeatureProcessResult> _processFiadoPayment(
    SyncQueueItem item,
  ) async {
    final payment = await _fiadoRepository.findPaymentForSync(
      item.localEntityId,
    );
    if (payment == null) {
      return const SyncFeatureProcessResult.synced();
    }

    final saleRemoteId = payment.saleRemoteId;
    if (saleRemoteId == null || saleRemoteId.isEmpty) {
      return const SyncFeatureProcessResult.blocked(
        reason: 'Pagamento aguardando a venda correspondente receber remoteId.',
      );
    }

    final remote = await _createFinancialEvent(
      RemoteFinancialEventRecord(
        remoteId: payment.remoteId ?? '',
        companyId: _operationalContext.currentRemoteCompanyId ?? '',
        saleId: saleRemoteId,
        fiadoId: payment.fiadoUuid,
        eventType: 'fiado_payment',
        localUuid: payment.entryUuid,
        amountCents: payment.amountCents,
        paymentType: payment.paymentMethod.dbValue,
        createdAt: payment.createdAt,
        updatedAt: payment.updatedAt,
        metadata: <String, dynamic>{
          'fiadoLocalId': payment.fiadoId,
          'paymentEntryLocalId': payment.entryId,
          if (payment.notes != null && payment.notes!.trim().isNotEmpty)
            'notes': payment.notes!.trim(),
        },
      ),
    );

    if (remote == null) {
      final conflict = SyncConflictInfo(
        reason:
            'Ja existe um evento remoto divergente para este pagamento de fiado.',
        localUpdatedAt: payment.updatedAt,
        remoteUpdatedAt: DateTime.now(),
      );
      await _fiadoRepository.markPaymentConflict(
        payment: payment,
        message: conflict.reason,
        detectedAt: DateTime.now(),
      );
      return SyncFeatureProcessResult.conflict(conflict: conflict);
    }

    if (!_matchesFiadoPayment(payment, remote)) {
      final conflict = SyncConflictInfo(
        reason: 'O evento remoto de pagamento divergiu do pagamento local.',
        localUpdatedAt: payment.updatedAt,
        remoteUpdatedAt: remote.updatedAt,
      );
      await _fiadoRepository.markPaymentConflict(
        payment: payment,
        message: conflict.reason,
        detectedAt: DateTime.now(),
      );
      return SyncFeatureProcessResult.conflict(conflict: conflict);
    }

    await _fiadoRepository.markPaymentSynced(
      payment: payment,
      remoteId: remote.remoteId,
      syncedAt: DateTime.now(),
    );
    return SyncFeatureProcessResult.synced(remoteId: remote.remoteId);
  }

  bool _matchesSaleCancellation(
    SaleCancellationSyncPayload local,
    RemoteFinancialEventRecord remote,
  ) {
    return remote.eventType == 'sale_canceled' &&
        remote.saleId == local.saleRemoteId &&
        remote.amountCents == local.amountCents &&
        remote.paymentType == local.paymentType;
  }

  bool _matchesFiadoPayment(
    FiadoPaymentSyncPayload local,
    RemoteFinancialEventRecord remote,
  ) {
    return remote.eventType == 'fiado_payment' &&
        remote.saleId == local.saleRemoteId &&
        remote.fiadoId == local.fiadoUuid &&
        remote.amountCents == local.amountCents &&
        remote.paymentType == local.paymentMethod.dbValue;
  }

  Future<RemoteFinancialEventRecord?> _createFinancialEvent(
    RemoteFinancialEventRecord record,
  ) async {
    try {
      return await _financialEventsRemoteDatasource.create(record);
    } on NetworkRequestException catch (error) {
      final statusCode = error.cause is int ? error.cause! as int : null;
      if (statusCode == 409) {
        return null;
      }
      rethrow;
    }
  }
}
