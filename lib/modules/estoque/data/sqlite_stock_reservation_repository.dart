import 'package:sqflite/sqflite.dart';

import '../../../app/core/database/app_database.dart';
import '../../../app/core/database/table_names.dart';
import '../../../app/core/errors/app_exceptions.dart';
import '../../../app/core/utils/id_generator.dart';
import '../domain/entities/stock_reservation.dart';
import '../domain/repositories/stock_reservation_repository.dart';

class SqliteStockReservationRepository implements StockReservationRepository {
  const SqliteStockReservationRepository(this._appDatabase);

  final AppDatabase _appDatabase;

  @override
  Future<int> createReservation(StockReservationInput input) async {
    _validateInput(input);

    final database = await _appDatabase.database;
    final nowIso = DateTime.now().toIso8601String();

    try {
      return await database.insert(TableNames.estoqueReservas, {
        'uuid': IdGenerator.next(),
        'pedido_operacional_id': input.operationalOrderId,
        'item_pedido_operacional_id': input.operationalOrderItemId,
        'produto_id': input.productId,
        'produto_variante_id': input.productVariantId,
        'quantidade_mil': input.quantityMil,
        'status': StockReservationStatus.active.storageValue,
        'venda_id': null,
        'criado_em': nowIso,
        'atualizado_em': nowIso,
        'liberado_em': null,
        'convertido_em_venda_em': null,
      });
    } on DatabaseException catch (error) {
      throw ValidationException(
        'Ja existe reserva ativa para este item de pedido.',
        cause: error,
      );
    }
  }

  @override
  Future<List<StockReservation>> findActiveByOrderId(int orderId) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      TableNames.estoqueReservas,
      where: 'pedido_operacional_id = ? AND status = ?',
      whereArgs: [orderId, StockReservationStatus.active.storageValue],
      orderBy: 'id ASC',
    );
    return rows.map(_mapReservation).toList(growable: false);
  }

  @override
  Future<StockReservation?> findActiveByOrderItemId(int orderItemId) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      TableNames.estoqueReservas,
      where: 'item_pedido_operacional_id = ? AND status = ?',
      whereArgs: [orderItemId, StockReservationStatus.active.storageValue],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _mapReservation(rows.first);
  }

  @override
  Future<int> getReservedQuantityMil({
    required int productId,
    required int? productVariantId,
  }) async {
    final database = await _appDatabase.database;
    final rows = await database.rawQuery(
      '''
      SELECT COALESCE(SUM(quantidade_mil), 0) AS total
      FROM ${TableNames.estoqueReservas}
      WHERE produto_id = ?
        AND status = ?
        AND ${_variantWhereClause(productVariantId)}
      ''',
      <Object?>[
        productId,
        StockReservationStatus.active.storageValue,
        if (productVariantId != null) productVariantId,
      ],
    );
    return rows.first['total'] as int? ?? 0;
  }

  @override
  Future<Map<StockReservationProductKey, int>> getReservedQuantityByProductKeys(
    Iterable<StockReservationProductKey> keys,
  ) async {
    final result = <StockReservationProductKey, int>{};
    for (final key in keys) {
      result[key] = await getReservedQuantityMil(
        productId: key.productId,
        productVariantId: key.productVariantId,
      );
    }
    return result;
  }

  @override
  Future<void> releaseReservation(int reservationId) async {
    await _markStatus(
      reservationId,
      status: StockReservationStatus.released,
      timestampColumn: 'liberado_em',
      saleId: null,
    );
  }

  @override
  Future<void> releaseActiveByOrderId(int orderId) async {
    final database = await _appDatabase.database;
    await _releaseActiveByOrderId(
      database,
      orderId: orderId,
      nowIso: DateTime.now().toIso8601String(),
    );
  }

  @override
  Future<void> markConverted(int reservationId, int saleId) async {
    if (saleId <= 0) {
      throw const ValidationException('Venda invalida para converter reserva.');
    }
    await _markStatus(
      reservationId,
      status: StockReservationStatus.converted,
      timestampColumn: 'convertido_em_venda_em',
      saleId: saleId,
    );
  }

  @override
  Future<void> markActiveByOrderIdConverted(int orderId, int saleId) async {
    if (saleId <= 0) {
      throw const ValidationException('Venda invalida para converter reserva.');
    }
    final database = await _appDatabase.database;
    await _markActiveByOrderIdConverted(
      database,
      orderId: orderId,
      saleId: saleId,
      nowIso: DateTime.now().toIso8601String(),
    );
  }

  Future<void> _releaseActiveByOrderId(
    DatabaseExecutor database, {
    required int orderId,
    required String nowIso,
  }) async {
    await database.update(
      TableNames.estoqueReservas,
      {
        'status': StockReservationStatus.released.storageValue,
        'atualizado_em': nowIso,
        'liberado_em': nowIso,
      },
      where: 'pedido_operacional_id = ? AND status = ?',
      whereArgs: [orderId, StockReservationStatus.active.storageValue],
    );
  }

  Future<void> _markActiveByOrderIdConverted(
    DatabaseExecutor database, {
    required int orderId,
    required int saleId,
    required String nowIso,
  }) async {
    await database.update(
      TableNames.estoqueReservas,
      {
        'status': StockReservationStatus.converted.storageValue,
        'venda_id': saleId,
        'atualizado_em': nowIso,
        'convertido_em_venda_em': nowIso,
      },
      where: 'pedido_operacional_id = ? AND status = ?',
      whereArgs: [orderId, StockReservationStatus.active.storageValue],
    );
  }

  Future<void> _markStatus(
    int reservationId, {
    required StockReservationStatus status,
    required String timestampColumn,
    required int? saleId,
  }) async {
    final database = await _appDatabase.database;
    final nowIso = DateTime.now().toIso8601String();
    await database.update(
      TableNames.estoqueReservas,
      {
        'status': status.storageValue,
        'venda_id': saleId,
        'atualizado_em': nowIso,
        timestampColumn: nowIso,
      },
      where: 'id = ?',
      whereArgs: [reservationId],
    );
  }

  void _validateInput(StockReservationInput input) {
    if (input.quantityMil <= 0) {
      throw const ValidationException(
        'A quantidade reservada deve ser maior que zero.',
      );
    }
  }

  String _variantWhereClause(int? productVariantId) {
    if (productVariantId == null) {
      return 'produto_variante_id IS NULL';
    }
    return 'produto_variante_id = ?';
  }

  StockReservation _mapReservation(Map<String, Object?> row) {
    return StockReservation(
      id: row['id'] as int,
      uuid: row['uuid'] as String,
      operationalOrderId: row['pedido_operacional_id'] as int,
      operationalOrderItemId: row['item_pedido_operacional_id'] as int,
      productId: row['produto_id'] as int,
      productVariantId: row['produto_variante_id'] as int?,
      quantityMil: row['quantidade_mil'] as int,
      status: StockReservationStatusX.fromStorage(row['status'] as String),
      saleId: row['venda_id'] as int?,
      createdAt: DateTime.parse(row['criado_em'] as String),
      updatedAt: DateTime.parse(row['atualizado_em'] as String),
      releasedAt: _parseDateTime(row['liberado_em']),
      convertedToSaleAt: _parseDateTime(row['convertido_em_venda_em']),
    );
  }

  DateTime? _parseDateTime(Object? value) {
    if (value == null) {
      return null;
    }
    final raw = value.toString().trim();
    if (raw.isEmpty) {
      return null;
    }
    return DateTime.parse(raw);
  }
}
