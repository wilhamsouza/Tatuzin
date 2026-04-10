import '../../../modules/compras/data/models/purchase_sync_payload.dart';
import '../../../modules/compras/domain/entities/purchase_status.dart';
import '../../../modules/fiado/data/models/fiado_payment_sync_payload.dart';
import '../../../modules/vendas/data/models/sale_cancellation_sync_payload.dart';
import '../../../modules/vendas/data/models/sale_sync_payload.dart';
import '../../../modules/vendas/domain/entities/sale_enums.dart';
import 'reconciliation_payload_support.dart';
import 'reconciliation_local_comparable_record.dart';
import 'remote_financial_event_record.dart';
import 'sync_feature_keys.dart';
import 'sync_metadata.dart';
import 'sync_queue_item.dart';
import '../../../modules/vendas/data/models/remote_sale_record.dart';

class ReconciliationLocalRecordMapper {
  const ReconciliationLocalRecordMapper._();

  static ReconciliationLocalComparableRecord mapCategory(
    Map<String, Object?> row, {
    required int localId,
    required SyncMetadata? metadata,
    required SyncQueueItem? queueItem,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) {
    return ReconciliationLocalComparableRecord(
      featureKey: SyncFeatureKeys.categories,
      entityType: 'category',
      localId: localId,
      localUuid: row['uuid'] as String,
      remoteId: metadata?.identity.remoteId,
      label: row['nome'] as String? ?? 'Categoria',
      createdAt: createdAt,
      updatedAt: updatedAt,
      metadataStatus: metadata?.status,
      queueItem: queueItem,
      lastError: metadata?.lastError,
      lastErrorType: metadata?.lastErrorType,
      payload: <String, dynamic>{
        'name': row['nome'] as String? ?? '',
        'description': row['descricao'] as String?,
        'isActive': (row['ativo'] as int? ?? 0) == 1,
        'deletedAt': row['deletado_em'] as String?,
      },
      allowRepair: true,
    );
  }

  static ReconciliationLocalComparableRecord mapCustomer(
    Map<String, Object?> row, {
    required int localId,
    required SyncMetadata? metadata,
    required SyncQueueItem? queueItem,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) {
    return ReconciliationLocalComparableRecord(
      featureKey: SyncFeatureKeys.customers,
      entityType: 'customer',
      localId: localId,
      localUuid: row['uuid'] as String,
      remoteId: metadata?.identity.remoteId,
      label: row['nome'] as String? ?? 'Cliente',
      createdAt: createdAt,
      updatedAt: updatedAt,
      metadataStatus: metadata?.status,
      queueItem: queueItem,
      lastError: metadata?.lastError,
      lastErrorType: metadata?.lastErrorType,
      payload: <String, dynamic>{
        'name': row['nome'] as String? ?? '',
        'phone': row['telefone'] as String?,
        'address': row['endereco'] as String?,
        'notes': row['observacao'] as String?,
        'isActive': (row['ativo'] as int? ?? 0) == 1,
        'deletedAt': row['deletado_em'] as String?,
      },
      allowRepair: true,
    );
  }

  static ReconciliationLocalComparableRecord mapSupplier(
    Map<String, Object?> row, {
    required int localId,
    required SyncMetadata? metadata,
    required SyncQueueItem? queueItem,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) {
    return ReconciliationLocalComparableRecord(
      featureKey: SyncFeatureKeys.suppliers,
      entityType: 'supplier',
      localId: localId,
      localUuid: row['uuid'] as String,
      remoteId: metadata?.identity.remoteId,
      label: row['nome'] as String? ?? 'Fornecedor',
      createdAt: createdAt,
      updatedAt: updatedAt,
      metadataStatus: metadata?.status,
      queueItem: queueItem,
      lastError: metadata?.lastError,
      lastErrorType: metadata?.lastErrorType,
      payload: <String, dynamic>{
        'localUuid': row['uuid'] as String,
        'name': row['nome'] as String? ?? '',
        'tradeName': row['nome_fantasia'] as String?,
        'phone': row['telefone'] as String?,
        'email': row['email'] as String?,
        'address': row['endereco'] as String?,
        'document': row['documento'] as String?,
        'contactName': row['contato_responsavel'] as String?,
        'notes': row['observacao'] as String?,
        'isActive': (row['ativo'] as int? ?? 0) == 1,
        'deletedAt': row['deletado_em'] as String?,
      },
      allowRepair: true,
    );
  }

  static ReconciliationLocalComparableRecord mapProduct(
    Map<String, Object?> row, {
    required int localId,
    required SyncMetadata? metadata,
    required SyncQueueItem? queueItem,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) {
    return ReconciliationLocalComparableRecord(
      featureKey: SyncFeatureKeys.products,
      entityType: 'product',
      localId: localId,
      localUuid: row['uuid'] as String,
      remoteId: metadata?.identity.remoteId,
      label: row['nome'] as String? ?? 'Produto',
      createdAt: createdAt,
      updatedAt: updatedAt,
      metadataStatus: metadata?.status,
      queueItem: queueItem,
      lastError: metadata?.lastError,
      lastErrorType: metadata?.lastErrorType,
      payload: <String, dynamic>{
        'name': row['nome'] as String? ?? '',
        'categoryId': row['categoria_remote_id'] as String?,
        'description': row['descricao'] as String?,
        'barcode': row['codigo_barras'] as String?,
        'productType': row['tipo_produto'] as String? ?? 'unidade',
        'niche': row['nicho'] as String? ?? 'alimentacao',
        'catalogType': (row['catalog_type'] as String?) ?? 'simple',
        'modelName': row['model_name'] as String?,
        'variantLabel': row['variant_label'] as String?,
        'unitMeasure': row['unidade_medida'] as String? ?? 'un',
        'costPriceCents': row['custo_centavos'] as int? ?? 0,
        'salePriceCents': row['preco_venda_centavos'] as int? ?? 0,
        'stockMil': row['estoque_mil'] as int? ?? 0,
        'isActive': (row['ativo'] as int? ?? 0) == 1,
        'deletedAt': row['deletado_em'] as String?,
      },
      allowRepair: true,
    );
  }

  static ReconciliationLocalComparableRecord mapPurchase(
    PurchaseSyncPayload purchase, {
    required int localId,
    required SyncMetadata? metadata,
    required SyncQueueItem? queueItem,
  }) {
    return ReconciliationLocalComparableRecord(
      featureKey: SyncFeatureKeys.purchases,
      entityType: 'purchase',
      localId: localId,
      localUuid: purchase.purchaseUuid,
      remoteId: metadata?.identity.remoteId ?? purchase.remoteId,
      label: purchase.documentNumber?.trim().isNotEmpty == true
          ? 'Compra ${purchase.documentNumber}'
          : 'Compra #$localId',
      createdAt: purchase.createdAt,
      updatedAt: purchase.updatedAt,
      metadataStatus: metadata?.status,
      queueItem: queueItem,
      lastError: metadata?.lastError,
      lastErrorType: metadata?.lastErrorType,
      payload: <String, dynamic>{
        'localUuid': purchase.purchaseUuid,
        'supplierId': purchase.supplierRemoteId,
        'documentNumber': purchase.documentNumber,
        'notes': purchase.notes,
        'purchasedAt': purchase.purchasedAt.toIso8601String(),
        'dueDate': purchase.dueDate?.toIso8601String(),
        'paymentMethod': purchase.paymentMethod?.dbValue,
        'status': purchase.status.dbValue,
        'subtotalCents': purchase.subtotalCents,
        'discountCents': purchase.discountCents,
        'surchargeCents': purchase.surchargeCents,
        'freightCents': purchase.freightCents,
        'finalAmountCents': purchase.finalAmountCents,
        'paidAmountCents': purchase.paidAmountCents,
        'pendingAmountCents': purchase.pendingAmountCents,
        'canceledAt': purchase.cancelledAt?.toIso8601String(),
        'items': purchase.items
            .map(
              (item) => <String, dynamic>{
                'localUuid': item.itemUuid,
                'productId': item.productRemoteId,
                'productNameSnapshot': item.productNameSnapshot,
                'unitMeasureSnapshot': item.unitMeasureSnapshot,
                'quantityMil': item.quantityMil,
                'unitCostCents': item.unitCostCents,
                'subtotalCents': item.subtotalCents,
              },
            )
            .toList(),
        'payments': purchase.payments
            .map(
              (payment) => <String, dynamic>{
                'localUuid': payment.paymentUuid,
                'amountCents': payment.amountCents,
                'paymentMethod': payment.paymentMethod.dbValue,
                'paidAt': payment.paidAt.toIso8601String(),
                'notes': payment.notes,
              },
            )
            .toList(),
      },
      allowRepair: true,
    );
  }

  static ReconciliationLocalComparableRecord mapSale(
    SaleSyncPayload payload, {
    required SyncMetadata? metadata,
    required SyncQueueItem? queueItem,
  }) {
    return ReconciliationLocalComparableRecord(
      featureKey: SyncFeatureKeys.sales,
      entityType: 'sale',
      localId: payload.saleId,
      localUuid: payload.saleUuid,
      remoteId: payload.remoteId,
      label: 'Cupom ${payload.receiptNumber}',
      createdAt: payload.soldAt,
      updatedAt: payload.updatedAt,
      metadataStatus: payload.syncStatus,
      queueItem: queueItem,
      lastError: metadata?.lastError,
      lastErrorType: metadata?.lastErrorType,
      payload: ReconciliationPayloadSupport.normalizedSalePayload(
        RemoteSaleRecord.fromSyncPayload(payload).toCreateBody(),
      ),
      allowRepair: payload.status.name != 'cancelled',
    );
  }

  static ReconciliationLocalComparableRecord mapCanceledSaleFinancialEvent(
    SaleCancellationSyncPayload payload, {
    required SyncMetadata? metadata,
    required SyncQueueItem? queueItem,
  }) {
    return ReconciliationLocalComparableRecord(
      featureKey: SyncFeatureKeys.financialEvents,
      entityType: 'sale_canceled_event',
      localId: payload.saleId,
      localUuid: payload.saleUuid,
      remoteId: payload.remoteId,
      label: 'Cancelamento venda #${payload.saleId}',
      createdAt: payload.canceledAt,
      updatedAt: payload.updatedAt,
      metadataStatus: payload.syncStatus,
      queueItem: queueItem,
      lastError: metadata?.lastError,
      lastErrorType: metadata?.lastErrorType,
      payload: RemoteFinancialEventRecord(
        remoteId: payload.remoteId ?? '',
        companyId: '',
        saleId: payload.saleRemoteId,
        fiadoId: null,
        eventType: 'sale_canceled',
        localUuid: payload.saleUuid,
        amountCents: payload.amountCents,
        paymentType: payload.paymentType,
        createdAt: payload.canceledAt,
        updatedAt: payload.updatedAt,
        metadata: <String, dynamic>{
          'saleLocalId': payload.saleId,
          if (payload.notes != null && payload.notes!.trim().isNotEmpty)
            'notes': payload.notes!.trim(),
        },
      ).toCreateBody(),
      allowRepair:
          payload.saleRemoteId != null && payload.saleRemoteId!.isNotEmpty,
    );
  }

  static ReconciliationLocalComparableRecord mapFiadoPaymentFinancialEvent(
    FiadoPaymentSyncPayload payload, {
    required SyncMetadata? metadata,
    required SyncQueueItem? queueItem,
  }) {
    return ReconciliationLocalComparableRecord(
      featureKey: SyncFeatureKeys.financialEvents,
      entityType: 'fiado_payment_event',
      localId: payload.entryId,
      localUuid: payload.entryUuid,
      remoteId: payload.remoteId,
      label: 'Pagamento fiado #${payload.entryId}',
      createdAt: payload.createdAt,
      updatedAt: payload.updatedAt,
      metadataStatus: payload.syncStatus,
      queueItem: queueItem,
      lastError: metadata?.lastError,
      lastErrorType: metadata?.lastErrorType,
      payload: RemoteFinancialEventRecord(
        remoteId: payload.remoteId ?? '',
        companyId: '',
        saleId: payload.saleRemoteId,
        fiadoId: payload.fiadoUuid,
        eventType: 'fiado_payment',
        localUuid: payload.entryUuid,
        amountCents: payload.amountCents,
        paymentType: payload.paymentMethod.dbValue,
        createdAt: payload.createdAt,
        updatedAt: payload.updatedAt,
        metadata: <String, dynamic>{
          'fiadoLocalId': payload.fiadoId,
          'paymentEntryLocalId': payload.entryId,
          if (payload.notes != null && payload.notes!.trim().isNotEmpty)
            'notes': payload.notes!.trim(),
        },
      ).toCreateBody(),
      allowRepair:
          payload.saleRemoteId != null && payload.saleRemoteId!.isNotEmpty,
    );
  }
}
