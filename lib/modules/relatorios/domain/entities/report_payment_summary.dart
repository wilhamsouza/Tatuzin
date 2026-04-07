import '../../../vendas/domain/entities/sale_enums.dart';

class ReportPaymentSummary {
  const ReportPaymentSummary({
    required this.paymentMethod,
    required this.receivedCents,
    required this.operationsCount,
  });

  final PaymentMethod paymentMethod;
  final int receivedCents;
  final int operationsCount;
}
