import 'package:sqflite/sqflite.dart';

import '../../../../app/core/database/table_names.dart';
import '../../../../app/core/utils/id_generator.dart';
import '../../domain/entities/supply_cost_history_entry.dart';

class SupplyCostSnapshot {
  const SupplyCostSnapshot({
    required this.lastPurchasePriceCents,
    required this.averagePurchasePriceCents,
    required this.purchaseUnitType,
    required this.conversionFactor,
  });

  final int lastPurchasePriceCents;
  final int? averagePurchasePriceCents;
  final String purchaseUnitType;
  final int conversionFactor;
}

abstract final class SupplyCostHistorySupport {
  static Future<void> recordManualSnapshot(
    DatabaseExecutor txn, {
    required int supplyId,
    required SupplyCostSnapshot snapshot,
    required DateTime changedAt,
    required SupplyCostHistoryEventType eventType,
    String? changeSummary,
    String? notes,
  }) async {
    await _insertHistory(
      txn,
      supplyId: supplyId,
      purchaseId: null,
      purchaseItemId: null,
      source: SupplyCostHistorySource.manual,
      eventType: eventType,
      snapshot: snapshot,
      changeSummary: changeSummary,
      notes: notes,
      occurredAt: changedAt,
    );
  }

  static Future<void> recordPurchaseSnapshot(
    DatabaseExecutor txn, {
    required int supplyId,
    required int? purchaseId,
    required int? purchaseItemId,
    required SupplyCostSnapshot snapshot,
    required DateTime changedAt,
    required SupplyCostHistoryEventType eventType,
    String? changeSummary,
    String? notes,
  }) async {
    await _insertHistory(
      txn,
      supplyId: supplyId,
      purchaseId: purchaseId,
      purchaseItemId: purchaseItemId,
      source: SupplyCostHistorySource.purchase,
      eventType: eventType,
      snapshot: snapshot,
      changeSummary: changeSummary,
      notes: notes,
      occurredAt: changedAt,
    );
  }

  static Future<SupplyCostSnapshot?> findLatestManualSnapshot(
    DatabaseExecutor txn, {
    required int supplyId,
  }) async {
    final rows = await txn.query(
      TableNames.supplyCostHistory,
      columns: const [
        'purchase_unit_type',
        'conversion_factor',
        'last_purchase_price_cents',
        'average_purchase_price_cents',
      ],
      where: 'supply_id = ? AND source = ?',
      whereArgs: [supplyId, SupplyCostHistorySource.manual.storageValue],
      orderBy: 'occurred_at DESC, id DESC',
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return SupplyCostSnapshot(
      lastPurchasePriceCents:
          rows.first['last_purchase_price_cents'] as int? ?? 0,
      averagePurchasePriceCents:
          rows.first['average_purchase_price_cents'] as int?,
      purchaseUnitType: rows.first['purchase_unit_type'] as String? ?? 'un',
      conversionFactor: rows.first['conversion_factor'] as int? ?? 1,
    );
  }

  static Future<void> _insertHistory(
    DatabaseExecutor txn, {
    required int supplyId,
    required int? purchaseId,
    required int? purchaseItemId,
    required SupplyCostHistorySource source,
    required SupplyCostHistoryEventType eventType,
    required SupplyCostSnapshot snapshot,
    required DateTime occurredAt,
    String? changeSummary,
    String? notes,
  }) async {
    final nowIso = DateTime.now().toIso8601String();
    await txn.insert(TableNames.supplyCostHistory, {
      'uuid': IdGenerator.next(),
      'supply_id': supplyId,
      'purchase_id': purchaseId,
      'purchase_item_id': purchaseItemId,
      'source': source.storageValue,
      'event_type': eventType.storageValue,
      'purchase_unit_type': snapshot.purchaseUnitType,
      'conversion_factor': snapshot.conversionFactor,
      'last_purchase_price_cents': snapshot.lastPurchasePriceCents,
      'average_purchase_price_cents': snapshot.averagePurchasePriceCents,
      'change_summary': _cleanNullable(changeSummary),
      'notes': _cleanNullable(notes),
      'occurred_at': occurredAt.toIso8601String(),
      'created_at': nowIso,
    });
  }

  static SupplyCostHistoryEntry mapRow(Map<String, Object?> row) {
    return SupplyCostHistoryEntry(
      id: row['id'] as int,
      uuid: row['uuid'] as String,
      supplyId: row['supply_id'] as int,
      purchaseId: row['purchase_id'] as int?,
      purchaseItemId: row['purchase_item_id'] as int?,
      source: supplyCostHistorySourceFromStorage(row['source'] as String?),
      eventType: supplyCostHistoryEventTypeFromStorage(
        row['event_type'] as String?,
        fallbackSource: supplyCostHistorySourceFromStorage(
          row['source'] as String?,
        ),
      ),
      purchaseUnitType: row['purchase_unit_type'] as String? ?? 'un',
      conversionFactor: row['conversion_factor'] as int? ?? 1,
      lastPurchasePriceCents: row['last_purchase_price_cents'] as int? ?? 0,
      averagePurchasePriceCents: row['average_purchase_price_cents'] as int?,
      changeSummary:
          row['change_summary'] as String? ?? row['notes'] as String?,
      notes: row['notes'] as String?,
      occurredAt: DateTime.parse(row['occurred_at'] as String),
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }

  static String? _cleanNullable(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
