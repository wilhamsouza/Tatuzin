import 'package:flutter_test/flutter_test.dart';

import 'package:erp_pdv_app/app/core/sync/sync_status.dart';
import 'package:erp_pdv_app/modules/compras/data/models/purchase_sync_payload.dart';
import 'package:erp_pdv_app/modules/compras/data/models/remote_purchase_record.dart';
import 'package:erp_pdv_app/modules/compras/domain/entities/purchase_item.dart';
import 'package:erp_pdv_app/modules/compras/domain/entities/purchase_status.dart';
import 'package:erp_pdv_app/modules/vendas/domain/entities/sale_enums.dart';

void main() {
  test('mixed purchase sync payload keeps product and supply references', () {
    final record = RemotePurchaseRecord.fromSyncPayload(
      PurchaseSyncPayload(
        purchaseId: 1,
        purchaseUuid: 'purchase-uuid',
        remoteId: null,
        supplierLocalId: 10,
        supplierRemoteId: 'supplier-remote',
        documentNumber: 'NF-123',
        notes: 'Compra mista',
        purchasedAt: DateTime.parse('2026-04-15T12:00:00Z'),
        dueDate: null,
        paymentMethod: PaymentMethod.pix,
        status: PurchaseStatus.recebida,
        subtotalCents: 2500,
        discountCents: 0,
        surchargeCents: 0,
        freightCents: 0,
        finalAmountCents: 2500,
        paidAmountCents: 2500,
        pendingAmountCents: 0,
        cancelledAt: null,
        createdAt: DateTime.parse('2026-04-15T12:00:00Z'),
        updatedAt: DateTime.parse('2026-04-15T12:05:00Z'),
        syncStatus: SyncStatus.pendingUpload,
        lastSyncedAt: null,
        items: const [
          PurchaseSyncItemPayload(
            itemId: 1,
            itemUuid: 'item-product',
            itemType: PurchaseItemType.product,
            productLocalId: 100,
            productVariantLocalId: 110,
            supplyLocalId: null,
            productRemoteId: 'product-remote',
            productVariantRemoteId: null,
            supplyRemoteId: null,
            itemNameSnapshot: 'Hamburguer',
            variantSkuSnapshot: 'CAMISETA-PRETA-P',
            variantColorLabelSnapshot: 'Preta',
            variantSizeLabelSnapshot: 'P',
            unitMeasureSnapshot: 'un',
            quantityMil: 1000,
            unitCostCents: 1500,
            subtotalCents: 1500,
          ),
          PurchaseSyncItemPayload(
            itemId: 2,
            itemUuid: 'item-supply',
            itemType: PurchaseItemType.supply,
            productLocalId: null,
            productVariantLocalId: null,
            supplyLocalId: 200,
            productRemoteId: null,
            productVariantRemoteId: null,
            supplyRemoteId: 'supply-remote',
            itemNameSnapshot: 'Mussarela',
            variantSkuSnapshot: null,
            variantColorLabelSnapshot: null,
            variantSizeLabelSnapshot: null,
            unitMeasureSnapshot: 'kg',
            quantityMil: 1000,
            unitCostCents: 1000,
            subtotalCents: 1000,
          ),
        ],
        payments: const [],
      ),
    );

    final body = record.toUpsertBody();
    final items = body['items'] as List<dynamic>;

    expect(items, hasLength(2));
    expect(items.first, <String, dynamic>{
      'localUuid': 'item-product',
      'itemType': 'product',
      'productId': 'product-remote',
      'productVariantId': null,
      'supplyId': null,
      'productNameSnapshot': 'Hamburguer',
      'variantSkuSnapshot': 'CAMISETA-PRETA-P',
      'variantColorLabelSnapshot': 'Preta',
      'variantSizeLabelSnapshot': 'P',
      'unitMeasureSnapshot': 'un',
      'quantityMil': 1000,
      'unitCostCents': 1500,
      'subtotalCents': 1500,
    });
    expect(items.last, <String, dynamic>{
      'localUuid': 'item-supply',
      'itemType': 'supply',
      'productId': null,
      'productVariantId': null,
      'supplyId': 'supply-remote',
      'productNameSnapshot': 'Mussarela',
      'variantSkuSnapshot': null,
      'variantColorLabelSnapshot': null,
      'variantSizeLabelSnapshot': null,
      'unitMeasureSnapshot': 'kg',
      'quantityMil': 1000,
      'unitCostCents': 1000,
      'subtotalCents': 1000,
    });
  });

  test('remote mixed purchase json parses item type and supply id', () {
    final record = RemotePurchaseRecord.fromJson({
      'id': 'purchase-remote',
      'localUuid': 'purchase-uuid',
      'supplierId': 'supplier-remote',
      'supplierName': 'Fornecedor',
      'purchasedAt': '2026-04-15T12:00:00Z',
      'status': 'recebida',
      'subtotalCents': 1000,
      'discountCents': 0,
      'surchargeCents': 0,
      'freightCents': 0,
      'finalAmountCents': 1000,
      'paidAmountCents': 1000,
      'pendingAmountCents': 0,
      'createdAt': '2026-04-15T12:00:00Z',
      'updatedAt': '2026-04-15T12:01:00Z',
      'items': [
        {
          'id': 'item-remote',
          'localUuid': 'item-supply',
          'itemType': 'supply',
          'supplyId': 'supply-remote',
          'productNameSnapshot': 'Molho',
          'variantSkuSnapshot': null,
          'variantColorLabelSnapshot': null,
          'variantSizeLabelSnapshot': null,
          'unitMeasureSnapshot': 'l',
          'quantityMil': 1000,
          'unitCostCents': 900,
          'subtotalCents': 900,
        },
      ],
      'payments': const [],
    });

    expect(record.items.single.itemType, PurchaseItemType.supply);
    expect(record.items.single.remoteSupplyId, 'supply-remote');
    expect(record.items.single.remoteProductId, isNull);
  });
}
