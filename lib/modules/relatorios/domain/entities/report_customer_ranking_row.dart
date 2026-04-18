class ReportCustomerRankingRow {
  const ReportCustomerRankingRow({
    required this.customerId,
    required this.customerName,
    required this.isActive,
    required this.salesCount,
    required this.totalPurchasedCents,
    required this.pendingFiadoCents,
    required this.creditBalanceCents,
    required this.lastPurchaseAt,
  });

  final int customerId;
  final String customerName;
  final bool isActive;
  final int salesCount;
  final int totalPurchasedCents;
  final int pendingFiadoCents;
  final int creditBalanceCents;
  final DateTime? lastPurchaseAt;

  bool get hasPurchases => salesCount > 0 || totalPurchasedCents > 0;

  bool get hasPendingFiado => pendingFiadoCents > 0;

  bool get hasCredit => creditBalanceCents > 0;
}
