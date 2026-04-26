import 'package:sqflite/sqflite.dart';

import '../../../modules/compras/data/sqlite_purchase_repository.dart';
import '../../../modules/fiado/data/sqlite_fiado_repository.dart';
import '../../../modules/vendas/data/sqlite_sale_repository.dart';
import '../database/table_names.dart';
import 'reconciliation_local_comparable_record.dart';
import 'reconciliation_local_record_mapper.dart';
import 'sync_feature_keys.dart';
import 'sync_metadata.dart';
import 'sync_queue_item.dart';

class ReconciliationLocalRichLoader {
  const ReconciliationLocalRichLoader._();

  static Future<List<ReconciliationLocalComparableRecord>> loadProducts(
    DatabaseExecutor database, {
    required Map<int, SyncMetadata> metadataByLocalId,
    required Map<String, SyncQueueItem> queueByEntityKey,
  }) async {
    final rows = await database.rawQuery('''
      SELECT
        p.id,
        p.uuid,
        p.nome,
        p.descricao,
        p.codigo_barras,
        p.tipo_produto,
        p.catalog_type,
        p.model_name,
        p.variant_label,
        p.unidade_medida,
        p.custo_centavos,
        p.preco_venda_centavos,
        p.estoque_mil,
        p.ativo,
        p.criado_em,
        p.atualizado_em,
        p.deletado_em,
        p.categoria_id,
        c.nome AS categoria_nome,
        category_sync.remote_id AS categoria_remote_id
      FROM ${TableNames.produtos} p
      LEFT JOIN ${TableNames.categorias} c ON c.id = p.categoria_id
      LEFT JOIN ${TableNames.syncRegistros} category_sync
        ON category_sync.feature_key = '${SyncFeatureKeys.categories}'
        AND category_sync.local_id = p.categoria_id
      ORDER BY p.nome COLLATE NOCASE ASC, p.id ASC
    ''');

    return rows.map((row) {
      final localId = row['id'] as int;
      final metadata = metadataByLocalId[localId];
      return ReconciliationLocalRecordMapper.mapProduct(
        row,
        localId: localId,
        metadata: metadata,
        queueItem:
            queueByEntityKey[_entityKey(
              SyncFeatureKeys.products,
              'product',
              localId,
            )],
        createdAt: DateTime.parse(row['criado_em'] as String),
        updatedAt: DateTime.parse(row['atualizado_em'] as String),
      );
    }).toList();
  }

  static Future<List<ReconciliationLocalComparableRecord>> loadPurchases(
    DatabaseExecutor database, {
    required Map<int, SyncMetadata> metadataByLocalId,
    required Map<String, SyncQueueItem> queueByEntityKey,
    required SqlitePurchaseRepository purchaseRepository,
  }) async {
    final idRows = await database.query(
      TableNames.compras,
      columns: const ['id'],
      orderBy: 'data_compra DESC, id DESC',
    );

    final records = <ReconciliationLocalComparableRecord>[];
    for (final row in idRows) {
      final localId = row['id'] as int;
      final purchase = await purchaseRepository.findPurchaseForSync(localId);
      if (purchase == null) {
        continue;
      }
      final metadata = metadataByLocalId[localId];
      records.add(
        ReconciliationLocalRecordMapper.mapPurchase(
          purchase,
          localId: localId,
          metadata: metadata,
          queueItem:
              queueByEntityKey[_entityKey(
                SyncFeatureKeys.purchases,
                'purchase',
                localId,
              )],
        ),
      );
    }

    return records;
  }

  static Future<List<ReconciliationLocalComparableRecord>> loadSales(
    DatabaseExecutor database, {
    required Map<int, SyncMetadata> metadataByLocalId,
    required Map<String, SyncQueueItem> queueByEntityKey,
    required SqliteSaleRepository saleRepository,
  }) async {
    final idRows = await database.query(
      TableNames.vendas,
      columns: const ['id'],
      orderBy: 'data_venda DESC, id DESC',
    );

    final records = <ReconciliationLocalComparableRecord>[];
    for (final row in idRows) {
      final localId = row['id'] as int;
      final payload = await saleRepository.findSaleForSync(localId);
      if (payload == null) {
        continue;
      }
      final metadata = metadataByLocalId[localId];
      records.add(
        ReconciliationLocalRecordMapper.mapSale(
          payload,
          metadata: metadata,
          queueItem:
              queueByEntityKey[_entityKey(
                SyncFeatureKeys.sales,
                'sale',
                payload.saleId,
              )],
        ),
      );
    }

    return records;
  }

  static Future<List<ReconciliationLocalComparableRecord>> loadFinancialEvents(
    DatabaseExecutor database, {
    required Map<int, SyncMetadata> cancellationMetadataByLocalId,
    required Map<int, SyncMetadata> paymentMetadataByLocalId,
    required Map<String, SyncQueueItem> queueByEntityKey,
    required SqliteSaleRepository saleRepository,
    required SqliteFiadoRepository fiadoRepository,
  }) async {
    final records = <ReconciliationLocalComparableRecord>[];

    final canceledSaleRows = await database.query(
      TableNames.vendas,
      columns: const ['id'],
      where: 'status = ? AND cancelada_em IS NOT NULL',
      whereArgs: const ['cancelada'],
      orderBy: 'cancelada_em DESC, id DESC',
    );
    for (final row in canceledSaleRows) {
      final saleId = row['id'] as int;
      final payload = await saleRepository.findSaleCancellationForSync(saleId);
      if (payload == null) {
        continue;
      }
      final metadata = cancellationMetadataByLocalId[saleId];
      records.add(
        ReconciliationLocalRecordMapper.mapCanceledSaleFinancialEvent(
          payload,
          metadata: metadata,
          queueItem:
              queueByEntityKey[_entityKey(
                SyncFeatureKeys.financialEvents,
                'sale_canceled_event',
                payload.saleId,
              )],
        ),
      );
    }

    final paymentRows = await database.query(
      TableNames.fiadoLancamentos,
      columns: const ['id'],
      where: 'tipo_lancamento = ?',
      whereArgs: const ['pagamento'],
      orderBy: 'data_lancamento DESC, id DESC',
    );
    for (final row in paymentRows) {
      final paymentId = row['id'] as int;
      final payload = await fiadoRepository.findPaymentForSync(paymentId);
      if (payload == null) {
        continue;
      }
      final metadata = paymentMetadataByLocalId[paymentId];
      records.add(
        ReconciliationLocalRecordMapper.mapFiadoPaymentFinancialEvent(
          payload,
          metadata: metadata,
          queueItem:
              queueByEntityKey[_entityKey(
                SyncFeatureKeys.financialEvents,
                'fiado_payment_event',
                payload.entryId,
              )],
        ),
      );
    }

    return records;
  }

  static String _entityKey(
    String featureKey,
    String entityType,
    int localEntityId,
  ) {
    return '$featureKey:$entityType:$localEntityId';
  }
}
