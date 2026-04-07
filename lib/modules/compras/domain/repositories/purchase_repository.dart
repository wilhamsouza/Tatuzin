import '../entities/purchase.dart';
import '../entities/purchase_detail.dart';
import '../entities/purchase_payment.dart';
import '../entities/purchase_status.dart';

abstract interface class PurchaseRepository {
  Future<List<Purchase>> search({
    String query = '',
    PurchaseStatus? status,
    int? supplierId,
  });

  Future<PurchaseDetail> fetchDetail(int purchaseId);
  Future<int> create(PurchaseUpsertInput input);
  Future<void> update(int id, PurchaseUpsertInput input);
  Future<PurchaseDetail> registerPayment(PurchasePaymentInput input);
  Future<void> cancel(int purchaseId, {String? reason});
}
