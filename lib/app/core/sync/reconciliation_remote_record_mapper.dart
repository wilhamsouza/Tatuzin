import '../../../modules/categorias/data/models/remote_category_record.dart';
import '../../../modules/clientes/data/models/remote_customer_record.dart';
import '../../../modules/compras/data/models/remote_purchase_record.dart';
import '../../../modules/fornecedores/data/models/remote_supplier_record.dart';
import '../../../modules/produtos/data/models/remote_product_record.dart';
import '../../../modules/vendas/data/models/remote_sale_record.dart';
import 'reconciliation_payload_support.dart';
import 'reconciliation_remote_comparable_record.dart';
import 'remote_financial_event_record.dart';

class ReconciliationRemoteRecordMapper {
  const ReconciliationRemoteRecordMapper._();

  static ReconciliationRemoteComparableRecord mapCategory(
    RemoteCategoryRecord remote,
  ) {
    return ReconciliationRemoteComparableRecord(
      entityType: 'category',
      remoteId: remote.remoteId,
      localUuid: remote.localUuid,
      label: remote.name,
      updatedAt: remote.updatedAt,
      payload: remote.toUpsertBody(),
    );
  }

  static ReconciliationRemoteComparableRecord mapSupplier(
    RemoteSupplierRecord remote,
  ) {
    return ReconciliationRemoteComparableRecord(
      entityType: 'supplier',
      remoteId: remote.remoteId,
      localUuid: remote.localUuid,
      label: remote.name,
      updatedAt: remote.updatedAt,
      payload: remote.toUpsertBody(),
    );
  }

  static ReconciliationRemoteComparableRecord mapProduct(
    RemoteProductRecord remote,
  ) {
    return ReconciliationRemoteComparableRecord(
      entityType: 'product',
      remoteId: remote.remoteId,
      localUuid: remote.localUuid,
      label: remote.displayName,
      updatedAt: remote.updatedAt,
      payload: remote.toUpsertBody(),
    );
  }

  static ReconciliationRemoteComparableRecord mapPurchase(
    RemotePurchaseRecord remote,
  ) {
    return ReconciliationRemoteComparableRecord(
      entityType: 'purchase',
      remoteId: remote.remoteId,
      localUuid: remote.localUuid,
      label: remote.documentNumber?.trim().isNotEmpty == true
          ? 'Compra ${remote.documentNumber}'
          : 'Compra ${remote.remoteId}',
      updatedAt: remote.updatedAt,
      payload: remote.toUpsertBody(),
    );
  }

  static ReconciliationRemoteComparableRecord mapCustomer(
    RemoteCustomerRecord remote,
  ) {
    return ReconciliationRemoteComparableRecord(
      entityType: 'customer',
      remoteId: remote.remoteId,
      localUuid: remote.localUuid,
      label: remote.name,
      updatedAt: remote.updatedAt,
      payload: remote.toUpsertBody(),
    );
  }

  static ReconciliationRemoteComparableRecord mapSale(RemoteSaleRecord remote) {
    return ReconciliationRemoteComparableRecord(
      entityType: 'sale',
      remoteId: remote.remoteId,
      localUuid: remote.localUuid,
      label: remote.receiptNumber ?? 'Venda ${remote.remoteId}',
      updatedAt: remote.updatedAt,
      payload: ReconciliationPayloadSupport.normalizedSalePayload(
        remote.toCreateBody(),
      ),
    );
  }

  static ReconciliationRemoteComparableRecord mapFinancialEvent(
    RemoteFinancialEventRecord remote,
  ) {
    return ReconciliationRemoteComparableRecord(
      entityType: remote.eventType == 'sale_canceled'
          ? 'sale_canceled_event'
          : 'fiado_payment_event',
      remoteId: remote.remoteId,
      localUuid: remote.localUuid,
      label: remote.eventType == 'sale_canceled'
          ? 'Cancelamento remoto ${remote.localUuid}'
          : 'Pagamento remoto ${remote.localUuid}',
      updatedAt: remote.updatedAt,
      payload: remote.toCreateBody(),
    );
  }
}
