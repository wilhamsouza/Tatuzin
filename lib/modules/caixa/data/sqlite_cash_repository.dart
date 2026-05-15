import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../app/core/app_context/app_operational_context.dart';
import '../../../app/core/app_context/record_identity.dart';
import '../../../app/core/database/app_database.dart';
import '../../../app/core/database/table_names.dart';
import '../../../app/core/errors/app_exceptions.dart';
import '../../../app/core/sync/operational_sync_event.dart';
import '../../../app/core/sync/sqlite_sync_metadata_repository.dart';
import '../../../app/core/sync/sqlite_operational_sync_queue_repository.dart';
import '../../../app/core/sync/sqlite_sync_queue_repository.dart';
import '../../../app/core/sync/sync_feature_keys.dart';
import '../../../app/core/sync/sync_queue_operation.dart';
import '../../../app/core/sync/sync_status.dart';
import '../../../app/core/utils/id_generator.dart';
import '../../../app/core/utils/payment_method_note_codec.dart';
import '../../vendas/domain/entities/sale_enums.dart';
import '../../vendas/domain/entities/sale_record.dart';
import '../domain/entities/cash_enums.dart';
import '../domain/entities/cash_manual_movement_input.dart';
import '../domain/entities/cash_movement.dart';
import '../domain/entities/cash_session.dart';
import '../domain/entities/cash_session_detail.dart';
import '../domain/repositories/cash_repository.dart';
import 'cash_database_support.dart';
import 'models/cash_event_sync_payload.dart';
import 'models/remote_cash_movement_record.dart';
import 'models/remote_cash_session_record.dart';

class SqliteCashRepository implements CashRepository {
  SqliteCashRepository(this._appDatabase, this._operationalContext)
    : _syncMetadataRepository = SqliteSyncMetadataRepository(_appDatabase),
      _operationalSyncQueueRepository = SqliteOperationalSyncQueueRepository(
        _appDatabase,
      ),
      _syncQueueRepository = SqliteSyncQueueRepository(_appDatabase);

  static const String cashEventFeatureKey = SyncFeatureKeys.cashEvents;
  static const String cashSessionFeatureKey = SyncFeatureKeys.cashSessions;
  static const String _sessionMetadataPrefix = '__cash_session_meta__:';
  static const String _autoOpenedNote =
      'Sessão aberta automaticamente para registrar movimento financeiro.';

  final AppDatabase _appDatabase;
  final AppOperationalContext _operationalContext;
  final SqliteSyncMetadataRepository _syncMetadataRepository;
  final SqliteOperationalSyncQueueRepository _operationalSyncQueueRepository;
  final SqliteSyncQueueRepository _syncQueueRepository;

  @override
  Future<CashSession?> getCurrentSession() async {
    final database = await _appDatabase.database;
    final row = await CashDatabaseSupport.getOpenSessionRow(database);
    if (row == null) {
      return null;
    }

    return _mapSession(await _loadSessionRow(database, row['id'] as int));
  }

  @override
  Future<List<CashMovement>> listCurrentSessionMovements() async {
    final database = await _appDatabase.database;
    final sessionId = await _tryGetOpenSessionId(database);
    if (sessionId == null) {
      return const <CashMovement>[];
    }

    final rows = await database.query(
      TableNames.caixaMovimentos,
      where: 'sessao_id = ?',
      whereArgs: [sessionId],
      orderBy: 'criado_em DESC, id DESC',
    );

    return rows.map(_mapMovement).toList();
  }

  @override
  Future<List<CashSession>> listSessions() async {
    final database = await _appDatabase.database;
    final rows = await _loadSessionRows(database);
    return rows.map(_mapSession).toList();
  }

  Future<void> upsertSessionFromRemote(RemoteCashSessionRecord remote) async {
    final database = await _appDatabase.database;
    await database.transaction((txn) async {
      final metadataByRemoteId = await _syncMetadataRepository.findByRemoteId(
        txn,
        featureKey: cashSessionFeatureKey,
        remoteId: remote.remoteId,
      );
      final metadataByLocalUuid = await _syncMetadataRepository.findByLocalUuid(
        txn,
        featureKey: cashSessionFeatureKey,
        localUuid: remote.localUuid,
      );
      final metadata = metadataByRemoteId ?? metadataByLocalUuid;

      Map<String, Object?>? existing;
      if (metadata?.identity.localId != null) {
        existing = await _findSessionRowById(txn, metadata!.identity.localId!);
      }
      existing ??= await _findSessionRowByUuid(txn, remote.localUuid);

      late final int localId;
      final values = <String, Object?>{
        'uuid': remote.localUuid,
        'usuario_id': null,
        'aberta_em': remote.openedAt.toIso8601String(),
        'fechada_em': remote.closedAt?.toIso8601String(),
        'troco_inicial_centavos': remote.initialFloatCents,
        'aguardando_confirmacao_troco_inicial': 0,
        'total_entradas_dinheiro_centavos': 0,
        'total_suprimentos_centavos': 0,
        'total_sangrias_centavos': 0,
        'total_vendas_centavos': 0,
        'total_recebimentos_fiado_centavos': 0,
        'total_recebimentos_fiado_dinheiro_centavos': 0,
        'total_recebimentos_fiado_pix_centavos': 0,
        'total_recebimentos_fiado_cartao_centavos': 0,
        'saldo_esperado_centavos':
            remote.expectedBalanceCents ?? remote.initialFloatCents,
        'saldo_contado_centavos': remote.countedBalanceCents,
        'diferenca_centavos':
            remote.countedBalanceCents == null ||
                remote.expectedBalanceCents == null
            ? null
            : remote.countedBalanceCents! - remote.expectedBalanceCents!,
        'saldo_final_centavos':
            remote.expectedBalanceCents ?? remote.initialFloatCents,
        'status': remote.status == 'closed'
            ? CashSessionStatus.closed.dbValue
            : CashSessionStatus.open.dbValue,
        'observacao': _encodeSessionNotes(
          visibleNotes: remote.notes,
          operatorName: remote.operatorName,
        ),
      };

      if (existing == null) {
        localId = await txn.insert(TableNames.caixaSessoes, values);
      } else {
        localId = existing['id'] as int;
        await txn.update(
          TableNames.caixaSessoes,
          values,
          where: 'id = ?',
          whereArgs: [localId],
        );
      }

      await _syncMetadataRepository.markSynced(
        txn,
        featureKey: cashSessionFeatureKey,
        localId: localId,
        localUuid: remote.localUuid,
        remoteId: remote.remoteId,
        origin: existing == null ? RecordOrigin.remote : RecordOrigin.merged,
        createdAt: remote.createdAt,
        updatedAt: remote.updatedAt,
        syncedAt: DateTime.now(),
      );
    });
  }

  Future<void> upsertMovementFromRemote(RemoteCashMovementRecord remote) async {
    if (remote.remoteCashSessionId == null ||
        remote.remoteCashSessionId!.trim().isEmpty) {
      return;
    }

    final database = await _appDatabase.database;
    await database.transaction((txn) async {
      final sessionMetadata = await _syncMetadataRepository.findByRemoteId(
        txn,
        featureKey: cashSessionFeatureKey,
        remoteId: remote.remoteCashSessionId!,
      );
      final sessionId = sessionMetadata?.identity.localId;
      if (sessionId == null) {
        return;
      }

      final metadataByRemoteId = await _syncMetadataRepository.findByRemoteId(
        txn,
        featureKey: cashEventFeatureKey,
        remoteId: remote.remoteId,
      );
      final metadataByLocalUuid = await _syncMetadataRepository.findByLocalUuid(
        txn,
        featureKey: cashEventFeatureKey,
        localUuid: remote.localUuid,
      );
      final metadata = metadataByRemoteId ?? metadataByLocalUuid;

      Map<String, Object?>? existing;
      if (metadata?.identity.localId != null) {
        existing = await _findMovementRowById(txn, metadata!.identity.localId!);
      }
      existing ??= await _findMovementRowByUuid(txn, remote.localUuid);

      late final int localId;
      final referenceId = await _resolveRemoteMovementReferenceId(
        txn,
        referenceType: remote.referenceType,
        referenceId: remote.referenceId,
      );
      final values = <String, Object?>{
        'uuid': remote.localUuid,
        'sessao_id': sessionId,
        'tipo_movimento': CashMovementTypeX.fromDb(remote.type).dbValue,
        'referencia_tipo': remote.referenceType,
        'referencia_id': referenceId,
        'valor_centavos': remote.amountCents,
        'descricao': PaymentMethodNoteCodec.withPaymentMethod(
          remote.notes ?? '',
          paymentMethod: remote.paymentMethod,
        ),
        'criado_em': remote.createdAt.toIso8601String(),
      };

      if (existing == null) {
        localId = await txn.insert(TableNames.caixaMovimentos, values);
      } else {
        localId = existing['id'] as int;
        await txn.update(
          TableNames.caixaMovimentos,
          values,
          where: 'id = ?',
          whereArgs: [localId],
        );
      }

      await CashSessionMathSupport.rebuildSessionTotals(
        txn,
        sessionId: sessionId,
      );
      await _syncMetadataRepository.markSynced(
        txn,
        featureKey: cashEventFeatureKey,
        localId: localId,
        localUuid: remote.localUuid,
        remoteId: remote.remoteId,
        origin: existing == null ? RecordOrigin.remote : RecordOrigin.merged,
        createdAt: remote.createdAt,
        updatedAt: remote.updatedAt,
        syncedAt: DateTime.now(),
      );
    });
  }

  @override
  Future<CashSessionDetail> fetchSessionDetail(int sessionId) async {
    final database = await _appDatabase.database;
    final session = _mapSession(await _loadSessionRow(database, sessionId));
    final periodEnd = session.closedAt ?? DateTime.now();
    final movements = await _loadSessionMovementDetails(database, sessionId);
    final sales = await _loadSessionSales(
      database,
      openedAt: session.openedAt,
      periodEnd: periodEnd,
    );

    final totalEntriesCents = movements.fold<int>(
      0,
      (sum, item) =>
          item.movement.amountCents > 0 ? sum + item.movement.amountCents : sum,
    );
    final totalOutflowsCents = movements.fold<int>(
      0,
      (sum, item) => item.movement.amountCents < 0
          ? sum + item.movement.amountCents.abs()
          : sum,
    );
    final totalSoldCents = sales.fold<int>(
      0,
      (sum, item) => item.sale.status == SaleStatus.cancelled
          ? sum
          : sum + item.sale.finalCents,
    );

    return CashSessionDetail(
      session: session,
      periodEnd: periodEnd,
      movements: movements,
      sales: sales,
      totalSoldCents: totalSoldCents,
      totalEntriesCents: totalEntriesCents,
      totalOutflowsCents: totalOutflowsCents,
      totalCashSalesReceivedCents: session.totalSalesCents,
      totalFiadoReceiptsCashCents: session.fiadoReceiptsCashCents,
      totalFiadoReceiptsPixCents: session.fiadoReceiptsPixCents,
      totalFiadoReceiptsCardCents: session.fiadoReceiptsCardCents,
      totalManualEntriesCents: session.totalSuppliesCents,
      totalManualWithdrawalsCents: session.totalWithdrawalsCents,
      countedAmountCents: session.countedBalanceCents,
      reportedBalanceCents: session.expectedBalanceCents,
      differenceCents: session.differenceCents,
    );
  }

  @override
  Future<CashSession> openSession({
    required int initialFloatCents,
    String? notes,
  }) async {
    final database = await _appDatabase.database;

    return database.transaction<CashSession>((txn) async {
      final existingOpen = await CashDatabaseSupport.getOpenSessionRow(txn);
      if (existingOpen != null) {
        throw const ValidationException(
          'Ja existe um caixa aberto. Feche a sessao atual antes de abrir outra.',
        );
      }

      final now = DateTime.now();
      final sessionUuid = IdGenerator.next();
      final sessionId = await txn.insert(TableNames.caixaSessoes, {
        'uuid': sessionUuid,
        'usuario_id': _operationalContext.currentLocalUserId,
        'aberta_em': now.toIso8601String(),
        'fechada_em': null,
        'troco_inicial_centavos': initialFloatCents,
        'aguardando_confirmacao_troco_inicial': 0,
        'total_entradas_dinheiro_centavos': 0,
        'total_suprimentos_centavos': 0,
        'total_sangrias_centavos': 0,
        'total_vendas_centavos': 0,
        'total_recebimentos_fiado_centavos': 0,
        'total_recebimentos_fiado_dinheiro_centavos': 0,
        'total_recebimentos_fiado_pix_centavos': 0,
        'total_recebimentos_fiado_cartao_centavos': 0,
        'saldo_esperado_centavos': initialFloatCents,
        'saldo_contado_centavos': null,
        'diferenca_centavos': null,
        'saldo_final_centavos': initialFloatCents,
        'status': CashSessionStatus.open.dbValue,
        'observacao': _cleanNullable(notes),
      });

      final session = _mapSession(await _loadSessionRow(txn, sessionId));
      await _enqueueCashSessionEvent(
        txn,
        session,
        operation: 'create',
        occurredAt: now,
      );
      return session;
    });
  }

  @override
  Future<CashSession> confirmAutoOpenedSession({
    required int initialFloatCents,
  }) async {
    final database = await _appDatabase.database;

    return database.transaction<CashSession>((txn) async {
      final row = await CashDatabaseSupport.getOpenSessionRow(txn);
      if (row == null) {
        throw const ValidationException(
          'Nao existe um caixa aberto aguardando confirmacao.',
        );
      }

      final sessionId = row['id'] as int;
      final updatedNotes = _removeAutomaticOpeningNote(
        row['observacao'] as String?,
      );
      final expectedBalance = CashSessionMathSupport.calculateExpectedBalance(
        initialFloatCents: initialFloatCents,
        cashEntriesCents: row['total_entradas_dinheiro_centavos'] as int? ?? 0,
        fiadoReceiptsCashCents:
            row['total_recebimentos_fiado_dinheiro_centavos'] as int? ?? 0,
        suppliesCents: row['total_suprimentos_centavos'] as int? ?? 0,
        withdrawalsCents: row['total_sangrias_centavos'] as int? ?? 0,
      );

      await txn.update(
        TableNames.caixaSessoes,
        {
          'troco_inicial_centavos': initialFloatCents,
          'aguardando_confirmacao_troco_inicial': 0,
          'saldo_esperado_centavos': expectedBalance,
          'saldo_final_centavos': expectedBalance,
          'observacao': updatedNotes,
        },
        where: 'id = ?',
        whereArgs: [sessionId],
      );

      final session = _mapSession(await _loadSessionRow(txn, sessionId));
      await _enqueueCashSessionEvent(
        txn,
        session,
        operation: 'update',
        occurredAt: DateTime.now(),
      );
      return session;
    });
  }

  @override
  Future<CashSession> closeSession({
    required int countedBalanceCents,
    String? notes,
  }) async {
    final database = await _appDatabase.database;

    return database.transaction<CashSession>((txn) async {
      final row = await CashDatabaseSupport.getOpenSessionRow(txn);
      if (row == null) {
        throw const ValidationException(
          'Nao existe um caixa aberto para fechar.',
        );
      }

      final sessionId = row['id'] as int;
      final expectedBalance =
          row['saldo_esperado_centavos'] as int? ??
          row['saldo_final_centavos'] as int? ??
          0;
      final differenceCents = countedBalanceCents - expectedBalance;
      final closedAt = DateTime.now().toIso8601String();
      final updatedNotes = _mergeNotes(row['observacao'] as String?, notes);

      await txn.update(
        TableNames.caixaSessoes,
        {
          'fechada_em': closedAt,
          'aguardando_confirmacao_troco_inicial': 0,
          'saldo_contado_centavos': countedBalanceCents,
          'diferenca_centavos': differenceCents,
          'status': CashSessionStatus.closed.dbValue,
          'observacao': updatedNotes,
        },
        where: 'id = ?',
        whereArgs: [sessionId],
      );

      final session = _mapSession(await _loadSessionRow(txn, sessionId));
      await _enqueueCashSessionEvent(
        txn,
        session,
        operation: 'update',
        occurredAt: DateTime.parse(closedAt),
      );
      return session;
    });
  }

  @override
  Future<void> registerManualMovement(CashManualMovementInput input) async {
    final database = await _appDatabase.database;

    await database.transaction((txn) async {
      final sessionId = await CashDatabaseSupport.requireOpenSessionId(txn);
      final now = DateTime.now();

      switch (input.type) {
        case CashMovementType.supply:
          await CashSessionMathSupport.applySessionDeltas(
            txn,
            sessionId: sessionId,
            suppliesDeltaCents: input.amountCents,
          );
          break;
        case CashMovementType.sangria:
          await CashSessionMathSupport.applySessionDeltas(
            txn,
            sessionId: sessionId,
            withdrawalsDeltaCents: input.amountCents,
          );
          break;
        default:
          throw const ValidationException(
            'Somente suprimentos e sangrias manuais sao suportados nesta etapa.',
          );
      }

      final movement = await CashDatabaseSupport.insertMovement(
        txn,
        sessionId: sessionId,
        type: input.type,
        amountCents: input.type == CashMovementType.sangria
            ? -input.amountCents
            : input.amountCents,
        timestamp: now,
        referenceType: 'manual',
        referenceId: null,
        description: input.description,
      );
      await _registerCashEventForSync(
        txn,
        movementId: movement.id,
        movementUuid: movement.uuid,
        createdAt: now,
      );
      await _enqueueCashMovementEvent(
        txn,
        movementId: movement.id,
        movementUuid: movement.uuid,
        sessionId: sessionId,
        type: input.type.dbValue,
        amountCents: input.type == CashMovementType.sangria
            ? -input.amountCents
            : input.amountCents,
        description: input.description,
        occurredAt: now,
      );
    });
  }

  Future<CashEventSyncPayload?> findCashEventForSync(int movementId) async {
    final database = await _appDatabase.database;
    final rows = await database.rawQuery(
      '''
      SELECT
        mov.id,
        mov.uuid,
        mov.tipo_movimento,
        mov.referencia_tipo,
        mov.referencia_id,
        mov.valor_centavos,
        mov.descricao,
        mov.criado_em,
        event_sync.remote_id AS event_remote_id,
        event_sync.sync_status AS event_sync_status,
        event_sync.last_synced_at AS event_last_synced_at,
        sale_sync.remote_id AS sale_remote_id,
        payment_sync.remote_id AS payment_remote_id
      FROM ${TableNames.caixaMovimentos} mov
      LEFT JOIN ${TableNames.syncRegistros} event_sync
        ON event_sync.feature_key = '$cashEventFeatureKey'
        AND event_sync.local_id = mov.id
      LEFT JOIN ${TableNames.syncRegistros} sale_sync
        ON sale_sync.feature_key = '${SyncFeatureKeys.sales}'
        AND sale_sync.local_id = mov.referencia_id
        AND mov.referencia_tipo = 'venda'
      LEFT JOIN ${TableNames.fiadoLancamentos} fiado_payment
        ON fiado_payment.caixa_movimento_id = mov.id
        AND fiado_payment.tipo_lancamento = 'pagamento'
      LEFT JOIN ${TableNames.syncRegistros} payment_sync
        ON payment_sync.feature_key = '${SyncFeatureKeys.fiadoPayments}'
        AND payment_sync.local_id = fiado_payment.id
      WHERE mov.id = ?
      LIMIT 1
    ''',
      [movementId],
    );

    if (rows.isEmpty) {
      return null;
    }

    final row = rows.first;
    final description = row['descricao'] as String?;
    final referenceType = row['referencia_tipo'] as String?;
    return CashEventSyncPayload(
      movementId: row['id'] as int,
      movementUuid: row['uuid'] as String,
      type: CashMovementTypeX.fromDb(row['tipo_movimento'] as String),
      amountCents: row['valor_centavos'] as int,
      paymentMethod: PaymentMethodNoteCodec.parse(description),
      referenceType: referenceType,
      referenceLocalId: _intFromDb(row['referencia_id']),
      referenceRemoteId: referenceType == 'venda'
          ? row['sale_remote_id'] as String?
          : referenceType == 'fiado'
          ? row['payment_remote_id'] as String?
          : null,
      description: PaymentMethodNoteCodec.clean(description),
      createdAt: DateTime.parse(row['criado_em'] as String),
      updatedAt: DateTime.parse(row['criado_em'] as String),
      remoteId: row['event_remote_id'] as String?,
      syncStatus: syncStatusFromStorage(row['event_sync_status'] as String?),
      lastSyncedAt: row['event_last_synced_at'] == null
          ? null
          : DateTime.parse(row['event_last_synced_at'] as String),
    );
  }

  Future<void> markCashEventSynced({
    required CashEventSyncPayload event,
    required String remoteId,
    required DateTime syncedAt,
  }) async {
    final database = await _appDatabase.database;
    await database.transaction((txn) async {
      await _syncMetadataRepository.markSynced(
        txn,
        featureKey: cashEventFeatureKey,
        localId: event.movementId,
        localUuid: event.movementUuid,
        remoteId: remoteId,
        origin: RecordOrigin.local,
        createdAt: event.createdAt,
        updatedAt: event.updatedAt,
        syncedAt: syncedAt,
      );
    });
  }

  Future<void> _registerCashEventForSync(
    dynamic txn, {
    required int movementId,
    required String movementUuid,
    required DateTime createdAt,
  }) async {
    await _syncMetadataRepository.markPendingUpload(
      txn,
      featureKey: cashEventFeatureKey,
      localId: movementId,
      localUuid: movementUuid,
      createdAt: createdAt,
      updatedAt: createdAt,
    );
    await _syncQueueRepository.enqueueMutation(
      txn,
      featureKey: cashEventFeatureKey,
      entityType: 'cash_event',
      localEntityId: movementId,
      localUuid: movementUuid,
      remoteId: null,
      operation: SyncQueueOperation.create,
      localUpdatedAt: createdAt,
    );
  }

  Future<void> _enqueueCashSessionEvent(
    DatabaseExecutor txn,
    CashSession session, {
    required String operation,
    required DateTime occurredAt,
  }) async {
    final eventIdentity = operation == 'create'
        ? session.uuid
        : '${session.uuid}:${occurredAt.microsecondsSinceEpoch}';
    await _operationalSyncQueueRepository.enqueue(
      txn,
      event: OperationalSyncEvent(
        eventId: OperationalSyncEvent.buildEventId(
          entity: 'cashSession',
          operation: operation,
          localIdentity: eventIdentity,
        ),
        feature: 'pdv',
        entity: 'cashSession',
        operation: operation,
        entityLocalId: session.uuid,
        occurredAt: occurredAt,
        payload: <String, dynamic>{
          'localId': session.id,
          'uuid': session.uuid,
          'operatorName': session.operatorName,
          'openedAt': session.openedAt.toIso8601String(),
          'closedAt': session.closedAt?.toIso8601String(),
          'initialFloatCents': session.initialFloatCents,
          'expectedBalanceCents': session.expectedBalanceCents,
          'countedBalanceCents': session.countedBalanceCents,
          'differenceCents': session.differenceCents,
          'status': session.status.dbValue,
          'notes': session.notes,
        },
      ),
    );
  }

  Future<void> _enqueueCashMovementEvent(
    DatabaseExecutor txn, {
    required int movementId,
    required String movementUuid,
    required int sessionId,
    required String type,
    required int amountCents,
    required DateTime occurredAt,
    String? description,
  }) async {
    await _operationalSyncQueueRepository.enqueue(
      txn,
      event: OperationalSyncEvent(
        eventId: OperationalSyncEvent.buildEventId(
          entity: 'cashMovement',
          operation: 'create',
          localIdentity: movementUuid,
        ),
        feature: 'pdv',
        entity: 'cashMovement',
        operation: 'create',
        entityLocalId: movementUuid,
        occurredAt: occurredAt,
        payload: <String, dynamic>{
          'localId': movementId,
          'uuid': movementUuid,
          'sessionId': sessionId,
          'type': type,
          'amountCents': amountCents,
          'description': description,
          'createdAt': occurredAt.toIso8601String(),
        },
      ),
    );
  }

  Future<int?> _tryGetOpenSessionId(dynamic db) async {
    final row = await CashDatabaseSupport.getOpenSessionRow(db);
    return row == null ? null : row['id'] as int;
  }

  Future<Map<String, Object?>?> _findSessionRowById(
    DatabaseExecutor db,
    int sessionId,
  ) async {
    final rows = await db.query(
      TableNames.caixaSessoes,
      where: 'id = ?',
      whereArgs: [sessionId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, Object?>?> _findSessionRowByUuid(
    DatabaseExecutor db,
    String uuid,
  ) async {
    final rows = await db.query(
      TableNames.caixaSessoes,
      where: 'uuid = ?',
      whereArgs: [uuid],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, Object?>?> _findMovementRowById(
    DatabaseExecutor db,
    int movementId,
  ) async {
    final rows = await db.query(
      TableNames.caixaMovimentos,
      where: 'id = ?',
      whereArgs: [movementId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, Object?>?> _findMovementRowByUuid(
    DatabaseExecutor db,
    String uuid,
  ) async {
    final rows = await db.query(
      TableNames.caixaMovimentos,
      where: 'uuid = ?',
      whereArgs: [uuid],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, Object?>>> _loadSessionRows(
    DatabaseExecutor db,
  ) async {
    return db.rawQuery('''
      ${_sessionSelectSql()}
      ORDER BY sess.aberta_em DESC, sess.id DESC
    ''');
  }

  Future<Map<String, Object?>> _loadSessionRow(
    DatabaseExecutor db,
    int sessionId,
  ) async {
    final rows = await db.rawQuery(
      '''
      ${_sessionSelectSql()}
      WHERE sess.id = ?
      LIMIT 1
    ''',
      [sessionId],
    );

    if (rows.isEmpty) {
      throw const ValidationException(
        'Sessao de caixa nao encontrada para detalhamento.',
      );
    }

    return rows.first;
  }

  String _sessionSelectSql() {
    return '''
      SELECT
        sess.*,
        usr.nome AS usuario_nome
      FROM ${TableNames.caixaSessoes} sess
      LEFT JOIN ${TableNames.usuarios} usr ON usr.id = sess.usuario_id
    ''';
  }

  Future<List<CashSessionMovementDetail>> _loadSessionMovementDetails(
    Database database,
    int sessionId,
  ) async {
    final rows = await database.rawQuery(
      '''
      SELECT
        mov.*,
        sale_sync.remote_id AS sale_remote_id,
        sale.numero_cupom AS sale_receipt_number,
        sale.tipo_venda AS sale_type,
        sale.forma_pagamento AS sale_payment_method,
        sale.status AS sale_status,
        direct_client.nome AS sale_client_name,
        fiado_payment_sync.remote_id AS fiado_payment_remote_id,
        fiado.venda_id AS fiado_sale_id,
        fiado_sale.numero_cupom AS fiado_receipt_number,
        fiado_sale.tipo_venda AS fiado_sale_type,
        fiado_sale.forma_pagamento AS fiado_sale_payment_method,
        fiado_sale.status AS fiado_sale_status,
        fiado_client.nome AS fiado_client_name
      FROM ${TableNames.caixaMovimentos} mov
      LEFT JOIN ${TableNames.syncRegistros} sale_sync
        ON mov.referencia_tipo = 'venda'
        AND sale_sync.feature_key = '${SyncFeatureKeys.sales}'
        AND sale_sync.remote_id = CAST(mov.referencia_id AS TEXT)
      LEFT JOIN ${TableNames.vendas} sale
        ON mov.referencia_tipo = 'venda'
        AND (sale.id = mov.referencia_id OR sale.id = sale_sync.local_id)
      LEFT JOIN ${TableNames.clientes} direct_client
        ON direct_client.id = sale.cliente_id
      LEFT JOIN ${TableNames.syncRegistros} fiado_payment_sync
        ON mov.referencia_tipo = 'fiado'
        AND fiado_payment_sync.feature_key = '${SyncFeatureKeys.fiadoPayments}'
        AND fiado_payment_sync.remote_id = CAST(mov.referencia_id AS TEXT)
      LEFT JOIN ${TableNames.fiadoLancamentos} fiado_payment
        ON mov.referencia_tipo = 'fiado'
        AND (
          fiado_payment.id = mov.referencia_id
          OR fiado_payment.id = fiado_payment_sync.local_id
        )
      LEFT JOIN ${TableNames.fiado} fiado
        ON mov.referencia_tipo = 'fiado'
        AND fiado.id = fiado_payment.fiado_id
      LEFT JOIN ${TableNames.vendas} fiado_sale
        ON fiado_sale.id = fiado.venda_id
      LEFT JOIN ${TableNames.clientes} fiado_client
        ON fiado_client.id = fiado.cliente_id
      WHERE mov.sessao_id = ?
      ORDER BY mov.criado_em DESC, mov.id DESC
    ''',
      [sessionId],
    );

    return rows.map(_mapMovementDetail).toList();
  }

  Future<List<CashSessionSaleSummary>> _loadSessionSales(
    Database database, {
    required DateTime openedAt,
    required DateTime periodEnd,
  }) async {
    final saleRows = await database.rawQuery(
      '''
      SELECT
        v.*,
        vpo.pedido_operacional_id AS pedido_operacional_id,
        c.nome AS cliente_nome,
        f.id AS fiado_id,
        f.status AS fiado_status,
        f.valor_aberto_centavos AS fiado_valor_aberto_centavos,
        f.vencimento AS fiado_vencimento
      FROM ${TableNames.vendas} v
      LEFT JOIN ${TableNames.vendasPedidosOperacionais} vpo
        ON vpo.venda_id = v.id
      LEFT JOIN ${TableNames.clientes} c ON c.id = v.cliente_id
      LEFT JOIN ${TableNames.fiado} f ON f.venda_id = v.id
      WHERE v.data_venda >= ?
        AND v.data_venda <= ?
      ORDER BY v.data_venda DESC, v.id DESC
    ''',
      [openedAt.toIso8601String(), periodEnd.toIso8601String()],
    );

    if (saleRows.isEmpty) {
      return const <CashSessionSaleSummary>[];
    }

    final sales = saleRows.map(_mapSaleRecord).toList();
    final saleIds = sales.map((sale) => sale.id).toList(growable: false);
    final placeholders = List.filled(saleIds.length, '?').join(', ');
    final itemRows = await database.query(
      TableNames.itensVenda,
      columns: [
        'venda_id',
        'nome_produto_snapshot',
        'quantidade_mil',
        'unidade_medida_snapshot',
      ],
      where: 'venda_id IN ($placeholders)',
      whereArgs: saleIds,
      orderBy: 'id ASC',
    );

    final itemCounts = <int, int>{};
    final previewBySale = <int, List<CashSessionSaleItemPreview>>{};
    for (final row in itemRows) {
      final saleId = row['venda_id'] as int;
      itemCounts[saleId] = (itemCounts[saleId] ?? 0) + 1;
      final preview = previewBySale.putIfAbsent(
        saleId,
        () => <CashSessionSaleItemPreview>[],
      );
      if (preview.length >= 4) {
        continue;
      }
      preview.add(
        CashSessionSaleItemPreview(
          productName: row['nome_produto_snapshot'] as String,
          quantityMil: row['quantidade_mil'] as int,
          unitMeasure: row['unidade_medida_snapshot'] as String,
        ),
      );
    }

    return sales
        .map(
          (sale) => CashSessionSaleSummary(
            sale: sale,
            itemLinesCount: itemCounts[sale.id] ?? 0,
            itemPreview: previewBySale[sale.id] ?? const [],
          ),
        )
        .toList(growable: false);
  }

  CashSession _mapSession(Map<String, Object?> row) {
    final notesPayload = _decodeSessionNotes(row['observacao'] as String?);
    final userName = _cleanNullable(row['usuario_nome'] as String?);
    final fallbackOperatorName =
        row['usuario_id'] == _operationalContext.currentLocalUserId
        ? _operationalContext.session.user.displayName
        : 'Operador local';
    return CashSession(
      id: row['id'] as int,
      uuid: row['uuid'] as String,
      userId: row['usuario_id'] as int?,
      operatorName:
          userName ?? notesPayload.operatorName ?? fallbackOperatorName,
      openedAt: DateTime.parse(row['aberta_em'] as String),
      closedAt: row['fechada_em'] == null
          ? null
          : DateTime.parse(row['fechada_em'] as String),
      initialFloatCents: row['troco_inicial_centavos'] as int? ?? 0,
      awaitingInitialFloatConfirmation:
          (row['aguardando_confirmacao_troco_inicial'] as int? ?? 0) == 1,
      cashEntriesCents:
          row['total_entradas_dinheiro_centavos'] as int? ??
          row['total_vendas_centavos'] as int? ??
          0,
      withdrawalsCents: row['total_sangrias_centavos'] as int? ?? 0,
      suppliesCents: row['total_suprimentos_centavos'] as int? ?? 0,
      fiadoReceiptsCashCents:
          row['total_recebimentos_fiado_dinheiro_centavos'] as int? ??
          row['total_recebimentos_fiado_centavos'] as int? ??
          0,
      fiadoReceiptsPixCents:
          row['total_recebimentos_fiado_pix_centavos'] as int? ?? 0,
      fiadoReceiptsCardCents:
          row['total_recebimentos_fiado_cartao_centavos'] as int? ?? 0,
      expectedBalanceCents:
          row['saldo_esperado_centavos'] as int? ??
          row['saldo_final_centavos'] as int? ??
          0,
      countedBalanceCents: row['saldo_contado_centavos'] as int?,
      differenceCents: row['diferenca_centavos'] as int?,
      status: CashSessionStatusX.fromDb(row['status'] as String),
      notes: notesPayload.visibleNotes,
    );
  }

  CashMovement _mapMovement(Map<String, Object?> row) {
    final description = row['descricao'] as String?;
    return CashMovement(
      id: row['id'] as int,
      uuid: row['uuid'] as String,
      sessionId: row['sessao_id'] as int,
      type: CashMovementTypeX.fromDb(row['tipo_movimento'] as String),
      referenceType: row['referencia_tipo'] as String?,
      referenceId: _stringFromDb(row['referencia_id']),
      amountCents: row['valor_centavos'] as int,
      description: PaymentMethodNoteCodec.clean(description),
      createdAt: DateTime.parse(row['criado_em'] as String),
      paymentMethod: PaymentMethodNoteCodec.parse(description),
    );
  }

  CashSessionMovementDetail _mapMovementDetail(Map<String, Object?> row) {
    final movement = _mapMovement(row);
    final referenceType = movement.referenceType;
    final isFiadoReference = referenceType == 'fiado';
    final receiptNumber = isFiadoReference
        ? row['fiado_receipt_number'] as String?
        : row['sale_receipt_number'] as String?;
    final clientName = isFiadoReference
        ? row['fiado_client_name'] as String?
        : row['sale_client_name'] as String?;
    final saleType = _saleTypeFromRow(
      isFiadoReference
          ? row['fiado_sale_type'] as String?
          : row['sale_type'] as String?,
    );
    final salePaymentMethod = _paymentMethodFromRow(
      isFiadoReference
          ? row['fiado_sale_payment_method'] as String?
          : row['sale_payment_method'] as String?,
    );
    final saleStatus = _saleStatusFromRow(
      isFiadoReference
          ? row['fiado_sale_status'] as String?
          : row['sale_status'] as String?,
    );

    return CashSessionMovementDetail(
      movement: movement,
      originLabel: _movementOriginLabel(
        movement.type,
        referenceType: referenceType,
      ),
      referenceLabel: _buildReferenceLabel(
        referenceType: referenceType,
        referenceId: movement.referenceId,
        receiptNumber: receiptNumber,
      ),
      clientName: clientName,
      receiptNumber: receiptNumber,
      saleType: saleType,
      salePaymentMethod: salePaymentMethod,
      saleStatus: saleStatus,
    );
  }

  SaleRecord _mapSaleRecord(Map<String, Object?> row) {
    return SaleRecord(
      id: row['id'] as int,
      uuid: row['uuid'] as String,
      receiptNumber: row['numero_cupom'] as String,
      saleType: SaleTypeX.fromDb(row['tipo_venda'] as String),
      paymentMethod: PaymentMethodX.fromDb(row['forma_pagamento'] as String),
      operationalOrderId: row['pedido_operacional_id'] as int?,
      status: SaleStatusX.fromDb(row['status'] as String),
      totalCents: row['valor_total_centavos'] as int,
      finalCents: row['valor_final_centavos'] as int,
      discountCents: row['desconto_centavos'] as int? ?? 0,
      surchargeCents: row['acrescimo_centavos'] as int? ?? 0,
      creditUsedCents: row['haver_utilizado_centavos'] as int? ?? 0,
      creditGeneratedCents: row['haver_gerado_centavos'] as int? ?? 0,
      immediateReceivedCents:
          row['valor_recebido_imediato_centavos'] as int? ??
          row['valor_final_centavos'] as int? ??
          0,
      soldAt: DateTime.parse(row['data_venda'] as String),
      clientId: row['cliente_id'] as int?,
      clientName: row['cliente_nome'] as String?,
      notes: row['observacao'] as String?,
      cancelledAt: row['cancelada_em'] == null
          ? null
          : DateTime.parse(row['cancelada_em'] as String),
      fiadoId: row['fiado_id'] as int?,
      fiadoStatus: row['fiado_status'] as String?,
      fiadoOpenCents: row['fiado_valor_aberto_centavos'] as int?,
      fiadoDueDate: row['fiado_vencimento'] == null
          ? null
          : DateTime.parse(row['fiado_vencimento'] as String),
    );
  }

  String _movementOriginLabel(
    CashMovementType type, {
    required String? referenceType,
  }) {
    switch (type) {
      case CashMovementType.sale:
        return 'Venda a vista';
      case CashMovementType.fiadoReceipt:
        return 'Pagamento de fiado';
      case CashMovementType.supply:
        return 'Entrada manual';
      case CashMovementType.sangria:
        return 'Retirada manual';
      case CashMovementType.adjustment:
        return 'Ajuste';
      case CashMovementType.cancellation:
        if (referenceType == 'fiado') {
          return 'Estorno de fiado';
        }
        if (referenceType == 'venda') {
          return 'Cancelamento de venda';
        }
        return 'Cancelamento';
    }
  }

  String? _buildReferenceLabel({
    required String? referenceType,
    required String? referenceId,
    required String? receiptNumber,
  }) {
    if (referenceType == null) {
      return null;
    }
    if (referenceType == 'venda' && receiptNumber != null) {
      return 'Venda $receiptNumber';
    }
    if (referenceType == 'fiado' && receiptNumber != null) {
      return 'Fiado da venda $receiptNumber';
    }
    if (referenceType == 'manual') {
      return 'Lancamento manual';
    }
    if (referenceId != null) {
      return '${referenceType.toUpperCase()} #$referenceId';
    }
    return referenceType;
  }

  SaleType? _saleTypeFromRow(String? value) {
    return value == null ? null : SaleTypeX.fromDb(value);
  }

  PaymentMethod? _paymentMethodFromRow(String? value) {
    return value == null ? null : PaymentMethodX.fromDb(value);
  }

  SaleStatus? _saleStatusFromRow(String? value) {
    return value == null ? null : SaleStatusX.fromDb(value);
  }

  String? _removeAutomaticOpeningNote(String? current) {
    final notesPayload = _decodeSessionNotes(current);
    final cleanedCurrent = _cleanNullable(notesPayload.visibleNotes);
    if (cleanedCurrent == null) {
      return _encodeSessionNotes(operatorName: notesPayload.operatorName);
    }

    final lines = cleanedCurrent
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && line != _autoOpenedNote)
        .toList(growable: false);
    if (lines.isEmpty) {
      return _encodeSessionNotes(operatorName: notesPayload.operatorName);
    }
    return _encodeSessionNotes(
      visibleNotes: lines.join('\n'),
      operatorName: notesPayload.operatorName,
    );
  }

  String? _mergeNotes(String? current, String? appended) {
    final notesPayload = _decodeSessionNotes(current);
    final cleanedCurrent = _cleanNullable(notesPayload.visibleNotes);
    final cleanedAppended = _cleanNullable(appended);

    if (cleanedCurrent == null) {
      return _encodeSessionNotes(
        visibleNotes: cleanedAppended,
        operatorName: notesPayload.operatorName,
      );
    }
    if (cleanedAppended == null) {
      return _encodeSessionNotes(
        visibleNotes: cleanedCurrent,
        operatorName: notesPayload.operatorName,
      );
    }

    return _encodeSessionNotes(
      visibleNotes: '$cleanedCurrent\n$cleanedAppended',
      operatorName: notesPayload.operatorName,
    );
  }

  String? _cleanNullable(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  Future<Object?> _resolveRemoteMovementReferenceId(
    DatabaseExecutor txn, {
    required String? referenceType,
    required String? referenceId,
  }) async {
    final cleanedReferenceId = _cleanNullable(referenceId);
    if (cleanedReferenceId == null) {
      return null;
    }

    final featureKey = switch (referenceType) {
      'venda' => SyncFeatureKeys.sales,
      'fiado' => SyncFeatureKeys.fiadoPayments,
      _ => null,
    };
    if (featureKey == null) {
      return int.tryParse(cleanedReferenceId) ?? cleanedReferenceId;
    }

    final metadata = await _syncMetadataRepository.findByRemoteId(
      txn,
      featureKey: featureKey,
      remoteId: cleanedReferenceId,
    );
    return metadata?.identity.localId ??
        int.tryParse(cleanedReferenceId) ??
        cleanedReferenceId;
  }

  String? _stringFromDb(Object? value) {
    if (value == null) {
      return null;
    }
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  int? _intFromDb(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }

  String? _encodeSessionNotes({
    String? visibleNotes,
    String? operatorName,
  }) {
    final cleanedVisibleNotes = _cleanNullable(visibleNotes);
    final cleanedOperatorName = _cleanNullable(operatorName);
    final lines = <String>[];
    if (cleanedVisibleNotes != null) {
      lines.add(cleanedVisibleNotes);
    }
    if (cleanedOperatorName != null) {
      lines.add(
        '$_sessionMetadataPrefix${jsonEncode(<String, String>{'operatorName': cleanedOperatorName})}',
      );
    }
    if (lines.isEmpty) {
      return null;
    }
    return lines.join('\n');
  }

  _SessionNotesPayload _decodeSessionNotes(String? raw) {
    final cleanedRaw = _cleanNullable(raw);
    if (cleanedRaw == null) {
      return const _SessionNotesPayload();
    }

    final visibleLines = <String>[];
    String? operatorName;
    for (final line in cleanedRaw.split('\n')) {
      final trimmedLine = line.trim();
      if (trimmedLine.startsWith(_sessionMetadataPrefix)) {
        final encodedMetadata = trimmedLine.substring(
          _sessionMetadataPrefix.length,
        );
        try {
          final decoded = jsonDecode(encodedMetadata);
          if (decoded is Map<String, dynamic>) {
            operatorName = _cleanNullable(decoded['operatorName'] as String?);
          }
        } catch (_) {
          visibleLines.add(trimmedLine);
        }
        continue;
      }
      if (trimmedLine.isNotEmpty) {
        visibleLines.add(trimmedLine);
      }
    }

    return _SessionNotesPayload(
      visibleNotes: visibleLines.isEmpty ? null : visibleLines.join('\n'),
      operatorName: operatorName,
    );
  }
}

class _SessionNotesPayload {
  const _SessionNotesPayload({this.visibleNotes, this.operatorName});

  final String? visibleNotes;
  final String? operatorName;
}
