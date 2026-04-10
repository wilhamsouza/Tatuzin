import 'package:sqflite/sqflite.dart';

import '../../../../app/core/database/table_names.dart';
import '../../../../app/core/sync/sync_feature_keys.dart';
import '../../../../app/core/sync/sync_status.dart';
import '../../../vendas/domain/entities/sale_enums.dart';
import '../../domain/entities/purchase_status.dart';
import '../models/purchase_sync_payload.dart';

class PurchaseSyncPayloadLoader {
  const PurchaseSyncPayloadLoader._();

  static Future<PurchaseSyncPayload?> load(
    DatabaseExecutor db, {
    required int purchaseId,
    required String featureKey,
  }) async {
    final rows = await db.rawQuery(
      '''
      SELECT
        c.*,
        sync.remote_id AS sync_remote_id,
        sync.sync_status AS sync_status,
        sync.last_synced_at AS sync_last_synced_at,
        supplier_sync.remote_id AS supplier_remote_id
      FROM ${TableNames.compras} c
      LEFT JOIN ${TableNames.syncRegistros} sync
        ON sync.feature_key = '$featureKey'
        AND sync.local_id = c.id
      LEFT JOIN ${TableNames.syncRegistros} supplier_sync
        ON supplier_sync.feature_key = '${SyncFeatureKeys.suppliers}'
        AND supplier_sync.local_id = c.fornecedor_id
      WHERE c.id = ?
      LIMIT 1
    ''',
      [purchaseId],
    );

    if (rows.isEmpty) {
      return null;
    }

    final row = rows.first;
    final itemsRows = await db.rawQuery(
      '''
      SELECT
        ic.*,
        product_sync.remote_id AS produto_remote_id
      FROM ${TableNames.itensCompra} ic
      LEFT JOIN ${TableNames.syncRegistros} product_sync
        ON product_sync.feature_key = '${SyncFeatureKeys.products}'
        AND product_sync.local_id = ic.produto_id
      WHERE ic.compra_id = ?
      ORDER BY ic.id ASC
    ''',
      [purchaseId],
    );
    final paymentRows = await db.query(
      TableNames.compraPagamentos,
      where: 'compra_id = ?',
      whereArgs: [purchaseId],
      orderBy: 'data_hora ASC, id ASC',
    );

    return PurchaseSyncPayload(
      purchaseId: row['id'] as int,
      purchaseUuid: row['uuid'] as String,
      remoteId: row['sync_remote_id'] as String?,
      supplierLocalId: row['fornecedor_id'] as int,
      supplierRemoteId: row['supplier_remote_id'] as String?,
      documentNumber: row['numero_documento'] as String?,
      notes: row['observacao'] as String?,
      purchasedAt: DateTime.parse(row['data_compra'] as String),
      dueDate: row['data_vencimento'] == null
          ? null
          : DateTime.parse(row['data_vencimento'] as String),
      paymentMethod: row['forma_pagamento'] == null
          ? null
          : PaymentMethodX.fromDb(row['forma_pagamento'] as String),
      status: PurchaseStatusX.fromDb(row['status'] as String),
      subtotalCents: row['subtotal_centavos'] as int,
      discountCents: row['desconto_centavos'] as int? ?? 0,
      surchargeCents: row['acrescimo_centavos'] as int? ?? 0,
      freightCents: row['frete_centavos'] as int? ?? 0,
      finalAmountCents: row['valor_final_centavos'] as int,
      paidAmountCents: row['valor_pago_centavos'] as int? ?? 0,
      pendingAmountCents: row['valor_pendente_centavos'] as int? ?? 0,
      cancelledAt: row['cancelada_em'] == null
          ? null
          : DateTime.parse(row['cancelada_em'] as String),
      createdAt: DateTime.parse(row['criado_em'] as String),
      updatedAt: DateTime.parse(row['atualizado_em'] as String),
      syncStatus: syncStatusFromStorage(row['sync_status'] as String?),
      lastSyncedAt: row['sync_last_synced_at'] == null
          ? null
          : DateTime.parse(row['sync_last_synced_at'] as String),
      items: itemsRows
          .map(
            (item) => PurchaseSyncItemPayload(
              itemId: item['id'] as int,
              itemUuid: item['uuid'] as String,
              productLocalId: item['produto_id'] as int,
              productRemoteId: item['produto_remote_id'] as String?,
              productNameSnapshot: item['nome_produto_snapshot'] as String,
              unitMeasureSnapshot:
                  item['unidade_medida_snapshot'] as String? ?? 'un',
              quantityMil: item['quantidade_mil'] as int? ?? 0,
              unitCostCents: item['custo_unitario_centavos'] as int? ?? 0,
              subtotalCents: item['subtotal_centavos'] as int? ?? 0,
            ),
          )
          .toList(),
      payments: paymentRows
          .map(
            (payment) => PurchaseSyncPaymentPayload(
              paymentId: payment['id'] as int,
              paymentUuid: payment['uuid'] as String,
              amountCents: payment['valor_centavos'] as int? ?? 0,
              paymentMethod: PaymentMethodX.fromDb(
                payment['forma_pagamento'] as String? ?? 'dinheiro',
              ),
              paidAt: DateTime.parse(payment['data_hora'] as String),
              notes: payment['observacao'] as String?,
            ),
          )
          .toList(),
    );
  }
}
