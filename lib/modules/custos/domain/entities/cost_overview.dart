class CostOverview {
  const CostOverview({
    required this.pendingFixedCents,
    required this.pendingVariableCents,
    required this.overdueFixedCents,
    required this.overdueVariableCents,
    required this.paidFixedThisMonthCents,
    required this.paidVariableThisMonthCents,
    required this.openFixedCount,
    required this.openVariableCount,
  });

  final int pendingFixedCents;
  final int pendingVariableCents;
  final int overdueFixedCents;
  final int overdueVariableCents;
  final int paidFixedThisMonthCents;
  final int paidVariableThisMonthCents;
  final int openFixedCount;
  final int openVariableCount;
}
