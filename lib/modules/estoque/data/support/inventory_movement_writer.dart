import 'package:sqflite/sqflite.dart';

import '../../../../app/core/database/table_names.dart';
import '../../../../app/core/utils/id_generator.dart';
import '../../domain/entities/inventory_movement.dart';
import 'inventory_balance_support.dart';

abstract final class InventoryMovementWriter {
  static Future<void> writeSaleOut(
    DatabaseExecutor db, {
    required Iterable<InventoryBalanceMutation> changes,
    required int referenceId,
    String referenceType = 'sale',
    String? notes,
    DateTime? createdAt,
  }) {
    return recordChanges(
      db,
      changes: changes,
      movementType: InventoryMovementType.saleOut,
      referenceType: referenceType,
      referenceId: referenceId,
      notes: notes,
      createdAt: createdAt,
    );
  }

  static Future<void> writeSaleCancelIn(
    DatabaseExecutor db, {
    required Iterable<InventoryBalanceMutation> changes,
    required int referenceId,
    String referenceType = 'sale',
    String? notes,
    DateTime? createdAt,
  }) {
    return recordChanges(
      db,
      changes: changes,
      movementType: InventoryMovementType.saleCancelIn,
      referenceType: referenceType,
      referenceId: referenceId,
      notes: notes,
      createdAt: createdAt,
    );
  }

  static Future<void> writeReturnIn(
    DatabaseExecutor db, {
    required Iterable<InventoryBalanceMutation> changes,
    required int referenceId,
    String referenceType = 'sale_return',
    String? notes,
    DateTime? createdAt,
  }) {
    return recordChanges(
      db,
      changes: changes,
      movementType: InventoryMovementType.returnIn,
      referenceType: referenceType,
      referenceId: referenceId,
      notes: notes,
      createdAt: createdAt,
    );
  }

  static Future<void> writeExchangeOut(
    DatabaseExecutor db, {
    required Iterable<InventoryBalanceMutation> changes,
    required int referenceId,
    String referenceType = 'sale_return',
    String? notes,
    DateTime? createdAt,
  }) {
    return recordChanges(
      db,
      changes: changes,
      movementType: InventoryMovementType.exchangeOut,
      referenceType: referenceType,
      referenceId: referenceId,
      notes: notes,
      createdAt: createdAt,
    );
  }

  static Future<void> writeCountAdjustmentIn(
    DatabaseExecutor db, {
    required Iterable<InventoryBalanceMutation> changes,
    required int referenceId,
    String referenceType = 'inventory_count_session',
    String? notes,
    DateTime? createdAt,
  }) {
    return recordChanges(
      db,
      changes: changes,
      movementType: InventoryMovementType.countAdjustmentIn,
      referenceType: referenceType,
      referenceId: referenceId,
      notes: notes,
      createdAt: createdAt,
    );
  }

  static Future<void> writeCountAdjustmentOut(
    DatabaseExecutor db, {
    required Iterable<InventoryBalanceMutation> changes,
    required int referenceId,
    String referenceType = 'inventory_count_session',
    String? notes,
    DateTime? createdAt,
  }) {
    return recordChanges(
      db,
      changes: changes,
      movementType: InventoryMovementType.countAdjustmentOut,
      referenceType: referenceType,
      referenceId: referenceId,
      notes: notes,
      createdAt: createdAt,
    );
  }

  static Future<void> recordChanges(
    DatabaseExecutor db, {
    required Iterable<InventoryBalanceMutation> changes,
    required InventoryMovementType movementType,
    required String referenceType,
    int? referenceId,
    String? reason,
    String? notes,
    DateTime? createdAt,
  }) async {
    final normalizedChanges = changes
        .where((change) => change.quantityDeltaMil != 0)
        .toList(growable: false);
    if (normalizedChanges.isEmpty) {
      return;
    }

    final createdAtIso = (createdAt ?? DateTime.now()).toIso8601String();
    final normalizedReason = _cleanNullable(reason);
    final normalizedNotes = _cleanNullable(notes);
    for (final change in normalizedChanges) {
      await db.insert(TableNames.inventoryMovements, {
        'uuid': IdGenerator.next(),
        'product_id': change.productId,
        'product_variant_id': change.productVariantId,
        'movement_type': movementType.storageValue,
        'quantity_delta_mil': change.quantityDeltaMil,
        'stock_before_mil': change.stockBeforeMil,
        'stock_after_mil': change.stockAfterMil,
        'reference_type': referenceType,
        'reference_id': referenceId,
        'reason': normalizedReason,
        'notes': normalizedNotes,
        'created_at': createdAtIso,
        'updated_at': createdAtIso,
      });
    }
  }

  static String? _cleanNullable(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
