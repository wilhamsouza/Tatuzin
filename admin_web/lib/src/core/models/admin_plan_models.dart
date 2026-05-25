class AdminPlansOverview {
  const AdminPlansOverview({
    required this.items,
    required this.features,
    required this.usageSummary,
    required this.rules,
  });

  final List<AdminPlanCatalogItem> items;
  final List<AdminPlanFeature> features;
  final AdminPlansUsageSummary usageSummary;
  final AdminPlanRules rules;

  factory AdminPlansOverview.fromMap(Map<String, dynamic> map) {
    return AdminPlansOverview(
      items: _readList(
        map,
        'items',
      ).map(AdminPlanCatalogItem.fromMap).toList(growable: false),
      features: _readList(
        map,
        'features',
      ).map(AdminPlanFeature.fromMap).toList(growable: false),
      usageSummary: AdminPlansUsageSummary.fromMap(
        _readMap(map, 'usageSummary'),
      ),
      rules: AdminPlanRules.fromMap(_readMap(map, 'rules')),
    );
  }
}

class AdminPlanCatalogItem {
  const AdminPlanCatalogItem({
    required this.key,
    required this.name,
    required this.description,
    required this.priceCents,
    required this.currency,
    required this.billingCycle,
    required this.featuresSummary,
    required this.entitlements,
    required this.usage,
    required this.status,
    required this.isPublic,
    required this.observations,
  });

  final String key;
  final String name;
  final String? description;
  final int? priceCents;
  final String? currency;
  final String? billingCycle;
  final List<String> featuresSummary;
  final AdminPlanEntitlements entitlements;
  final AdminPlanUsage usage;
  final String status;
  final bool isPublic;
  final List<String> observations;

  factory AdminPlanCatalogItem.fromMap(Map<String, dynamic> map) {
    return AdminPlanCatalogItem(
      key: _readString(map, 'key', fallback: 'FREE'),
      name: _readString(map, 'name', fallback: 'Plano'),
      description: _readOptionalString(map, 'description'),
      priceCents: _readInt(map, 'priceCents'),
      currency: _readOptionalString(map, 'currency'),
      billingCycle: _readOptionalString(map, 'billingCycle'),
      featuresSummary: _readStringList(map, 'featuresSummary'),
      entitlements: AdminPlanEntitlements.fromMap(
        _readMap(map, 'entitlements'),
      ),
      usage: AdminPlanUsage.fromMap(_readMap(map, 'usage')),
      status: _readString(map, 'status', fallback: 'ACTIVE'),
      isPublic: map['isPublic'] != false,
      observations: _readStringList(map, 'observations'),
    );
  }

  bool hasFeature(String featureKey) {
    return entitlements.features[featureKey] == true;
  }
}

class AdminPlanEntitlements {
  const AdminPlanEntitlements({
    required this.plan,
    required this.features,
    required this.limits,
  });

  final String plan;
  final Map<String, bool> features;
  final AdminPlanLimits limits;

  factory AdminPlanEntitlements.fromMap(Map<String, dynamic> map) {
    final rawFeatures = _readMap(map, 'features');
    return AdminPlanEntitlements(
      plan: _readString(map, 'plan', fallback: 'FREE'),
      features: rawFeatures.map((key, value) => MapEntry(key, value == true)),
      limits: AdminPlanLimits.fromMap(_readMap(map, 'limits')),
    );
  }
}

class AdminPlanLimits {
  const AdminPlanLimits({
    required this.maxDevices,
    required this.maxEmployees,
    required this.reportPeriods,
  });

  final int? maxDevices;
  final int? maxEmployees;
  final List<String> reportPeriods;

  factory AdminPlanLimits.fromMap(Map<String, dynamic> map) {
    return AdminPlanLimits(
      maxDevices: _readInt(map, 'maxDevices'),
      maxEmployees: _readInt(map, 'maxEmployees'),
      reportPeriods: _readStringList(map, 'reportPeriods'),
    );
  }
}

class AdminPlanUsage {
  const AdminPlanUsage({
    required this.companiesCount,
    required this.activeCompaniesCount,
    required this.pendingPlanCount,
  });

  final int? companiesCount;
  final int? activeCompaniesCount;
  final int? pendingPlanCount;

  factory AdminPlanUsage.fromMap(Map<String, dynamic> map) {
    return AdminPlanUsage(
      companiesCount: _readInt(map, 'companiesCount'),
      activeCompaniesCount: _readInt(map, 'activeCompaniesCount'),
      pendingPlanCount: _readInt(map, 'pendingPlanCount'),
    );
  }
}

class AdminPlanFeature {
  const AdminPlanFeature({required this.key, required this.requiredPlan});

  final String key;
  final String? requiredPlan;

  factory AdminPlanFeature.fromMap(Map<String, dynamic> map) {
    return AdminPlanFeature(
      key: _readString(map, 'key'),
      requiredPlan: _readOptionalString(map, 'requiredPlan'),
    );
  }
}

class AdminPlansUsageSummary {
  const AdminPlansUsageSummary({
    required this.totalPlans,
    required this.companiesByPlan,
    required this.activeCompaniesByPlan,
    required this.pendingCompaniesByPlan,
    required this.pendingPlanCount,
    required this.plansWithActiveCompanies,
  });

  final int? totalPlans;
  final Map<String, int> companiesByPlan;
  final Map<String, int> activeCompaniesByPlan;
  final Map<String, int> pendingCompaniesByPlan;
  final int? pendingPlanCount;
  final int? plansWithActiveCompanies;

  factory AdminPlansUsageSummary.fromMap(Map<String, dynamic> map) {
    return AdminPlansUsageSummary(
      totalPlans: _readInt(map, 'totalPlans'),
      companiesByPlan: _readIntMap(map, 'companiesByPlan'),
      activeCompaniesByPlan: _readIntMap(map, 'activeCompaniesByPlan'),
      pendingCompaniesByPlan: _readIntMap(map, 'pendingCompaniesByPlan'),
      pendingPlanCount: _readInt(map, 'pendingPlanCount'),
      plansWithActiveCompanies: _readInt(map, 'plansWithActiveCompanies'),
    );
  }
}

class AdminPlanRules {
  const AdminPlanRules({
    required this.entitlementSource,
    required this.pendingPlanReleasesFeatures,
  });

  final String entitlementSource;
  final bool pendingPlanReleasesFeatures;

  factory AdminPlanRules.fromMap(Map<String, dynamic> map) {
    return AdminPlanRules(
      entitlementSource: _readString(
        map,
        'entitlementSource',
        fallback: 'license.plan',
      ),
      pendingPlanReleasesFeatures: map['pendingPlanReleasesFeatures'] == true,
    );
  }
}

List<Map<String, dynamic>> _readList(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! List) {
    return const <Map<String, dynamic>>[];
  }
  return value.whereType<Map<String, dynamic>>().toList(growable: false);
}

Map<String, dynamic> _readMap(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return const <String, dynamic>{};
}

Map<String, int> _readIntMap(Map<String, dynamic> map, String key) {
  final source = _readMap(map, key);
  return source.map((key, value) => MapEntry(key, _readIntValue(value) ?? 0));
}

String _readString(
  Map<String, dynamic> map,
  String key, {
  String fallback = '',
}) {
  final value = map[key]?.toString().trim();
  if (value == null || value.isEmpty) {
    return fallback;
  }
  return value;
}

String? _readOptionalString(Map<String, dynamic> map, String key) {
  final value = map[key]?.toString().trim();
  if (value == null || value.isEmpty) {
    return null;
  }
  return value;
}

int? _readInt(Map<String, dynamic> map, String key) {
  return _readIntValue(map[key]);
}

int? _readIntValue(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  return int.tryParse(value?.toString() ?? '');
}

List<String> _readStringList(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! List) {
    return const <String>[];
  }
  return value.map((item) => item.toString()).toList(growable: false);
}
