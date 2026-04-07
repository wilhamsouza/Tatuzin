import 'sale_enums.dart';

class CompletedSale {
  const CompletedSale({
    required this.saleId,
    required this.receiptNumber,
    required this.totalCents,
    required this.itemsCount,
    required this.soldAt,
    required this.saleType,
    required this.paymentMethod,
    this.clientId,
    this.fiadoId,
  });

  final int saleId;
  final String receiptNumber;
  final int totalCents;
  final int itemsCount;
  final DateTime soldAt;
  final SaleType saleType;
  final PaymentMethod paymentMethod;
  final int? clientId;
  final int? fiadoId;
}
