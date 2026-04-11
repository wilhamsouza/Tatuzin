class ReportCustomerCreditSummary {
  const ReportCustomerCreditSummary({
    required this.customerId,
    required this.customerName,
    required this.balanceCents,
  });

  final int customerId;
  final String customerName;
  final int balanceCents;
}
