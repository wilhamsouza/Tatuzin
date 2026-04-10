import '../../../app/core/app_context/app_operational_context.dart';
import '../../../app/core/app_context/record_identity.dart';
import '../../../app/core/database/app_database.dart';
import '../../../app/core/database/table_names.dart';
import '../../../app/core/errors/app_exceptions.dart';
import '../../../app/core/sync/sqlite_sync_metadata_repository.dart';
import '../../../app/core/sync/sqlite_sync_queue_repository.dart';
import '../../../app/core/sync/sync_feature_keys.dart';
import '../../../app/core/sync/sync_queue_operation.dart';
import '../../../app/core/sync/sync_status.dart';
import '../../../app/core/utils/id_generator.dart';
import '../../../app/core/utils/payment_method_note_codec.dart';
import '../../caixa/data/cash_database_support.dart';
import '../../caixa/domain/entities/cash_enums.dart';
import '../../vendas/domain/entities/sale_enums.dart';
import '../domain/entities/fiado_account.dart';
import '../domain/entities/fiado_detail.dart';
import '../domain/entities/fiado_payment_entry.dart';
import '../domain/entities/fiado_payment_input.dart';
import '../domain/repositories/fiado_repository.dart';
import 'models/fiado_payment_sync_payload.dart';

class SqliteFiadoRepository implements FiadoRepository {
  SqliteFiadoRepository(this._appDatabase, this._operationalContext)
    : _syncMetadataRepository = SqliteSyncMetadataRepository(_appDatabase),
      _syncQueueRepository = SqliteSyncQueueRepository(_appDatabase);

  static const String paymentFeatureKey = SyncFeatureKeys.fiadoPayments;
  static const String financialEventFeatureKey =
      SyncFeatureKeys.financialEvents;

  final AppDatabase _appDatabase;
  final AppOperationalContext _operationalContext;
  final SqliteSyncMetadataRepository _syncMetadataRepository;
  final SqliteSyncQueueRepository _syncQueueRepository;

  @override
  Future<FiadoDetail> fetchDetail(int fiadoId) async {
    final database = await _appDatabase.database;
    final accountRows = await database.rawQuery(
      '''
      SELECT
        f.*,
        c.nome AS cliente_nome,
        v.numero_cupom AS numero_cupom
      FROM ${TableNames.fiado} f
      INNER JOIN ${TableNames.clientes} c ON c.id = f.cliente_id
      INNER JOIN ${TableNames.vendas} v ON v.id = f.venda_id
      WHERE f.id = ?
      LIMIT 1
    ''',
      [fiadoId],
    );

    if (accountRows.isEmpty) {
      throw const ValidationException('Nota de fiado nao encontrada.');
    }

    final entryRows = await database.query(
      TableNames.fiadoLancamentos,
      where: 'fiado_id = ?',
      whereArgs: [fiadoId],
      orderBy: 'data_lancamento DESC, id DESC',
    );

    return FiadoDetail(
      account: _mapAccount(accountRows.first),
      entries: entryRows.map(_mapEntry).toList(),
    );
  }

  @override
  Future<FiadoDetail> registerPayment(FiadoPaymentInput input) async {
    final database = await _appDatabase.database;

    await database.transaction((txn) async {
      final fiadoRows = await txn.rawQuery(
        '''
        SELECT
          f.*,
          c.saldo_devedor_centavos AS cliente_saldo_devedor_centavos,
          c.nome AS cliente_nome,
          v.numero_cupom AS numero_cupom
        FROM ${TableNames.fiado} f
        INNER JOIN ${TableNames.clientes} c ON c.id = f.cliente_id
        INNER JOIN ${TableNames.vendas} v ON v.id = f.venda_id
        WHERE f.id = ?
        LIMIT 1
      ''',
        [input.fiadoId],
      );

      if (fiadoRows.isEmpty) {
        throw const ValidationException('Nota de fiado nao encontrada.');
      }

      final fiadoRow = fiadoRows.first;
      final currentStatus = fiadoRow['status'] as String;
      final openCents = fiadoRow['valor_aberto_centavos'] as int;
      final originalCents = fiadoRow['valor_original_centavos'] as int;

      if (currentStatus == 'quitado') {
        throw const ValidationException('Esta nota ja foi quitada.');
      }

      if (currentStatus == 'cancelado') {
        throw const ValidationException(
          'Nao e possivel pagar uma nota cancelada.',
        );
      }

      if (input.amountCents > openCents) {
        throw ValidationException(
          'O valor informado excede o saldo em aberto de ${fiadoRow['cliente_nome']}.',
        );
      }

      final now = DateTime.now();
      final nowIso = now.toIso8601String();
      final remainingCents = openCents - input.amountCents;
      final nextStatus = remainingCents == 0
          ? 'quitado'
          : (remainingCents == originalCents ? 'pendente' : 'parcial');

      final sessionId = await CashDatabaseSupport.ensureOpenSession(
        txn,
        timestamp: now,
        userId: _operationalContext.currentLocalUserId,
      );
      await CashSessionMathSupport.applySessionDeltas(
        txn,
        sessionId: sessionId,
        fiadoReceiptsCashDeltaCents: input.paymentMethod == PaymentMethod.cash
            ? input.amountCents
            : 0,
        fiadoReceiptsPixDeltaCents: input.paymentMethod == PaymentMethod.pix
            ? input.amountCents
            : 0,
        fiadoReceiptsCardDeltaCents: input.paymentMethod == PaymentMethod.card
            ? input.amountCents
            : 0,
      );
      final cashMovement = await CashDatabaseSupport.insertMovement(
        txn,
        sessionId: sessionId,
        type: CashMovementType.fiadoReceipt,
        amountCents: input.amountCents,
        timestamp: now,
        referenceType: 'fiado',
        referenceId: input.fiadoId,
        description:
            'Recebimento do fiado ${fiadoRow['numero_cupom']} de ${fiadoRow['cliente_nome']}',
        paymentMethod: input.paymentMethod,
      );

      await _registerCashEventForSync(
        txn,
        movementId: cashMovement.id,
        movementUuid: cashMovement.uuid,
        createdAt: now,
      );

      final paymentUuid = IdGenerator.next();
      final paymentEntryId = await txn.insert(TableNames.fiadoLancamentos, {
        'uuid': paymentUuid,
        'fiado_id': input.fiadoId,
        'cliente_id': fiadoRow['cliente_id'] as int,
        'tipo_lancamento': 'pagamento',
        'valor_centavos': input.amountCents,
        'data_lancamento': nowIso,
        'observacao': PaymentMethodNoteCodec.withPaymentMethod(
          input.notes ?? 'Pagamento registrado',
          paymentMethod: input.paymentMethod,
        ),
        'caixa_movimento_id': cashMovement.id,
      });

      await txn.update(
        TableNames.fiado,
        {
          'valor_aberto_centavos': remainingCents,
          'status': nextStatus,
          'atualizado_em': nowIso,
          'quitado_em': remainingCents == 0 ? nowIso : null,
        },
        where: 'id = ?',
        whereArgs: [input.fiadoId],
      );

      final clientCurrentDebt =
          fiadoRow['cliente_saldo_devedor_centavos'] as int? ?? 0;
      final nextClientDebt = clientCurrentDebt - input.amountCents;

      await txn.update(
        TableNames.clientes,
        {
          'saldo_devedor_centavos': nextClientDebt < 0 ? 0 : nextClientDebt,
          'atualizado_em': nowIso,
        },
        where: 'id = ?',
        whereArgs: [fiadoRow['cliente_id']],
      );

      await _registerPaymentForSync(
        txn,
        paymentEntryId: paymentEntryId,
        paymentUuid: paymentUuid,
        createdAt: now,
      );
    });

    return fetchDetail(input.fiadoId);
  }

  @override
  Future<List<FiadoAccount>> search({
    String query = '',
    String? status,
    bool overdueOnly = false,
  }) async {
    final database = await _appDatabase.database;
    final args = <Object?>[];
    final buffer = StringBuffer('''
      SELECT
        f.*,
        c.nome AS cliente_nome,
        v.numero_cupom AS numero_cupom
      FROM ${TableNames.fiado} f
      INNER JOIN ${TableNames.clientes} c ON c.id = f.cliente_id
      INNER JOIN ${TableNames.vendas} v ON v.id = f.venda_id
      WHERE 1 = 1
    ''');

    if (status != null && status.isNotEmpty) {
      buffer.write(' AND f.status = ?');
      args.add(status);
    }

    if (overdueOnly) {
      buffer.write(
        " AND f.status IN ('pendente', 'parcial') AND f.vencimento < ?",
      );
      args.add(DateTime.now().toIso8601String());
    }

    final trimmedQuery = query.trim();
    if (trimmedQuery.isNotEmpty) {
      buffer.write('''
         AND (
           c.nome LIKE ? COLLATE NOCASE
           OR v.numero_cupom LIKE ? COLLATE NOCASE
         )
      ''');
      args.add('%$trimmedQuery%');
      args.add('%$trimmedQuery%');
    }

    buffer.write(' ORDER BY f.vencimento ASC, f.id DESC');

    final rows = await database.rawQuery(buffer.toString(), args);
    return rows.map(_mapAccount).toList();
  }

  FiadoAccount _mapAccount(Map<String, Object?> row) {
    return FiadoAccount(
      id: row['id'] as int,
      uuid: row['uuid'] as String,
      saleId: row['venda_id'] as int,
      clientId: row['cliente_id'] as int,
      clientName: row['cliente_nome'] as String,
      originalCents: row['valor_original_centavos'] as int,
      openCents: row['valor_aberto_centavos'] as int,
      dueDate: DateTime.parse(row['vencimento'] as String),
      status: row['status'] as String,
      createdAt: DateTime.parse(row['criado_em'] as String),
      updatedAt: DateTime.parse(row['atualizado_em'] as String),
      settledAt: row['quitado_em'] == null
          ? null
          : DateTime.parse(row['quitado_em'] as String),
      receiptNumber: row['numero_cupom'] as String,
    );
  }

  FiadoPaymentEntry _mapEntry(Map<String, Object?> row) {
    final notes = row['observacao'] as String?;
    return FiadoPaymentEntry(
      id: row['id'] as int,
      uuid: row['uuid'] as String,
      fiadoId: row['fiado_id'] as int,
      clientId: row['cliente_id'] as int,
      entryType: row['tipo_lancamento'] as String,
      amountCents: row['valor_centavos'] as int,
      registeredAt: DateTime.parse(row['data_lancamento'] as String),
      notes: PaymentMethodNoteCodec.clean(notes),
      cashMovementId: row['caixa_movimento_id'] as int?,
      paymentMethod: PaymentMethodNoteCodec.parse(notes),
    );
  }

  Future<FiadoPaymentSyncPayload?> findPaymentForSync(
    int paymentEntryId,
  ) async {
    final database = await _appDatabase.database;
    final rows = await database.rawQuery(
      '''
      SELECT
        lanc.id,
        lanc.uuid,
        lanc.fiado_id,
        fiado.uuid AS fiado_uuid,
        lanc.valor_centavos,
        lanc.data_lancamento,
        lanc.observacao,
        fiado.venda_id AS venda_id,
        sale_sync.remote_id AS sale_remote_id,
        payment_sync.remote_id AS payment_remote_id,
        payment_sync.sync_status AS payment_sync_status,
        payment_sync.last_synced_at AS payment_last_synced_at
      FROM ${TableNames.fiadoLancamentos} lanc
      INNER JOIN ${TableNames.fiado} fiado ON fiado.id = lanc.fiado_id
      LEFT JOIN ${TableNames.syncRegistros} sale_sync
        ON sale_sync.feature_key = '${SyncFeatureKeys.sales}'
        AND sale_sync.local_id = fiado.venda_id
      LEFT JOIN ${TableNames.syncRegistros} payment_sync
        ON payment_sync.feature_key = '$paymentFeatureKey'
        AND payment_sync.local_id = lanc.id
      WHERE lanc.id = ?
        AND lanc.tipo_lancamento = 'pagamento'
      LIMIT 1
    ''',
      [paymentEntryId],
    );

    if (rows.isEmpty) {
      return null;
    }

    final row = rows.first;
    final notes = row['observacao'] as String?;
    return FiadoPaymentSyncPayload(
      entryId: row['id'] as int,
      entryUuid: row['uuid'] as String,
      fiadoId: row['fiado_id'] as int,
      fiadoUuid: row['fiado_uuid'] as String,
      saleLocalId: row['venda_id'] as int,
      saleRemoteId: row['sale_remote_id'] as String?,
      amountCents: row['valor_centavos'] as int,
      paymentMethod: PaymentMethodNoteCodec.parse(notes) ?? PaymentMethod.cash,
      notes: PaymentMethodNoteCodec.clean(notes),
      createdAt: DateTime.parse(row['data_lancamento'] as String),
      updatedAt: DateTime.parse(row['data_lancamento'] as String),
      remoteId: row['payment_remote_id'] as String?,
      syncStatus: syncStatusFromStorage(row['payment_sync_status'] as String?),
      lastSyncedAt: row['payment_last_synced_at'] == null
          ? null
          : DateTime.parse(row['payment_last_synced_at'] as String),
    );
  }

  Future<void> markPaymentSynced({
    required FiadoPaymentSyncPayload payment,
    required String remoteId,
    required DateTime syncedAt,
  }) async {
    final database = await _appDatabase.database;
    await database.transaction((txn) async {
      await _syncMetadataRepository.markSynced(
        txn,
        featureKey: paymentFeatureKey,
        localId: payment.entryId,
        localUuid: payment.entryUuid,
        remoteId: remoteId,
        origin: RecordOrigin.local,
        createdAt: payment.createdAt,
        updatedAt: payment.updatedAt,
        syncedAt: syncedAt,
      );
    });
  }

  Future<void> markPaymentConflict({
    required FiadoPaymentSyncPayload payment,
    required String message,
    required DateTime detectedAt,
  }) async {
    final database = await _appDatabase.database;
    await database.transaction((txn) async {
      await _syncMetadataRepository.markConflict(
        txn,
        featureKey: paymentFeatureKey,
        localId: payment.entryId,
        localUuid: payment.entryUuid,
        remoteId: payment.remoteId,
        createdAt: payment.createdAt,
        updatedAt: detectedAt,
        message: message,
      );
    });
  }

  Future<void> _registerPaymentForSync(
    dynamic txn, {
    required int paymentEntryId,
    required String paymentUuid,
    required DateTime createdAt,
  }) async {
    await _syncMetadataRepository.markPendingUpload(
      txn,
      featureKey: paymentFeatureKey,
      localId: paymentEntryId,
      localUuid: paymentUuid,
      createdAt: createdAt,
      updatedAt: createdAt,
    );
    await _syncQueueRepository.enqueueMutation(
      txn,
      featureKey: financialEventFeatureKey,
      entityType: 'fiado_payment_event',
      localEntityId: paymentEntryId,
      localUuid: paymentUuid,
      remoteId: null,
      operation: SyncQueueOperation.create,
      localUpdatedAt: createdAt,
    );
  }

  Future<void> _registerCashEventForSync(
    dynamic txn, {
    required int movementId,
    required String movementUuid,
    required DateTime createdAt,
  }) async {
    await _syncMetadataRepository.markPendingUpload(
      txn,
      featureKey: SyncFeatureKeys.cashEvents,
      localId: movementId,
      localUuid: movementUuid,
      createdAt: createdAt,
      updatedAt: createdAt,
    );
    await _syncQueueRepository.enqueueMutation(
      txn,
      featureKey: SyncFeatureKeys.cashEvents,
      entityType: 'cash_event',
      localEntityId: movementId,
      localUuid: movementUuid,
      remoteId: null,
      operation: SyncQueueOperation.create,
      localUpdatedAt: createdAt,
    );
  }
}
