class ManagerialDashboardPlannedIndicator {
  const ManagerialDashboardPlannedIndicator({
    required this.title,
    required this.reason,
  });

  final String title;
  final String reason;
}

class ManagerialDashboardReadiness {
  const ManagerialDashboardReadiness({
    required this.title,
    required this.message,
    required this.sourceLabel,
    required this.plannedIndicators,
  });

  final String title;
  final String message;
  final String sourceLabel;
  final List<ManagerialDashboardPlannedIndicator> plannedIndicators;
}
