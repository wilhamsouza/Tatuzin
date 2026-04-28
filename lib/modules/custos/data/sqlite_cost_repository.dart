import 'dart:async';

import 'package:sqflite/sqflite.dart';

import '../../../app/core/app_context/app_operational_context.dart';
import '../../../app/core/database/app_database.dart';
import '../../../app/core/database/table_names.dart';
import '../../../app/core/errors/app_exceptions.dart';
import '../../../app/core/sync/sqlite_sync_metadata_repository.dart';
import '../../../app/core/sync/sqlite_sync_queue_repository.dart';
import '../../../app/core/sync/sync_queue_operation.dart';
import '../../../app/core/utils/app_logger.dart';
import '../../../app/core/utils/id_generator.dart';
import '../../caixa/data/cash_database_support.dart';
import '../../caixa/data/sqlite_cash_repository.dart';
import '../../caixa/domain/entities/cash_enums.dart';
import '../../vendas/domain/entities/sale_enums.dart';
import '../domain/entities/cost_entry.dart';
import '../domain/entities/cost_overview.dart';
import '../domain/entities/cost_status.dart';
import '../domain/entities/cost_type.dart';
import '../domain/repositories/cost_repository.dart';

class SqliteCostRepository implements CostRepository {
  SqliteCostRepository(this._appDatabase, this._operationalContext)
    : _syncMetadataRepository = SqliteSyncMetadataRepository(_appDatabase),
      _syncQueueRepository = SqliteSyncQueueRepository(_appDatabase),
      _databaseLoader = null;

  SqliteCostRepository.forDatabase({
    required Future<Database> Function() databaseLoader,
    required AppOperationalContext operationalContext,
  }) : _appDatabase = AppDatabase.instance,
       _operationalContext = operationalContext,
       _syncMetadataRepository = SqliteSyncMetadataRepository(
         AppDatabase.instance,
       ),
       _syncQueueRepository = SqliteSyncQueueRepository(AppDatabase.instance),
       _databaseLoader = databaseLoader;

  final AppDatabase _appDatabase;
  final AppOperationalContext _operationalContext;
  final SqliteSyncMetadataRepository _syncMetadataRepository;
  final SqliteSyncQueueRepository _syncQueueRepository;
  final Future<Database> Function()? _databaseLoader;
  static const _localQueryTimeout = Duration(seconds: 6);

  Future<Database> _loadDatabase() {
    final databaseLoader = _databaseLoader;
    if (databaseLoader != null) {
      return databaseLoader();
    }
    return _appDatabase.database;
  }

  @override
  Future<CostOverview> fetchOverview() async {
    final stopwatch = Stopwatch()..start();
    AppLogger.info('[CustosSQLite] fetchOverview database started');
    final database = await _loadDatabase();
    AppLogger.info(
      '[CustosSQLite] fetchOverview database finished | duration_ms=${stopwatch.elapsedMilliseconds}',
    );
    final now = DateTime.now();
    final today = _normalizeDay(now).toIso8601String();
    final monthStart = DateTime(now.year, now.month).toIso8601String();
    final nextMonth = DateTime(now.year, now.month + 1).toIso8601String();

    AppLogger.info('[CustosSQLite] fetchOverview sql_started');
    final List<Map<String, Object?>> rows;
    try {
      rows = await database
          .rawQuery(
            '''
      SELECT
        COALESCE(SUM(CASE WHEN tipo_custo = 'fixed' AND status = 'pending' THEN valor_centavos ELSE 0 END), 0) AS pendente_fixo,
        COALESCE(SUM(CASE WHEN tipo_custo = 'variable' AND status = 'pending' THEN valor_centavos ELSE 0 END), 0) AS pendente_variavel,
        COALESCE(SUM(CASE WHEN tipo_custo = 'fixed' AND status = 'pending' AND data_referencia < ? THEN valor_centavos ELSE 0 END), 0) AS vencido_fixo,
        COALESCE(SUM(CASE WHEN tipo_custo = 'variable' AND status = 'pending' AND data_referencia < ? THEN valor_centavos ELSE 0 END), 0) AS vencido_variavel,
        COALESCE(SUM(CASE WHEN tipo_custo = 'fixed' AND status = 'paid' AND pago_em >= ? AND pago_em < ? THEN valor_centavos ELSE 0 END), 0) AS pago_fixo_mes,
        COALESCE(SUM(CASE WHEN tipo_custo = 'variable' AND status = 'paid' AND pago_em >= ? AND pago_em < ? THEN valor_centavos ELSE 0 END), 0) AS pago_variavel_mes,
        COALESCE(SUM(CASE WHEN tipo_custo = 'fixed' AND status = 'pending' THEN 1 ELSE 0 END), 0) AS quantidade_fixo,
        COALESCE(SUM(CASE WHEN tipo_custo = 'variable' AND status = 'pending' THEN 1 ELSE 0 END), 0) AS quantidade_variavel
      FROM ${TableNames.custos}
    ''',
            [today, today, monthStart, nextMonth, monthStart, nextMonth],
          )
          .timeout(
            _localQueryTimeout,
            onTimeout: () {
              throw TimeoutException(
                'cost_fetch_overview_timeout',
                _localQueryTimeout,
              );
            },
          );
      AppLogger.info(
        '[CustosSQLite] fetchOverview sql_finished rows=${rows.length} | duration_ms=${stopwatch.elapsedMilliseconds}',
      );
    } catch (error, stackTrace) {
      AppLogger.error(
        '[CustosSQLite] fetchOverview sql_failed | duration_ms=${stopwatch.elapsedMilliseconds}',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }

    final row = rows.first;
    return CostOverview(
      pendingFixedCents: _toInt(row['pendente_fixo']),
      pendingVariableCents: _toInt(row['pendente_variavel']),
      overdueFixedCents: _toInt(row['vencido_fixo']),
      overdueVariableCents: _toInt(row['vencido_variavel']),
      paidFixedThisMonthCents: _toInt(row['pago_fixo_mes']),
      paidVariableThisMonthCents: _toInt(row['pago_variavel_mes']),
      openFixedCount: _toInt(row['quantidade_fixo']),
      openVariableCount: _toInt(row['quantidade_variavel']),
    );
  }

  @override
  Future<List<CostEntry>> searchCosts({
    required CostType type,
    String query = '',
    CostStatus? status,
    DateTime? from,
    DateTime? to,
    bool overdueOnly = false,
  }) async {
    final stopwatch = Stopwatch()..start();
    AppLogger.info('[CustosSQLite] searchCosts database started');
    final database = await _loadDatabase();
    AppLogger.info(
      '[CustosSQLite] searchCosts database finished | duration_ms=${stopwatch.elapsedMilliseconds}',
    );
    final args = <Object?>[type.dbValue];
    final buffer = StringBuffer('''
      SELECT *
      FROM ${TableNames.custos}
      WHERE tipo_custo = ?
    ''');

    if (status != null) {
      buffer.write(' AND status = ?');
      args.add(status.dbValue);
    }

    if (from != null) {
      buffer.write(' AND data_referencia >= ?');
      args.add(_normalizeDay(from).toIso8601String());
    }

    if (to != null) {
      buffer.write(' AND data_referencia <= ?');
      args.add(_normalizeDay(to).toIso8601String());
    }

    final today = _normalizeDay(DateTime.now()).toIso8601String();
    if (overdueOnly) {
      buffer.write(" AND status = 'pending' AND data_referencia < ?");
      args.add(today);
    }

    final trimmedQuery = query.trim();
    if (trimmedQuery.isNotEmpty) {
      buffer.write('''
        AND (
          descricao LIKE ? COLLATE NOCASE
          OR COALESCE(categoria, '') LIKE ? COLLATE NOCASE
          OR COALESCE(observacao, '') LIKE ? COLLATE NOCASE
        )
      ''');
      args.add('%$trimmedQuery%');
      args.add('%$trimmedQuery%');
      args.add('%$trimmedQuery%');
    }

    buffer.write('''
      ORDER BY
        CASE
          WHEN status = 'pending' AND data_referencia < ? THEN 0
          WHEN status = 'pending' THEN 1
          WHEN status = 'paid' THEN 2
          ELSE 3
        END,
        CASE
          WHEN status = 'paid' THEN COALESCE(pago_em, atualizado_em)
          WHEN status = 'canceled' THEN COALESCE(cancelado_em, atualizado_em)
          ELSE data_referencia
        END DESC,
        id DESC
    ''');
    args.add(today);

    AppLogger.info('[CustosSQLite] searchCosts sql_started');
    final List<Map<String, Object?>> rows;
    try {
      rows = await database
          .rawQuery(buffer.toString(), args)
          .timeout(
            _localQueryTimeout,
            onTimeout: () {
              throw TimeoutException(
                'cost_search_costs_timeout',
                _localQueryTimeout,
              );
            },
          );
      AppLogger.info(
        '[CustosSQLite] searchCosts sql_finished rows=${rows.length} | duration_ms=${stopwatch.elapsedMilliseconds}',
      );
    } catch (error, stackTrace) {
      AppLogger.error(
        '[CustosSQLite] searchCosts sql_failed | duration_ms=${stopwatch.elapsedMilliseconds}',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
    return rows.map(_mapCost).toList(growable: false);
  }

  @override
  Future<CostEntry> fetchCost(int costId) async {
    final database = await _loadDatabase();
    final rows = await database.query(
      TableNames.custos,
      where: 'id = ?',
      whereArgs: [costId],
      limit: 1,
    );

    if (rows.isEmpty) {
      throw const ValidationException('Custo nao encontrado.');
    }

    return _mapCost(rows.first);
  }

  @override
  Future<int> createCost(CreateCostInput input) async {
    final database = await _loadDatabase();
    return database.transaction((txn) async {
      _validateCostInput(
        description: input.description,
        amountCents: input.amountCents,
      );

      final now = DateTime.now();
      return txn.insert(TableNames.custos, {
        'uuid': IdGenerator.next(),
        'remote_id': null,
        'descricao': input.description.trim(),
        'tipo_custo': input.type.dbValue,
        'categoria': _cleanNullable(input.category),
        'valor_centavos': input.amountCents,
        'data_referencia': _normalizeDay(input.referenceDate).toIso8601String(),
        'pago_em': null,
        'forma_pagamento': null,
        'observacao': _cleanNullable(input.notes),
        'recorrente': input.isRecurring ? 1 : 0,
        'status': CostStatus.pending.dbValue,
        'caixa_movimento_id': null,
        'criado_em': now.toIso8601String(),
        'atualizado_em': now.toIso8601String(),
        'cancelado_em': null,
      });
    });
  }

  @override
  Future<CostEntry> updateCost({
    required int costId,
    required UpdateCostInput input,
  }) async {
    final database = await _loadDatabase();
    await database.transaction((txn) async {
      _validateCostInput(
        description: input.description,
        amountCents: input.amountCents,
      );

      final existing = await _findCostRow(txn, costId);
      if (existing == null) {
        throw const ValidationException('Custo nao encontrado.');
      }

      final status = CostStatusX.fromDb(existing['status'] as String? ?? '');
      if (status != CostStatus.pending) {
        throw const ValidationException(
          'Apenas custos pendentes podem ser editados.',
        );
      }

      await txn.update(
        TableNames.custos,
        {
          'descricao': input.description.trim(),
          'tipo_custo': input.type.dbValue,
          'categoria': _cleanNullable(input.category),
          'valor_centavos': input.amountCents,
          'data_referencia': _normalizeDay(
            input.referenceDate,
          ).toIso8601String(),
          'observacao': _cleanNullable(input.notes),
          'recorrente': input.isRecurring ? 1 : 0,
          'atualizado_em': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [costId],
      );
    });

    return fetchCost(costId);
  }

  @override
  Future<CostEntry> markCostPaid(MarkCostPaidInput input) async {
    final database = await _loadDatabase();
    await database.transaction((txn) async {
      final existing = await _findCostRow(txn, input.costId);
      if (existing == null) {
        throw const ValidationException('Custo nao encontrado.');
      }

      final status = CostStatusX.fromDb(existing['status'] as String? ?? '');
      if (status == CostStatus.canceled) {
        throw const ValidationException(
          'Nao e possivel pagar um custo cancelado.',
        );
      }
      if (status == CostStatus.paid) {
        throw const ValidationException(
          'Este custo ja esta marcado como pago.',
        );
      }
      if (input.paymentMethod == PaymentMethod.fiado) {
        throw const ValidationException(
          'Selecione uma forma de pagamento valida para o custo.',
        );
      }

      final now = DateTime.now();
      final paidAt = DateTime(
        input.paidAt.year,
        input.paidAt.month,
        input.paidAt.day,
        now.hour,
        now.minute,
        now.second,
        now.millisecond,
        now.microsecond,
      );
      final amountCents = existing['valor_centavos'] as int? ?? 0;
      int? cashMovementId;

      if (input.registerInCash) {
        final sessionId = await CashDatabaseSupport.ensureOpenSession(
          txn,
          timestamp: paidAt,
          userId: _operationalContext.currentLocalUserId,
        );
        await CashSessionMathSupport.applySessionDeltas(
          txn,
          sessionId: sessionId,
          withdrawalsDeltaCents: amountCents,
        );
        final movement = await CashDatabaseSupport.insertMovement(
          txn,
          sessionId: sessionId,
          type: CashMovementType.sangria,
          amountCents: -amountCents,
          timestamp: paidAt,
          referenceType: 'custo',
          referenceId: input.costId,
          description: 'Pagamento de custo: ${existing['descricao']}',
          paymentMethod: input.paymentMethod,
        );
        cashMovementId = movement.id;
        await _registerCashEventForSync(
          txn,
          movementId: movement.id,
          movementUuid: movement.uuid,
          createdAt: paidAt,
        );
      }

      await txn.update(
        TableNames.custos,
        {
          'status': CostStatus.paid.dbValue,
          'pago_em': paidAt.toIso8601String(),
          'forma_pagamento': input.paymentMethod.dbValue,
          'observacao': _mergeNotes(
            existing['observacao'] as String?,
            input.notes,
          ),
          'caixa_movimento_id': cashMovementId,
          'atualizado_em': now.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [input.costId],
      );
    });

    return fetchCost(input.costId);
  }

  @override
  Future<CostEntry> cancelCost({required int costId, String? notes}) async {
    final database = await _loadDatabase();
    await database.transaction((txn) async {
      final existing = await _findCostRow(txn, costId);
      if (existing == null) {
        throw const ValidationException('Custo nao encontrado.');
      }

      final status = CostStatusX.fromDb(existing['status'] as String? ?? '');
      if (status == CostStatus.paid) {
        throw const ValidationException(
          'Custos ja pagos nao podem ser cancelados nesta etapa.',
        );
      }
      if (status == CostStatus.canceled) {
        return;
      }

      final now = DateTime.now();
      await txn.update(
        TableNames.custos,
        {
          'status': CostStatus.canceled.dbValue,
          'observacao': _mergeNotes(existing['observacao'] as String?, notes),
          'cancelado_em': now.toIso8601String(),
          'atualizado_em': now.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [costId],
      );
    });

    return fetchCost(costId);
  }

  Future<Map<String, Object?>?> _findCostRow(
    DatabaseExecutor db,
    int costId,
  ) async {
    final rows = await db.query(
      TableNames.custos,
      where: 'id = ?',
      whereArgs: [costId],
      limit: 1,
    );

    return rows.isEmpty ? null : rows.first;
  }

  Future<void> _registerCashEventForSync(
    DatabaseExecutor txn, {
    required int movementId,
    required String movementUuid,
    required DateTime createdAt,
  }) async {
    await _syncMetadataRepository.markPendingUpload(
      txn,
      featureKey: SqliteCashRepository.cashEventFeatureKey,
      localId: movementId,
      localUuid: movementUuid,
      createdAt: createdAt,
      updatedAt: createdAt,
    );
    await _syncQueueRepository.enqueueMutation(
      txn,
      featureKey: SqliteCashRepository.cashEventFeatureKey,
      entityType: 'cash_event',
      localEntityId: movementId,
      localUuid: movementUuid,
      remoteId: null,
      operation: SyncQueueOperation.create,
      localUpdatedAt: createdAt,
    );
  }

  void _validateCostInput({
    required String description,
    required int amountCents,
  }) {
    if (description.trim().isEmpty) {
      throw const ValidationException('Informe uma descricao para o custo.');
    }
    if (amountCents <= 0) {
      throw const ValidationException('Informe um valor maior que zero.');
    }
  }

  CostEntry _mapCost(Map<String, Object?> row) {
    return CostEntry(
      id: row['id'] as int,
      uuid: row['uuid'] as String,
      remoteId: row['remote_id'] as String?,
      description: row['descricao'] as String,
      type: CostTypeX.fromDb(row['tipo_custo'] as String? ?? 'variable'),
      category: row['categoria'] as String?,
      amountCents: row['valor_centavos'] as int? ?? 0,
      referenceDate: DateTime.parse(row['data_referencia'] as String),
      paidAt: row['pago_em'] == null
          ? null
          : DateTime.parse(row['pago_em'] as String),
      paymentMethod: _parsePaymentMethod(row['forma_pagamento'] as String?),
      notes: row['observacao'] as String?,
      isRecurring: (row['recorrente'] as int? ?? 0) == 1,
      status: CostStatusX.fromDb(row['status'] as String? ?? 'pending'),
      cashMovementId: row['caixa_movimento_id'] as int?,
      createdAt: DateTime.parse(row['criado_em'] as String),
      updatedAt: DateTime.parse(row['atualizado_em'] as String),
      canceledAt: row['cancelado_em'] == null
          ? null
          : DateTime.parse(row['cancelado_em'] as String),
    );
  }

  PaymentMethod? _parsePaymentMethod(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return PaymentMethodX.fromDb(value);
  }

  int _toInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return 0;
  }

  DateTime _normalizeDay(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  String? _cleanNullable(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  String? _mergeNotes(String? current, String? next) {
    final currentValue = _cleanNullable(current);
    final nextValue = _cleanNullable(next);
    if (currentValue == null) {
      return nextValue;
    }
    if (nextValue == null) {
      return currentValue;
    }
    return '$currentValue\n$nextValue';
  }
}
