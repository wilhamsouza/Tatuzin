import '../../../app/core/database/app_database.dart';
import '../../../app/core/database/table_names.dart';
import '../../../app/core/errors/app_exceptions.dart';
import '../domain/entities/stock_availability.dart';
import '../domain/entities/stock_reservation.dart';
import '../domain/repositories/stock_availability_repository.dart';

class SqliteStockAvailabilityRepository implements StockAvailabilityRepository {
  const SqliteStockAvailabilityRepository(this._appDatabase);

  final AppDatabase _appDatabase;

  @override
  Future<StockAvailability> getAvailability({
    required int productId,
    required int? productVariantId,
  }) async {
    final physicalQuantityMil = productVariantId == null
        ? await _loadProductPhysicalQuantityMil(productId)
        : await _loadVariantPhysicalQuantityMil(
            productId: productId,
            productVariantId: productVariantId,
          );
    final reservedQuantityMil = await _loadReservedQuantityMil(
      productId: productId,
      productVariantId: productVariantId,
    );

    return StockAvailability(
      productId: productId,
      productVariantId: productVariantId,
      physicalQuantityMil: physicalQuantityMil,
      reservedQuantityMil: reservedQuantityMil,
    );
  }

  @override
  Future<Map<StockReservationProductKey, StockAvailability>>
  getAvailabilityByProductKeys(
    Iterable<StockReservationProductKey> keys,
  ) async {
    final result = <StockReservationProductKey, StockAvailability>{};
    for (final key in keys) {
      result[key] = await getAvailability(
        productId: key.productId,
        productVariantId: key.productVariantId,
      );
    }
    return result;
  }

  Future<int> _loadProductPhysicalQuantityMil(int productId) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      TableNames.produtos,
      columns: const ['estoque_mil'],
      where: 'id = ?',
      whereArgs: [productId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw ValidationException('Produto #$productId nao encontrado.');
    }
    return rows.first['estoque_mil'] as int? ?? 0;
  }

  Future<int> _loadVariantPhysicalQuantityMil({
    required int productId,
    required int productVariantId,
  }) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      TableNames.produtoVariantes,
      columns: const ['estoque_mil'],
      where: 'id = ? AND produto_id = ?',
      whereArgs: [productVariantId, productId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw ValidationException(
        'Variante #$productVariantId do produto #$productId nao encontrada.',
      );
    }
    return rows.first['estoque_mil'] as int? ?? 0;
  }

  Future<int> _loadReservedQuantityMil({
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
        AND ${productVariantId == null ? 'produto_variante_id IS NULL' : 'produto_variante_id = ?'}
      ''',
      <Object?>[
        productId,
        StockReservationStatus.active.storageValue,
        if (productVariantId != null) productVariantId,
      ],
    );
    return rows.first['total'] as int? ?? 0;
  }
}
