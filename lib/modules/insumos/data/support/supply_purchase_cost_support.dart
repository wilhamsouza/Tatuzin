import 'package:sqflite/sqflite.dart';

import '../../../../app/core/database/table_names.dart';
import '../../../../app/core/sync/sqlite_sync_metadata_repository.dart';
import '../../../../app/core/sync/sqlite_sync_queue_repository.dart';
import '../../domain/entities/supply_cost_history_entry.dart';
import 'supply_cost_history_support.dart';
import 'supply_sync_mutation_support.dart';
import 'supply_linked_product_support.dart';

abstract final class SupplyPurchaseCostSupport {
  static Future<void> refreshSupplyPricing(
    DatabaseExecutor txn, {
    required Iterable<int> supplyIds,
    required DateTime changedAt,
    required SupplyCostHistoryEventType eventType,
    required SqliteSyncMetadataRepository syncMetadataRepository,
    required SqliteSyncQueueRepository syncQueueRepository,
  }) async {
    final normalizedSupplyIds = supplyIds.toSet().toList(growable: false);
    if (normalizedSupplyIds.isEmpty) {
      return;
    }

    for (final supplyId in normalizedSupplyIds) {
      final changed = await _recomputeSupplyPricing(
        txn,
        supplyId: supplyId,
        changedAt: changedAt,
        eventType: eventType,
      );
      await SupplySyncMutationSupport.markSuppliesForSync(
        txn,
        supplyIds: [supplyId],
        changedAt: changedAt,
        syncMetadataRepository: syncMetadataRepository,
        syncQueueRepository: syncQueueRepository,
      );
      if (changed) {
        await SupplyLinkedProductSupport.recalculateLinkedProducts(
          txn,
          supplyIds: [supplyId],
          changedAt: changedAt,
          syncMetadataRepository: syncMetadataRepository,
          syncQueueRepository: syncQueueRepository,
        );
      }
    }
  }

  static Future<bool> _recomputeSupplyPricing(
    DatabaseExecutor txn, {
    required int supplyId,
    required DateTime changedAt,
    required SupplyCostHistoryEventType eventType,
  }) async {
    final supplyRows = await txn.query(
      TableNames.supplies,
      columns: const [
        'id',
        'purchase_unit_type',
        'conversion_factor',
        'last_purchase_price_cents',
        'average_purchase_price_cents',
      ],
      where: 'id = ?',
      whereArgs: [supplyId],
      limit: 1,
    );
    if (supplyRows.isEmpty) {
      return false;
    }

    final currentRow = supplyRows.first;
    final purchaseRows = await txn.rawQuery(
      '''
      SELECT
        ic.id AS purchase_item_id,
        ic.compra_id AS purchase_id,
        ic.custo_unitario_centavos AS unit_cost_cents,
        ic.quantidade_mil AS quantity_mil,
        c.data_compra AS purchased_at
      FROM ${TableNames.itensCompra} ic
      INNER JOIN ${TableNames.compras} c
        ON c.id = ic.compra_id
      WHERE ic.item_type = 'supply'
        AND ic.supply_id = ?
        AND c.status != 'cancelada'
      ORDER BY c.data_compra DESC, c.id DESC, ic.id DESC
    ''',
      [supplyId],
    );

    late final SupplyCostSnapshot nextSnapshot;
    int? sourcePurchaseId;
    int? sourcePurchaseItemId;
    String? historyNotes;
    String? changeSummary;

    if (purchaseRows.isNotEmpty) {
      final latestRow = purchaseRows.first;
      final totalWeightedCost = purchaseRows.fold<int>(
        0,
        (total, row) =>
            total +
            ((row['quantity_mil'] as int? ?? 0) *
                (row['unit_cost_cents'] as int? ?? 0)),
      );
      final totalQuantityMil = purchaseRows.fold<int>(
        0,
        (total, row) => total + (row['quantity_mil'] as int? ?? 0),
      );
      nextSnapshot = SupplyCostSnapshot(
        lastPurchasePriceCents: latestRow['unit_cost_cents'] as int? ?? 0,
        averagePurchasePriceCents: totalQuantityMil <= 0
            ? null
            : ((totalWeightedCost / totalQuantityMil)).round(),
        purchaseUnitType: currentRow['purchase_unit_type'] as String? ?? 'un',
        conversionFactor: currentRow['conversion_factor'] as int? ?? 1,
      );
      sourcePurchaseId = latestRow['purchase_id'] as int?;
      sourcePurchaseItemId = latestRow['purchase_item_id'] as int?;
      historyNotes = _historyNotesForPurchaseEvent(
        eventType,
        purchaseId: sourcePurchaseId,
      );
      changeSummary = _changeSummaryForPurchaseEvent(eventType, changed: true);
    } else {
      final fallbackManual =
          await SupplyCostHistorySupport.findLatestManualSnapshot(
            txn,
            supplyId: supplyId,
          );
      nextSnapshot =
          fallbackManual ??
          SupplyCostSnapshot(
            lastPurchasePriceCents: 0,
            averagePurchasePriceCents: null,
            purchaseUnitType:
                currentRow['purchase_unit_type'] as String? ?? 'un',
            conversionFactor: currentRow['conversion_factor'] as int? ?? 1,
          );
      historyNotes = fallbackManual == null
          ? 'Sem compras validas para compor o preco do insumo.'
          : 'Preco retornou para a ultima referencia manual apos reprocessar as compras.';
      changeSummary = _changeSummaryForPurchaseEvent(
        eventType,
        changed: true,
        returnedToManualReference: fallbackManual != null,
      );
    }

    final currentLastPrice =
        currentRow['last_purchase_price_cents'] as int? ?? 0;
    final currentAveragePrice =
        currentRow['average_purchase_price_cents'] as int?;
    final changed =
        currentLastPrice != nextSnapshot.lastPurchasePriceCents ||
        currentAveragePrice != nextSnapshot.averagePurchasePriceCents;

    if (changed) {
      await txn.update(
        TableNames.supplies,
        {
          'last_purchase_price_cents': nextSnapshot.lastPurchasePriceCents,
          'average_purchase_price_cents':
              nextSnapshot.averagePurchasePriceCents,
          'updated_at': changedAt.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [supplyId],
      );
    }

    await SupplyCostHistorySupport.recordPurchaseSnapshot(
      txn,
      supplyId: supplyId,
      purchaseId: sourcePurchaseId,
      purchaseItemId: sourcePurchaseItemId,
      snapshot: nextSnapshot,
      changedAt: changedAt,
      eventType: eventType,
      changeSummary: changeSummary,
      notes: historyNotes,
    );
    return changed;
  }

  static String _changeSummaryForPurchaseEvent(
    SupplyCostHistoryEventType eventType, {
    required bool changed,
    bool returnedToManualReference = false,
  }) {
    final suffix = changed
        ? returnedToManualReference
              ? 'O custo automatico voltou para a ultima referencia manual.'
              : 'O custo automatico do insumo foi reprocessado.'
        : 'O evento foi auditado sem alterar o custo automatico vigente.';
    return switch (eventType) {
      SupplyCostHistoryEventType.purchaseCreated =>
        'Compra com insumo criada. $suffix',
      SupplyCostHistoryEventType.purchaseCanceled =>
        'Compra com insumo cancelada. $suffix',
      SupplyCostHistoryEventType.purchaseUpdated =>
        'Compra com insumo atualizada. $suffix',
      _ => suffix,
    };
  }

  static String _historyNotesForPurchaseEvent(
    SupplyCostHistoryEventType eventType, {
    required int? purchaseId,
  }) {
    final purchaseLabel = purchaseId == null ? '' : ' Compra #$purchaseId.';
    return switch (eventType) {
      SupplyCostHistoryEventType.purchaseCreated =>
        'Preco derivado automaticamente apos registrar uma compra.$purchaseLabel',
      SupplyCostHistoryEventType.purchaseCanceled =>
        'Preco reprocessado automaticamente apos cancelar uma compra.$purchaseLabel',
      SupplyCostHistoryEventType.purchaseUpdated =>
        'Preco reprocessado automaticamente apos editar uma compra.$purchaseLabel',
      _ =>
        'Preco derivado automaticamente do historico de compras.$purchaseLabel',
    };
  }
}
