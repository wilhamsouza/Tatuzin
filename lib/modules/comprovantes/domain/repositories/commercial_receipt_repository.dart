import '../entities/commercial_receipt.dart';
import '../entities/commercial_receipt_request.dart';

abstract interface class CommercialReceiptRepository {
  Future<CommercialReceipt> build(CommercialReceiptRequest request);
}
