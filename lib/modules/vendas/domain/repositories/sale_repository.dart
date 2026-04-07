import '../entities/checkout_input.dart';
import '../entities/completed_sale.dart';

abstract interface class SaleRepository {
  Future<CompletedSale> completeCashSale({required CheckoutInput input});

  Future<CompletedSale> completeCreditSale({required CheckoutInput input});

  Future<void> cancelSale({required int saleId, required String reason});
}
