enum OperationalDashboardMovementDirection { inflow, outflow, neutral }

class OperationalDashboardRecentMovement {
  const OperationalDashboardRecentMovement({
    required this.label,
    required this.amountCents,
    required this.createdAt,
    required this.direction,
    this.description,
  });

  final String label;
  final int amountCents;
  final DateTime createdAt;
  final OperationalDashboardMovementDirection direction;
  final String? description;
}

class OperationalDashboardSnapshot {
  const OperationalDashboardSnapshot({
    required this.soldTodayCents,
    required this.currentCashCents,
    required this.pendingFiadoCount,
    required this.pendingFiadoCents,
    required this.activeOperationalOrdersCount,
    required this.recentMovements,
    this.todaySalesCount = 0,
    this.hasOpenCashSession = false,
    this.cashNeedsConfirmation = false,
  });

  final int soldTodayCents;
  final int todaySalesCount;
  final bool hasOpenCashSession;
  final bool cashNeedsConfirmation;
  final int currentCashCents;
  final int pendingFiadoCount;
  final int pendingFiadoCents;
  final int activeOperationalOrdersCount;
  final List<OperationalDashboardRecentMovement> recentMovements;

  int get recentMovementsCount => recentMovements.length;
}
