import '../../../app/core/app_context/app_operational_context.dart';
import '../../../app/core/app_context/data_access_policy.dart';
import '../../../app/core/errors/app_exceptions.dart';
import '../../../app/core/sync/sync_conflict_info.dart';
import '../../../app/core/sync/sync_feature_processor.dart';
import '../../../app/core/sync/sync_queue_item.dart';
import 'datasources/cash_remote_datasource.dart';
import 'models/cash_event_sync_payload.dart';
import 'models/remote_cash_event_record.dart';
import 'sqlite_cash_repository.dart';

class CashEventSyncProcessor implements SyncFeatureProcessor {
  const CashEventSyncProcessor({
    required SqliteCashRepository localRepository,
    required CashRemoteDatasource remoteDatasource,
    required AppOperationalContext operationalContext,
    required DataAccessPolicy dataAccessPolicy,
  }) : _localRepository = localRepository,
       _remoteDatasource = remoteDatasource,
       _operationalContext = operationalContext,
       _dataAccessPolicy = dataAccessPolicy;

  final SqliteCashRepository _localRepository;
  final CashRemoteDatasource _remoteDatasource;
  final AppOperationalContext _operationalContext;
  final DataAccessPolicy _dataAccessPolicy;

  @override
  String get featureKey => SqliteCashRepository.cashEventFeatureKey;

  @override
  String get displayName => 'Eventos de caixa';

  @override
  Future<void> ensureSyncAllowed() async {
    if (_dataAccessPolicy.allowRemoteWrite &&
        _operationalContext.canUseCloudWrites) {
      await _remoteDatasource.canReachRemote();
      return;
    }

    if (!_dataAccessPolicy.allowRemoteWrite) {
      throw const ValidationException(
        'Ative o modo hibrido pronto para sincronizar os eventos de caixa.',
      );
    }

    if (!_operationalContext.session.isRemoteAuthenticated ||
        _operationalContext.currentRemoteCompanyId == null) {
      throw const AuthenticationException(
        'Faca login remoto antes de sincronizar os eventos de caixa.',
      );
    }

    final licenseRestriction = _operationalContext.cloudSyncRestrictionReason;
    if (licenseRestriction != null) {
      throw ValidationException(licenseRestriction);
    }
  }

  @override
  Future<SyncFeatureProcessResult> processQueueItem(SyncQueueItem item) async {
    final event = await _localRepository.findCashEventForSync(
      item.localEntityId,
    );
    if (event == null) {
      return const SyncFeatureProcessResult.synced();
    }

    final requiresReference = _requiresReference(event);
    if (requiresReference && event.referenceRemoteId == null) {
      return const SyncFeatureProcessResult.blocked(
        reason: 'Evento de caixa aguardando a operacao remota de origem.',
      );
    }

    final remote = await _remoteDatasource.createEvent(
      RemoteCashEventRecord.fromSyncPayload(event),
    );

    if (!_matches(event, remote)) {
      return SyncFeatureProcessResult.conflict(
        conflict: SyncConflictInfo(
          reason:
              'O evento de caixa remoto retornado divergiu do evento local.',
          localUpdatedAt: event.updatedAt,
          remoteUpdatedAt: remote.updatedAt,
        ),
      );
    }

    await _localRepository.markCashEventSynced(
      event: event,
      remoteId: remote.remoteId,
      syncedAt: DateTime.now(),
    );
    return SyncFeatureProcessResult.synced(remoteId: remote.remoteId);
  }

  @override
  Future<int> pullRemoteSnapshot() async {
    return 0;
  }

  bool _requiresReference(CashEventSyncPayload event) {
    return event.referenceType == 'venda' || event.referenceType == 'fiado';
  }

  bool _matches(CashEventSyncPayload local, RemoteCashEventRecord remote) {
    final expectedType = RemoteCashEventRecord.fromSyncPayload(local).eventType;
    return remote.eventType == expectedType &&
        remote.amountCents == local.amountCents.abs() &&
        remote.referenceId == local.referenceRemoteId;
  }
}
