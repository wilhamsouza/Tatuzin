class OnboardingProgress {
  const OnboardingProgress({
    this.enabled = false,
    this.productReady = false,
    this.cashReady = false,
    this.completedAt,
  });

  factory OnboardingProgress.fromJson(Map<String, dynamic> json) =>
      OnboardingProgress(
        enabled: json['enabled'] == true,
        productReady: json['productReady'] == true,
        cashReady: json['cashReady'] == true,
        completedAt: DateTime.tryParse(json['completedAt'] as String? ?? ''),
      );

  final bool enabled;
  final bool productReady;
  final bool cashReady;
  final DateTime? completedAt;
  bool get completed => completedAt != null;
  int get completedSteps =>
      completed ? 3 : (productReady ? 1 : 0) + (cashReady ? 1 : 0);

  OnboardingProgress merge(OnboardingProgress other, {bool? enabled}) {
    final dates = [
      completedAt,
      other.completedAt,
    ].whereType<DateTime>().toList()..sort();
    return OnboardingProgress(
      enabled: enabled ?? (this.enabled || other.enabled),
      productReady: productReady || other.productReady || dates.isNotEmpty,
      cashReady: cashReady || other.cashReady || dates.isNotEmpty,
      completedAt: dates.firstOrNull,
    );
  }

  bool canOfferTrial(DateTime sessionStartedAt) =>
      !enabled ||
      (completedAt != null && completedAt!.isBefore(sessionStartedAt));

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'productReady': productReady,
    'cashReady': cashReady,
    'completedAt': completedAt?.toUtc().toIso8601String(),
  };
}
