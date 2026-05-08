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
    this.pendingPlan,
    this.pendingPlanRequestedAt,
    this.cancelAtPeriodEnd = false,
    this.cancelRequestedAt,
    this.canceledAt,
    this.billingSubscriptionStatus,
    this.warnings = const <String>[],
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
  final PlanKey? pendingPlan;
  final DateTime? pendingPlanRequestedAt;
  final bool cancelAtPeriodEnd;
  final DateTime? cancelRequestedAt;
  final DateTime? canceledAt;
  final String? billingSubscriptionStatus;
  final List<String> warnings;

  factory BillingStatus.fromMap(Map<String, dynamic> source) {
    return BillingStatus(
      companyId: _readString(source['companyId']) ?? '',
      plan: PlanKey.normalize(source['plan']),
      status: _readString(source['status']) ?? 'ACTIVE',
      currentPeriodStart: _readDate(source['currentPeriodStart']),
      currentPeriodEnd: _readDate(source['currentPeriodEnd']),
      expiresAt: _readDate(source['expiresAt']),
      provider: _readString(source['provider']),
      hasProviderSubscription: _readBool(source['hasProviderSubscription']),
      maskedProviderSubscriptionId: _readString(
        source['maskedProviderSubscriptionId'],
      ),
      canManageBilling: source['canManageBilling'] == true,
      nextPaymentDate: _readDate(source['nextPaymentDate']),
      entitlements: PlanEntitlements.fromJson(source),
      pendingPlan: _readPlan(source['pendingPlan']),
      pendingPlanRequestedAt: _readDate(source['pendingPlanRequestedAt']),
      cancelAtPeriodEnd: _readBool(source['cancelAtPeriodEnd']),
      cancelRequestedAt: _readDate(source['cancelRequestedAt']),
      canceledAt: _readDate(source['canceledAt']),
      billingSubscriptionStatus: _readString(
        source['billingSubscriptionStatus'],
      ),
      warnings: _readStringList(source['warnings']),
    );
  }
}

class BillingInvoicesPage {
  const BillingInvoicesPage({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.total,
    required this.count,
    required this.hasNext,
    required this.hasPrevious,
  });

  final List<BillingInvoice> items;
  final int page;
  final int pageSize;
  final int total;
  final int count;
  final bool hasNext;
  final bool hasPrevious;

  factory BillingInvoicesPage.fromMap(Map<String, dynamic> source) {
    final rawItems = source['items'];
    final items = rawItems is Iterable
        ? rawItems
              .whereType<Map>()
              .map(
                (item) =>
                    BillingInvoice.fromMap(Map<String, dynamic>.from(item)),
              )
              .toList(growable: false)
        : const <BillingInvoice>[];

    return BillingInvoicesPage(
      items: items,
      page: _readInt(source['page']) ?? 1,
      pageSize: _readInt(source['pageSize']) ?? items.length,
      total: _readInt(source['total']) ?? items.length,
      count: _readInt(source['count']) ?? items.length,
      hasNext: _readBool(source['hasNext']),
      hasPrevious: _readBool(source['hasPrevious']),
    );
  }
}

class BillingInvoice {
  const BillingInvoice({
    required this.id,
    required this.provider,
    required this.status,
    required this.amountCents,
    required this.currency,
    required this.periodStart,
    required this.periodEnd,
    required this.dueAt,
    required this.paidAt,
    required this.failedAt,
    required this.invoiceUrl,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String? provider;
  final String status;
  final int amountCents;
  final String currency;
  final DateTime? periodStart;
  final DateTime? periodEnd;
  final DateTime? dueAt;
  final DateTime? paidAt;
  final DateTime? failedAt;
  final String? invoiceUrl;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory BillingInvoice.fromMap(Map<String, dynamic> source) {
    return BillingInvoice(
      id: _readString(source['id']) ?? '',
      provider: _readString(source['provider']),
      status: _readString(source['status']) ?? 'unknown',
      amountCents: _readInt(source['amountCents']) ?? 0,
      currency: _readString(source['currency']) ?? 'BRL',
      periodStart: _readDate(source['periodStart']),
      periodEnd: _readDate(source['periodEnd']),
      dueAt: _readDate(source['dueAt']),
      paidAt: _readDate(source['paidAt']),
      failedAt: _readDate(source['failedAt']),
      invoiceUrl: _readString(source['invoiceUrl']),
      createdAt: _readDate(source['createdAt']),
      updatedAt: _readDate(source['updatedAt']),
    );
  }
}

class BillingPaymentMethod {
  const BillingPaymentMethod({
    required this.provider,
    required this.hasPaymentMethod,
    required this.unavailable,
    required this.status,
    required this.paymentMethodId,
    required this.paymentMethodType,
    required this.lastFour,
    required this.nextPaymentDate,
    required this.maskedProviderSubscriptionId,
    required this.message,
  });

  final String? provider;
  final bool hasPaymentMethod;
  final bool unavailable;
  final String? status;
  final String? paymentMethodId;
  final String? paymentMethodType;
  final String? lastFour;
  final DateTime? nextPaymentDate;
  final String? maskedProviderSubscriptionId;
  final String? message;

  factory BillingPaymentMethod.fromMap(Map<String, dynamic> source) {
    return BillingPaymentMethod(
      provider: _readString(source['provider']),
      hasPaymentMethod: _readBool(source['hasPaymentMethod']),
      unavailable: _readBool(source['unavailable']),
      status: _readString(source['status']),
      paymentMethodId: _readString(source['paymentMethodId']),
      paymentMethodType: _readString(source['paymentMethodType']),
      lastFour: _readString(source['lastFour']),
      nextPaymentDate: _readDate(source['nextPaymentDate']),
      maskedProviderSubscriptionId: _readString(
        source['maskedProviderSubscriptionId'],
      ),
      message: _readString(source['message']),
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

class BillingActionResult {
  const BillingActionResult({
    required this.status,
    required this.providerCancelled,
    required this.effective,
    required this.requiresNewCheckout,
    required this.checkoutUrl,
    required this.checkoutSessionId,
    required this.message,
    required this.pendingPlan,
  });

  final BillingStatus? status;
  final bool providerCancelled;
  final String? effective;
  final bool requiresNewCheckout;
  final String? checkoutUrl;
  final String? checkoutSessionId;
  final String message;
  final PlanKey? pendingPlan;

  factory BillingActionResult.fromMap(Map<String, dynamic> source) {
    final rawStatus = source['status'];
    final parsedStatus = rawStatus is Map
        ? BillingStatus.fromMap(Map<String, dynamic>.from(rawStatus))
        : null;

    final checkoutUrl = _readString(source['checkoutUrl']);

    return BillingActionResult(
      status: parsedStatus,
      providerCancelled: _readBool(source['providerCancelled']),
      effective: _readString(source['effective']),
      requiresNewCheckout: _readBool(source['requiresNewCheckout']),
      checkoutUrl: checkoutUrl,
      checkoutSessionId: _readString(source['checkoutSessionId']),
      message:
          _readString(source['message']) ??
          (checkoutUrl == null
              ? 'Status da assinatura atualizado.'
              : 'Apos o pagamento, seu plano sera atualizado automaticamente.'),
      pendingPlan:
          _readPlan(source['pendingPlan']) ?? parsedStatus?.pendingPlan,
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

bool _readBool(Object? rawValue) {
  if (rawValue is bool) {
    return rawValue;
  }
  if (rawValue is String) {
    final normalized = rawValue.trim().toLowerCase();
    return normalized == 'true' || normalized == '1';
  }
  if (rawValue is num) {
    return rawValue != 0;
  }
  return false;
}

PlanKey? _readPlan(Object? rawValue) {
  final value = _readString(rawValue);
  if (value == null) {
    return null;
  }
  final normalized = PlanKey.normalize(value);
  return normalized.key == value.trim().toUpperCase() ? normalized : null;
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
