import 'package:flutter_test/flutter_test.dart';

import 'package:erp_pdv_app/app/core/sync/sync_status.dart';
import 'package:erp_pdv_app/modules/insumos/data/models/remote_supply_record.dart';
import 'package:erp_pdv_app/modules/insumos/data/models/supply_sync_payload.dart';

void main() {
  test('supply sync payload keeps remote audit references in cost history', () {
    final record = RemoteSupplyRecord.fromSyncPayload(
      SupplySyncPayload(
        supplyId: 1,
        supplyUuid: 'supply-uuid',
        remoteId: null,
        defaultSupplierLocalId: 10,
        defaultSupplierRemoteId: 'supplier-remote',
        name: 'Mussarela',
        sku: 'MSL-1',
        unitType: 'g',
        purchaseUnitType: 'kg',
        conversionFactor: 1000,
        lastPurchasePriceCents: 3600,
        averagePurchasePriceCents: 3550,
        currentStockMil: 5000,
        minimumStockMil: 1000,
        isActive: true,
        createdAt: DateTime.parse('2026-04-15T12:00:00Z'),
        updatedAt: DateTime.parse('2026-04-15T12:05:00Z'),
        syncStatus: SyncStatus.pendingUpdate,
        lastSyncedAt: null,
        costHistory: [
          SupplyCostHistorySyncPayload(
            historyId: 1,
            historyUuid: 'history-1',
            purchaseLocalId: 99,
            purchaseRemoteId: 'purchase-remote',
            purchaseItemLocalUuid: 'purchase-item-uuid',
            source: 'purchase',
            eventType: 'purchase_created',
            purchaseUnitType: 'kg',
            conversionFactor: 1000,
            lastPurchasePriceCents: 3600,
            averagePurchasePriceCents: 3550,
            changeSummary: 'Compra criada.',
            notes: 'Historico remoto.',
            occurredAt: _occurredAt,
            createdAt: _createdAt,
          ),
        ],
      ),
    );

    final body = record.toUpsertBody();
    final history = body['costHistory'] as List<dynamic>;

    expect(body['defaultSupplierId'], 'supplier-remote');
    expect(history.single, <String, dynamic>{
      'localUuid': 'history-1',
      'purchaseId': 'purchase-remote',
      'purchaseItemId': null,
      'purchaseItemLocalUuid': 'purchase-item-uuid',
      'source': 'purchase',
      'eventType': 'purchase_created',
      'purchaseUnitType': 'kg',
      'conversionFactor': 1000,
      'lastPurchasePriceCents': 3600,
      'averagePurchasePriceCents': 3550,
      'changeSummary': 'Compra criada.',
      'notes': 'Historico remoto.',
      'occurredAt': '2026-04-15T11:59:00.000Z',
    });
  });

  test('inactive supply payload mirrors soft delete timestamp', () {
    final updatedAt = DateTime.parse('2026-04-15T12:05:00Z');
    final record = RemoteSupplyRecord.fromSyncPayload(
      SupplySyncPayload(
        supplyId: 1,
        supplyUuid: 'supply-uuid',
        remoteId: 'supply-remote',
        defaultSupplierLocalId: null,
        defaultSupplierRemoteId: null,
        name: 'Embalagem',
        sku: null,
        unitType: 'un',
        purchaseUnitType: 'cx',
        conversionFactor: 100,
        lastPurchasePriceCents: 1200,
        averagePurchasePriceCents: null,
        currentStockMil: null,
        minimumStockMil: null,
        isActive: false,
        createdAt: DateTime.parse('2026-04-15T12:00:00Z'),
        updatedAt: updatedAt,
        syncStatus: SyncStatus.pendingUpdate,
        lastSyncedAt: null,
        costHistory: const [],
      ),
    );

    expect(record.deletedAt, updatedAt);
    expect(record.toUpsertBody()['deletedAt'], updatedAt.toIso8601String());
  });
}

final _occurredAt = DateTime.parse('2026-04-15T11:59:00Z');
final _createdAt = DateTime.parse('2026-04-15T12:00:00Z');
