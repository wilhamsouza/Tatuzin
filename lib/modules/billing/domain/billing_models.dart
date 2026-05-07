import '../../../app/core/entitlements/plan_entitlements.dart';

class BillingPlan {
  const BillingPlan({
    required this.key,
    required this.name,
    required this.priceCents,
    required this.currency,
    required this.billingCycle,
    required this.description,
    required this.featuresSummary,
  });

  final PlanKey key;
  final String name;
  final int priceCents;
  final String currency;
  final String billingCycle;
  final String description;
  final List<String> featuresSummary;

  factory BillingPlan.fromMap(Map<String, dynamic> source) {
    return BillingPlan(
      key: PlanKey.normalize(source['key']),
      name: _readString(source['name']) ?? 'Plano',
      priceCents: _readInt(source['priceCents']) ?? 0,
      currency: _readString(source['currency']) ?? 'BRL',
      billingCycle: _readString(source['billingCycle']) ?? 'monthly',
      description: _readString(source['description']) ?? '',
      featuresSummary: _readStringList(source['featuresSummary']),
    );
  }
}

class BillingStatus {
  const BillingStatus({
    required this.companyId,
    required this.plan,
    required this.status,
    required this.currentPeriodStart,
    required this.currentPeriodEnd,
    required this.expiresAt,
    required this.provider,
    required this.hasProviderSubscription,
    required this.maskedProviderSubscriptionId,
    required this.canManageBilling,
    required this.nextPaymentDate,
    required this.entitlements,
  });

  final String companyId;
  final PlanKey plan;
  final String status;
  final DateTime? currentPeriodStart;
  final DateTime? currentPeriodEnd;
  final DateTime? expiresAt;
  final String? provider;
  final bool hasProviderSubscription;
  final String? maskedProviderSubscriptionId;
  final bool canManageBilling;
  final DateTime? nextPaymentDate;
  final PlanEntitlements entitlements;

  factory BillingStatus.fromMap(Map<String, dynamic> source) {
    return BillingStatus(
      companyId: _readString(source['companyId']) ?? '',
      plan: PlanKey.normalize(source['plan']),
      status: _readString(source['status']) ?? 'ACTIVE',
      currentPeriodStart: _readDate(source['currentPeriodStart']),
      currentPeriodEnd: _readDate(source['currentPeriodEnd']),
      expiresAt: _readDate(source['expiresAt']),
      provider: _readString(source['provider']),
      hasProviderSubscription: source['hasProviderSubscription'] == true,
      maskedProviderSubscriptionId: _readString(
        source['maskedProviderSubscriptionId'],
      ),
      canManageBilling: source['canManageBilling'] == true,
      nextPaymentDate: _readDate(source['nextPaymentDate']),
      entitlements: PlanEntitlements.fromJson(source),
    );
  }
}

class BillingSubscribeResult {
  const BillingSubscribeResult({
    required this.checkoutUrl,
    required this.provider,
    required this.plan,
    required this.checkoutSessionId,
    required this.expiresAt,
  });

  final String? checkoutUrl;
  final String? provider;
  final PlanKey plan;
  final String? checkoutSessionId;
  final DateTime? expiresAt;

  factory BillingSubscribeResult.fromMap(Map<String, dynamic> source) {
    return BillingSubscribeResult(
      checkoutUrl: _readString(source['checkoutUrl']),
      provider: _readString(source['provider']),
      plan: PlanKey.normalize(source['plan']),
      checkoutSessionId: _readString(source['checkoutSessionId']),
      expiresAt: _readDate(source['expiresAt']),
    );
  }
}

String? _readString(Object? rawValue) {
  if (rawValue is! String) {
    return null;
  }
  final trimmed = rawValue.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int? _readInt(Object? rawValue) {
  if (rawValue is int) {
    return rawValue;
  }
  if (rawValue is num) {
    return rawValue.toInt();
  }
  if (rawValue is String && rawValue.trim().isNotEmpty) {
    return int.tryParse(rawValue.trim());
  }
  return null;
}

DateTime? _readDate(Object? rawValue) {
  final value = _readString(rawValue);
  return value == null ? null : DateTime.tryParse(value);
}

List<String> _readStringList(Object? rawValue) {
  if (rawValue is! Iterable) {
    return const <String>[];
  }
  return rawValue
      .whereType<String>()
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
}
