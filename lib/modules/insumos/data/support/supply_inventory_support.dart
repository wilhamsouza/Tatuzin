import 'package:sqflite/sqflite.dart';

import '../../../../app/core/database/table_names.dart';
import '../../../../app/core/utils/id_generator.dart';
import '../../../carrinho/domain/entities/cart_item.dart';
import '../../../compras/domain/entities/purchase_item.dart';
import '../../domain/entities/supply_inventory.dart';
import '../../domain/services/supply_inventory_math.dart';

abstract final class SupplyInventorySupport {
  static Future<Set<int>> replacePurchaseEntries(
    DatabaseExecutor txn, {
    required String purchaseUuid,
    String? purchaseRemoteId,
    required Iterable<PurchaseItem> items,
    required DateTime occurredAt,
  }) async {
    final previousSupplyIds = await _findSupplyIdsForSource(
      txn,
      sourceType: SupplyInventorySourceType.purchase,
      sourceLocalUuid: purchaseUuid,
    );

    await txn.delete(
      TableNames.supplyInventoryMovements,
      where: 'source_type = ? AND source_local_uuid = ?',
      whereArgs: [
        SupplyInventorySourceType.purchase.storageValue,
        purchaseUuid,
      ],
    );

    final groupedEntries = await _groupPurchaseEntries(txn, items: items);
    for (final entry in groupedEntries.values) {
      await txn.insert(
        TableNames.supplyInventoryMovements,
        _movementMap(
          uuid: IdGenerator.next(),
          remoteId: null,
          supplyId: entry.supplyId,
          movementType: SupplyInventoryMovementType.inbound,
          sourceType: SupplyInventorySourceType.purchase,
          sourceLocalUuid: purchaseUuid,
          sourceRemoteId: purchaseRemoteId,
          dedupeKey: 'purchase:$purchaseUuid:entry:${entry.supplyId}',
          quantityDeltaMil: entry.quantityDeltaMil,
          unitType: entry.unitType,
          notes: 'Entrada operacional gerada pela compra.',
          occurredAt: occurredAt,
        ),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    final affectedSupplyIds = <int>{
      ...previousSupplyIds,
      ...groupedEntries.keys,
    };
    await rebuildSupplyStockCache(
      txn,
      supplyIds: affectedSupplyIds,
      changedAt: occurredAt,
    );
    return affectedSupplyIds;
  }

  static Future<Set<int>> cancelPurchaseEntries(
    DatabaseExecutor txn, {
    required String purchaseUuid,
    String? purchaseRemoteId,
    required DateTime occurredAt,
  }) async {
    final entryRows = await txn.query(
      TableNames.supplyInventoryMovements,
      where: 'source_type = ? AND source_local_uuid = ?',
      whereArgs: [
        SupplyInventorySourceType.purchase.storageValue,
        purchaseUuid,
      ],
    );
    if (entryRows.isEmpty) {
      return const <int>{};
    }

    final affectedSupplyIds = <int>{};
    for (final row in entryRows) {
      final supplyId = row['supply_id'] as int;
      affectedSupplyIds.add(supplyId);
      await txn.insert(
        TableNames.supplyInventoryMovements,
        _movementMap(
          uuid: IdGenerator.next(),
          remoteId: null,
          supplyId: supplyId,
          movementType: SupplyInventoryMovementType.reversal,
          sourceType: SupplyInventorySourceType.purchaseCancel,
          sourceLocalUuid: purchaseUuid,
          sourceRemoteId: purchaseRemoteId,
          dedupeKey: 'purchase:$purchaseUuid:cancel:$supplyId',
          quantityDeltaMil: -((row['quantity_delta_mil'] as int?) ?? 0),
          unitType: row['unit_type'] as String? ?? 'un',
          notes: 'Estorno operacional gerado pelo cancelamento da compra.',
          occurredAt: occurredAt,
        ),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    await rebuildSupplyStockCache(
      txn,
      supplyIds: affectedSupplyIds,
      changedAt: occurredAt,
    );
    return affectedSupplyIds;
  }

  static Future<SupplySaleConsumptionResult> recordSaleConsumption(
    DatabaseExecutor txn, {
    required String saleUuid,
    String? saleRemoteId,
    required Iterable<CartItem> items,
    required DateTime occurredAt,
  }) async {
    if (await _hasSourceMovement(
      txn,
      sourceType: SupplyInventorySourceType.saleCancel,
      sourceLocalUuid: saleUuid,
    )) {
      return const SupplySaleConsumptionResult.empty();
    }

    final groupedEntries = await _groupSaleConsumption(txn, items: items);
    final summaryLines = await _buildSaleConsumptionSummaryLines(
      txn,
      items: items,
    );

    for (final entry in groupedEntries.values) {
      await txn.insert(
        TableNames.supplyInventoryMovements,
        _movementMap(
          uuid: IdGenerator.next(),
          remoteId: null,
          supplyId: entry.supplyId,
          movementType: SupplyInventoryMovementType.outbound,
          sourceType: SupplyInventorySourceType.sale,
          sourceLocalUuid: saleUuid,
          sourceRemoteId: saleRemoteId,
          dedupeKey: 'sale:$saleUuid:consume:${entry.supplyId}',
          quantityDeltaMil: -entry.quantityDeltaMil,
          unitType: entry.unitType,
          notes: 'Consumo operacional gerado pela venda.',
          occurredAt: occurredAt,
        ),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    if (groupedEntries.isNotEmpty) {
      await rebuildSupplyStockCache(
        txn,
        supplyIds: groupedEntries.keys,
        changedAt: occurredAt,
      );
    }
    return SupplySaleConsumptionResult(
      lines: summaryLines,
      affectedSupplyIds: groupedEntries.keys.toList(growable: false),
    );
  }

  static Future<Set<int>> reverseSaleConsumption(
    DatabaseExecutor txn, {
    required String saleUuid,
    String? saleRemoteId,
    required DateTime occurredAt,
  }) async {
    final entryRows = await txn.query(
      TableNames.supplyInventoryMovements,
      where: 'source_type = ? AND source_local_uuid = ?',
      whereArgs: [SupplyInventorySourceType.sale.storageValue, saleUuid],
    );
    if (entryRows.isEmpty) {
      return const <int>{};
    }

    final affectedSupplyIds = <int>{};
    for (final row in entryRows) {
      final supplyId = row['supply_id'] as int;
      affectedSupplyIds.add(supplyId);
      await txn.insert(
        TableNames.supplyInventoryMovements,
        _movementMap(
          uuid: IdGenerator.next(),
          remoteId: null,
          supplyId: supplyId,
          movementType: SupplyInventoryMovementType.reversal,
          sourceType: SupplyInventorySourceType.saleCancel,
          sourceLocalUuid: saleUuid,
          sourceRemoteId: saleRemoteId,
          dedupeKey: 'sale:$saleUuid:cancel:$supplyId',
          quantityDeltaMil: -((row['quantity_delta_mil'] as int?) ?? 0),
          unitType: row['unit_type'] as String? ?? 'un',
          notes: 'Estorno operacional gerado pelo cancelamento da venda.',
          occurredAt: occurredAt,
        ),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    await rebuildSupplyStockCache(
      txn,
      supplyIds: affectedSupplyIds,
      changedAt: occurredAt,
    );
    return affectedSupplyIds;
  }

  static Future<SupplyInventoryBaselineSeedResult> seedLegacyBaselineIfNeeded(
    DatabaseExecutor txn, {
    required int supplyId,
    required String supplyUuid,
    required int? legacyStockMil,
    required DateTime occurredAt,
    String? notes,
  }) async {
    final normalizedSupplyUuid = supplyUuid.trim();
    if (legacyStockMil == null ||
        legacyStockMil < 0 ||
        normalizedSupplyUuid.isEmpty) {
      return SupplyInventoryBaselineSeedResult(
        supplyId: supplyId,
        status: SupplyInventoryBaselineSeedStatus.skippedInvalid,
      );
    }

    final existingSeedCount = await _countMovementsForSupply(
      txn,
      supplyId: supplyId,
      sourceType: SupplyInventorySourceType.migrationSeed,
    );
    if (existingSeedCount > 0) {
      return SupplyInventoryBaselineSeedResult(
        supplyId: supplyId,
        status: SupplyInventoryBaselineSeedStatus.skippedAlreadyExists,
      );
    }

    final existingMovementCount = await _countMovementsForSupply(
      txn,
      supplyId: supplyId,
    );
    if (existingMovementCount > 0) {
      return SupplyInventoryBaselineSeedResult(
        supplyId: supplyId,
        status: SupplyInventoryBaselineSeedStatus.skippedHasMovements,
      );
    }

    await txn.insert(
      TableNames.supplyInventoryMovements,
      _movementMap(
        uuid: IdGenerator.next(),
        remoteId: null,
        supplyId: supplyId,
        movementType: SupplyInventoryMovementType.adjustment,
        sourceType: SupplyInventorySourceType.migrationSeed,
        sourceLocalUuid: normalizedSupplyUuid,
        sourceRemoteId: null,
        dedupeKey: 'migration_seed:$normalizedSupplyUuid',
        quantityDeltaMil: legacyStockMil,
        unitType: await _loadSupplyUnitType(txn, supplyId),
        notes: notes ?? 'Saldo inicial migrado do estoque legado.',
        occurredAt: occurredAt,
      ),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    await rebuildSupplyStockCache(
      txn,
      supplyIds: [supplyId],
      changedAt: occurredAt,
    );

    return SupplyInventoryBaselineSeedResult(
      supplyId: supplyId,
      status: SupplyInventoryBaselineSeedStatus.created,
    );
  }

  static Future<void> applyManualStockTarget(
    DatabaseExecutor txn, {
    required int supplyId,
    required String supplyUuid,
    required int? targetStockMil,
    required DateTime occurredAt,
    String? notes,
  }) async {
    if (targetStockMil == null) {
      return;
    }

    final currentBalanceMil = await currentBalanceForSupply(
      txn,
      supplyId: supplyId,
    );
    final deltaMil = targetStockMil - (currentBalanceMil ?? 0);
    if (deltaMil == 0 && currentBalanceMil != null) {
      return;
    }

    await txn.insert(
      TableNames.supplyInventoryMovements,
      _movementMap(
        uuid: IdGenerator.next(),
        remoteId: null,
        supplyId: supplyId,
        movementType: SupplyInventoryMovementType.adjustment,
        sourceType: SupplyInventorySourceType.manualAdjustment,
        sourceLocalUuid: supplyUuid,
        sourceRemoteId: null,
        dedupeKey:
            'manual_adjustment:$supplyUuid:${occurredAt.microsecondsSinceEpoch}',
        quantityDeltaMil: deltaMil,
        unitType: await _loadSupplyUnitType(txn, supplyId),
        notes: notes ?? 'Saldo operacional ajustado manualmente.',
        occurredAt: occurredAt,
      ),
    );

    await rebuildSupplyStockCache(
      txn,
      supplyIds: [supplyId],
      changedAt: occurredAt,
    );
  }

  static Future<SupplyInventoryConsistencyReport> verifyInventoryConsistency(
    DatabaseExecutor txn, {
    Iterable<int>? supplyIds,
    required DateTime checkedAt,
    bool repair = true,
  }) async {
    final normalizedIds = supplyIds?.toSet().toList(growable: false);
    final supplyRows = await _loadSupplyRows(txn, supplyIds: normalizedIds);
    if (supplyRows.isEmpty) {
      return SupplyInventoryConsistencyReport(
        checkedAt: checkedAt,
        checkedSupplyCount: 0,
        issues: const <SupplyInventoryConsistencyIssue>[],
      );
    }

    final balanceBySupplyId = await _loadLedgerBalanceMap(
      txn,
      supplyIds: supplyRows.map((row) => row['id'] as int).toList(),
    );

    final issues = <SupplyInventoryConsistencyIssue>[];
    final driftedSupplyIds = <int>[];
    for (final row in supplyRows) {
      final supplyId = row['id'] as int;
      final cachedStockMil = row['current_stock_mil'] as int?;
      final ledgerStockMil = balanceBySupplyId[supplyId];
      if (cachedStockMil == ledgerStockMil) {
        continue;
      }

      driftedSupplyIds.add(supplyId);
      issues.add(
        SupplyInventoryConsistencyIssue(
          supplyId: supplyId,
          supplyName: row['name'] as String? ?? 'Insumo',
          cachedStockMil: cachedStockMil,
          ledgerStockMil: ledgerStockMil,
          repaired: repair,
        ),
      );
    }

    if (repair && driftedSupplyIds.isNotEmpty) {
      await rebuildSupplyStockCache(
        txn,
        supplyIds: driftedSupplyIds,
        changedAt: checkedAt,
      );
    }

    return SupplyInventoryConsistencyReport(
      checkedAt: checkedAt,
      checkedSupplyCount: supplyRows.length,
      issues: issues,
    );
  }

  static Future<int?> currentBalanceForSupply(
    DatabaseExecutor txn, {
    required int supplyId,
  }) async {
    final rows = await txn.rawQuery(
      '''
      SELECT
        COUNT(*) AS total_movements,
        COALESCE(SUM(quantity_delta_mil), 0) AS balance_mil
      FROM ${TableNames.supplyInventoryMovements}
      WHERE supply_id = ?
      ''',
      [supplyId],
    );
    if (rows.isEmpty) {
      return null;
    }

    final totalMovements = rows.first['total_movements'] as int? ?? 0;
    if (totalMovements <= 0) {
      return null;
    }
    return rows.first['balance_mil'] as int? ?? 0;
  }

  static Future<bool> hasAnyMovement(
    DatabaseExecutor txn, {
    required int supplyId,
  }) async {
    final rows = await txn.rawQuery(
      '''
      SELECT COUNT(*) AS total
      FROM ${TableNames.supplyInventoryMovements}
      WHERE supply_id = ?
      ''',
      [supplyId],
    );
    return (rows.first['total'] as int? ?? 0) > 0;
  }

  static Future<void> rebuildSupplyStockCache(
    DatabaseExecutor txn, {
    required Iterable<int> supplyIds,
    required DateTime changedAt,
  }) async {
    final normalizedIds = supplyIds.toSet().toList(growable: false);
    if (normalizedIds.isEmpty) {
      return;
    }

    final placeholders = List.filled(normalizedIds.length, '?').join(',');
    final balanceRows = await txn.rawQuery('''
      SELECT
        supply_id,
        COUNT(*) AS total_movements,
        COALESCE(SUM(quantity_delta_mil), 0) AS balance_mil
      FROM ${TableNames.supplyInventoryMovements}
      WHERE supply_id IN ($placeholders)
      GROUP BY supply_id
      ''', normalizedIds);

    final balanceBySupplyId = <int, int?>{};
    for (final row in balanceRows) {
      final supplyId = row['supply_id'] as int;
      final totalMovements = row['total_movements'] as int? ?? 0;
      balanceBySupplyId[supplyId] = totalMovements <= 0
          ? null
          : row['balance_mil'] as int? ?? 0;
    }

    final changedAtIso = changedAt.toIso8601String();
    for (final supplyId in normalizedIds) {
      await txn.update(
        TableNames.supplies,
        {
          'current_stock_mil': balanceBySupplyId[supplyId],
          'updated_at': changedAtIso,
        },
        where: 'id = ?',
        whereArgs: [supplyId],
      );
    }
  }

  static Future<Set<int>> _findSupplyIdsForSource(
    DatabaseExecutor txn, {
    required SupplyInventorySourceType sourceType,
    required String sourceLocalUuid,
  }) async {
    final rows = await txn.query(
      TableNames.supplyInventoryMovements,
      columns: const ['supply_id'],
      where: 'source_type = ? AND source_local_uuid = ?',
      whereArgs: [sourceType.storageValue, sourceLocalUuid],
    );
    return rows.map((row) => row['supply_id']).whereType<int>().toSet();
  }

  static Future<bool> _hasSourceMovement(
    DatabaseExecutor txn, {
    required SupplyInventorySourceType sourceType,
    required String sourceLocalUuid,
  }) async {
    final rows = await txn.rawQuery(
      '''
      SELECT COUNT(*) AS total
      FROM ${TableNames.supplyInventoryMovements}
      WHERE source_type = ? AND source_local_uuid = ?
      ''',
      [sourceType.storageValue, sourceLocalUuid],
    );
    return (rows.first['total'] as int? ?? 0) > 0;
  }

  static Future<int> _countMovementsForSupply(
    DatabaseExecutor txn, {
    required int supplyId,
    SupplyInventorySourceType? sourceType,
  }) async {
    final rows = await txn.rawQuery(
      '''
      SELECT COUNT(*) AS total
      FROM ${TableNames.supplyInventoryMovements}
      WHERE supply_id = ?
        ${sourceType == null ? '' : 'AND source_type = ?'}
      ''',
      sourceType == null ? [supplyId] : [supplyId, sourceType.storageValue],
    );
    return rows.first['total'] as int? ?? 0;
  }

  static Future<List<Map<String, Object?>>> _loadSupplyRows(
    DatabaseExecutor txn, {
    required List<int>? supplyIds,
  }) async {
    if (supplyIds != null && supplyIds.isEmpty) {
      return const <Map<String, Object?>>[];
    }

    if (supplyIds == null) {
      return txn.query(
        TableNames.supplies,
        columns: const ['id', 'name', 'current_stock_mil'],
      );
    }

    final placeholders = List.filled(supplyIds.length, '?').join(',');
    return txn.rawQuery('''
      SELECT id, name, current_stock_mil
      FROM ${TableNames.supplies}
      WHERE id IN ($placeholders)
      ''', supplyIds);
  }

  static Future<Map<int, int?>> _loadLedgerBalanceMap(
    DatabaseExecutor txn, {
    required List<int> supplyIds,
  }) async {
    if (supplyIds.isEmpty) {
      return const <int, int?>{};
    }

    final placeholders = List.filled(supplyIds.length, '?').join(',');
    final rows = await txn.rawQuery('''
      SELECT
        supply_id,
        COUNT(*) AS total_movements,
        COALESCE(SUM(quantity_delta_mil), 0) AS balance_mil
      FROM ${TableNames.supplyInventoryMovements}
      WHERE supply_id IN ($placeholders)
      GROUP BY supply_id
      ''', supplyIds);

    final result = <int, int?>{
      for (final supplyId in supplyIds) supplyId: null,
    };
    for (final row in rows) {
      final supplyId = row['supply_id'] as int;
      final totalMovements = row['total_movements'] as int? ?? 0;
      result[supplyId] = totalMovements <= 0
          ? null
          : row['balance_mil'] as int? ?? 0;
    }
    return result;
  }

  static Future<Map<int, _MovementDraft>> _groupPurchaseEntries(
    DatabaseExecutor txn, {
    required Iterable<PurchaseItem> items,
  }) async {
    final supplyIds = items
        .where((item) => item.isSupply && item.supplyId != null)
        .map((item) => item.supplyId!)
        .toSet()
        .toList(growable: false);
    if (supplyIds.isEmpty) {
      return const <int, _MovementDraft>{};
    }

    final supplyInfo = await _loadSupplyInfo(txn, supplyIds);
    final grouped = <int, _MovementDraft>{};
    for (final item in items.where((entry) => entry.isSupply)) {
      final supplyId = item.supplyId;
      if (supplyId == null) {
        continue;
      }
      final info = supplyInfo[supplyId];
      if (info == null) {
        continue;
      }

      final quantityDeltaMil =
          SupplyInventoryMath.purchaseToOperationalQuantityMil(
            purchaseQuantityMil: item.quantityMil,
            conversionFactor: info.conversionFactor,
          );
      grouped.update(
        supplyId,
        (current) => current.copyWith(
          quantityDeltaMil: current.quantityDeltaMil + quantityDeltaMil,
        ),
        ifAbsent: () => _MovementDraft(
          supplyId: supplyId,
          quantityDeltaMil: quantityDeltaMil,
          unitType: info.unitType,
        ),
      );
    }
    return grouped;
  }

  static Future<Map<int, _MovementDraft>> _groupSaleConsumption(
    DatabaseExecutor txn, {
    required Iterable<CartItem> items,
  }) async {
    final productIds = items
        .map((item) => item.productId)
        .toSet()
        .toList(growable: false);
    if (productIds.isEmpty) {
      return const <int, _MovementDraft>{};
    }

    final placeholders = List.filled(productIds.length, '?').join(',');
    final recipeRows = await txn.rawQuery('''
      SELECT
        pri.product_id,
        pri.supply_id,
        pri.quantity_used_mil,
        pri.waste_basis_points,
        s.unit_type AS supply_unit_type
      FROM ${TableNames.productRecipeItems} pri
      INNER JOIN ${TableNames.supplies} s
        ON s.id = pri.supply_id
      WHERE pri.product_id IN ($placeholders)
      ORDER BY pri.id ASC
      ''', productIds);

    final recipeByProductId = <int, List<Map<String, Object?>>>{};
    for (final row in recipeRows) {
      final productId = row['product_id'] as int;
      recipeByProductId.putIfAbsent(productId, () => <Map<String, Object?>>[]);
      recipeByProductId[productId]!.add(row);
    }

    final grouped = <int, _MovementDraft>{};
    for (final item in items) {
      final recipeItems = recipeByProductId[item.productId];
      if (recipeItems == null || recipeItems.isEmpty) {
        continue;
      }

      for (final recipeRow in recipeItems) {
        final supplyId = recipeRow['supply_id'] as int;
        final quantityDeltaMil = SupplyInventoryMath.saleConsumptionQuantityMil(
          quantityUsedMil: recipeRow['quantity_used_mil'] as int? ?? 0,
          soldQuantityMil: item.quantityMil,
          wasteBasisPoints: recipeRow['waste_basis_points'] as int? ?? 0,
        );
        grouped.update(
          supplyId,
          (current) => current.copyWith(
            quantityDeltaMil: current.quantityDeltaMil + quantityDeltaMil,
          ),
          ifAbsent: () => _MovementDraft(
            supplyId: supplyId,
            quantityDeltaMil: quantityDeltaMil,
            unitType: recipeRow['supply_unit_type'] as String? ?? 'un',
          ),
        );
      }
    }

    grouped.removeWhere((_, value) => value.quantityDeltaMil == 0);
    return grouped;
  }

  static Future<List<SupplySaleConsumptionLine>>
  _buildSaleConsumptionSummaryLines(
    DatabaseExecutor txn, {
    required Iterable<CartItem> items,
  }) async {
    final normalizedItems = items.toList(growable: false);
    if (normalizedItems.isEmpty) {
      return const <SupplySaleConsumptionLine>[];
    }

    final productIds = normalizedItems
        .map((item) => item.productId)
        .toSet()
        .toList(growable: false);
    final placeholders = List.filled(productIds.length, '?').join(',');
    final recipeRows = await txn.rawQuery('''
      SELECT DISTINCT product_id
      FROM ${TableNames.productRecipeItems}
      WHERE product_id IN ($placeholders)
      ''', productIds);
    final recipeProductIds = recipeRows
        .map((row) => row['product_id'])
        .whereType<int>()
        .toSet();

    return normalizedItems
        .map(
          (item) => SupplySaleConsumptionLine(
            productId: item.productId,
            productName: item.productName,
            quantityMil: item.quantityMil,
            status: recipeProductIds.contains(item.productId)
                ? SupplySaleConsumptionLineStatus.appliedFromRecipe
                : SupplySaleConsumptionLineStatus.skippedWithoutRecipe,
          ),
        )
        .toList(growable: false);
  }

  static Future<Map<int, _SupplyInventoryInfo>> _loadSupplyInfo(
    DatabaseExecutor txn,
    List<int> supplyIds,
  ) async {
    final placeholders = List.filled(supplyIds.length, '?').join(',');
    final rows = await txn.rawQuery('''
      SELECT
        id,
        unit_type,
        conversion_factor
      FROM ${TableNames.supplies}
      WHERE id IN ($placeholders)
      ''', supplyIds);
    return {
      for (final row in rows)
        row['id'] as int: _SupplyInventoryInfo(
          unitType: row['unit_type'] as String? ?? 'un',
          conversionFactor: row['conversion_factor'] as int? ?? 1,
        ),
    };
  }

  static Future<String> _loadSupplyUnitType(
    DatabaseExecutor txn,
    int supplyId,
  ) async {
    final rows = await txn.query(
      TableNames.supplies,
      columns: const ['unit_type'],
      where: 'id = ?',
      whereArgs: [supplyId],
      limit: 1,
    );
    return rows.isEmpty ? 'un' : rows.first['unit_type'] as String? ?? 'un';
  }

  static Map<String, Object?> _movementMap({
    required String uuid,
    required String? remoteId,
    required int supplyId,
    required SupplyInventoryMovementType movementType,
    required SupplyInventorySourceType sourceType,
    required String? sourceLocalUuid,
    required String? sourceRemoteId,
    required String dedupeKey,
    required int quantityDeltaMil,
    required String unitType,
    required String? notes,
    required DateTime occurredAt,
  }) {
    final occurredAtIso = occurredAt.toIso8601String();
    return {
      'uuid': uuid,
      'remote_id': remoteId,
      'supply_id': supplyId,
      'movement_type': movementType.storageValue,
      'source_type': sourceType.storageValue,
      'source_local_uuid': sourceLocalUuid,
      'source_remote_id': sourceRemoteId,
      'dedupe_key': dedupeKey,
      'quantity_delta_mil': quantityDeltaMil,
      'unit_type': unitType,
      'balance_after_mil': null,
      'notes': notes,
      'occurred_at': occurredAtIso,
      'created_at': occurredAtIso,
      'updated_at': occurredAtIso,
    };
  }
}

class _SupplyInventoryInfo {
  const _SupplyInventoryInfo({
    required this.unitType,
    required this.conversionFactor,
  });

  final String unitType;
  final int conversionFactor;
}

class _MovementDraft {
  const _MovementDraft({
    required this.supplyId,
    required this.quantityDeltaMil,
    required this.unitType,
  });

  final int supplyId;
  final int quantityDeltaMil;
  final String unitType;

  _MovementDraft copyWith({int? quantityDeltaMil}) {
    return _MovementDraft(
      supplyId: supplyId,
      quantityDeltaMil: quantityDeltaMil ?? this.quantityDeltaMil,
      unitType: unitType,
    );
  }
}
