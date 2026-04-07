import '../../../app/core/app_context/app_operational_context.dart';
import '../../../app/core/app_context/data_access_policy.dart';
import '../../../app/core/errors/app_exceptions.dart';
import '../../../app/core/sync/sync_conflict_info.dart';
import '../../../app/core/sync/sync_feature_processor.dart';
import '../../../app/core/sync/sync_queue_item.dart';
import 'datasources/fiado_remote_datasource.dart';
import 'models/fiado_payment_sync_payload.dart';
import 'models/remote_fiado_payment_record.dart';
import 'sqlite_fiado_repository.dart';

class FiadoPaymentSyncProcessor implements SyncFeatureProcessor {
  const FiadoPaymentSyncProcessor({
    required SqliteFiadoRepository localRepository,
    required FiadoRemoteDatasource remoteDatasource,
    required AppOperationalContext operationalContext,
    required DataAccessPolicy dataAccessPolicy,
  }) : _localRepository = localRepository,
       _remoteDatasource = remoteDatasource,
       _operationalContext = operationalContext,
       _dataAccessPolicy = dataAccessPolicy;

  final SqliteFiadoRepository _localRepository;
  final FiadoRemoteDatasource _remoteDatasource;
  final AppOperationalContext _operationalContext;
  final DataAccessPolicy _dataAccessPolicy;

  @override
  String get featureKey => SqliteFiadoRepository.paymentFeatureKey;

  @override
  String get displayName => 'Pagamentos de fiado';

  @override
  Future<void> ensureSyncAllowed() async {
    if (_dataAccessPolicy.allowRemoteWrite &&
        _operationalContext.canUseCloudWrites) {
      await _remoteDatasource.canReachRemote();
      return;
    }

    if (!_dataAccessPolicy.allowRemoteWrite) {
      throw const ValidationException(
        'Ative o modo hibrido pronto para sincronizar os pagamentos de fiado.',
      );
    }

    if (!_operationalContext.session.isRemoteAuthenticated ||
        _operationalContext.currentRemoteCompanyId == null) {
      throw const AuthenticationException(
        'Faca login remoto antes de sincronizar os pagamentos de fiado.',
      );
    }

    final licenseRestriction = _operationalContext.cloudSyncRestrictionReason;
    if (licenseRestriction != null) {
      throw ValidationException(licenseRestriction);
    }
  }

  @override
  Future<SyncFeatureProcessResult> processQueueItem(SyncQueueItem item) async {
    final payment = await _localRepository.findPaymentForSync(
      item.localEntityId,
    );
    if (payment == null) {
      return const SyncFeatureProcessResult.synced();
    }

    if (payment.saleRemoteId == null) {
      return const SyncFeatureProcessResult.blocked(
        reason: 'Pagamento aguardando a venda receber remoteId.',
      );
    }

    final remote = await _remoteDatasource.createPayment(
      RemoteFiadoPaymentRecord.fromSyncPayload(payment),
    );

    if (!_matches(payment, remote)) {
      return SyncFeatureProcessResult.conflict(
        conflict: SyncConflictInfo(
          reason:
              'O pagamento remoto retornado divergiu do evento local de fiado.',
          localUpdatedAt: payment.updatedAt,
          remoteUpdatedAt: remote.updatedAt,
        ),
      );
    }

    await _localRepository.markPaymentSynced(
      payment: payment,
      remoteId: remote.remoteId,
      syncedAt: DateTime.now(),
    );
    return SyncFeatureProcessResult.synced(remoteId: remote.remoteId);
  }

  @override
  Future<int> pullRemoteSnapshot() async {
    return 0;
  }

  bool _matches(
    FiadoPaymentSyncPayload local,
    RemoteFiadoPaymentRecord remote,
  ) {
    return remote.remoteSaleId == local.saleRemoteId &&
        remote.amountCents == local.amountCents &&
        remote.paymentMethod == local.paymentMethod;
  }
}
