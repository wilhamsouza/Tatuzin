class DashboardMetrics {
  const DashboardMetrics({
    required this.soldTodayCents,
    required this.currentCashCents,
    required this.pendingFiadoCount,
    required this.pendingFiadoCents,
    required this.realizedProfitTodayCents,
  });

  final int soldTodayCents;
  final int currentCashCents;
  final int pendingFiadoCount;
  final int pendingFiadoCents;
  final int realizedProfitTodayCents;
}
