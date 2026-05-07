enum PlanKey {
  free('FREE'),
  basic('BASIC'),
  pro('PRO');

  const PlanKey(this.key);

  final String key;

  static PlanKey normalize(Object? rawValue) {
    final normalized = rawValue?.toString().trim().toLowerCase();
    switch (normalized) {
      case 'basic':
        return PlanKey.basic;
      case 'pro':
        return PlanKey.pro;
      case 'free':
      case 'trial':
      default:
        return PlanKey.free;
    }
  }
}

enum FeatureKey {
  sales('sales'),
  cash('cash'),
  products('products'),
  categories('categories'),
  customersBasic('customersBasic'),
  fiadoCreateSale('fiadoCreateSale'),
  fiadoManagement('fiadoManagement'),
  supplies('supplies'),
  costs('costs'),
  suppliers('suppliers'),
  purchases('purchases'),
  inventoryBasic('inventoryBasic'),
  inventoryAdvanced('inventoryAdvanced'),
  reportsDaily('reportsDaily'),
  reportsBasic('reportsBasic'),
  reportsAdvanced('reportsAdvanced'),
  employees('employees'),
  permissions('permissions'),
  multiDevice('multiDevice'),
  ownerWebPanel('ownerWebPanel'),
  commissions('commissions'),
  devicesManagement('devicesManagement');

  const FeatureKey(this.key);

  final String key;

  static FeatureKey? fromKey(Object? rawValue) {
    final normalized = rawValue?.toString().trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    for (final feature in FeatureKey.values) {
      if (feature.key == normalized) {
        return feature;
      }
    }
    return null;
  }
}

enum ReportPeriodKey {
  daily('daily'),
  weekly('weekly'),
  monthly('monthly'),
  yearly('yearly'),
  custom('custom');

  const ReportPeriodKey(this.key);

  final String key;

  static ReportPeriodKey? fromKey(Object? rawValue) {
    final normalized = rawValue?.toString().trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    for (final period in ReportPeriodKey.values) {
      if (period.key == normalized) {
        return period;
      }
    }
    return null;
  }
}

class PlanLimits {
  const PlanLimits({
    required this.maxDevices,
    required this.maxEmployees,
    required this.reportPeriods,
  });

  final int maxDevices;
  final int maxEmployees;
  final Set<ReportPeriodKey> reportPeriods;

  bool allowsReportPeriod(ReportPeriodKey period) {
    return reportPeriods.contains(period);
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'maxDevices': maxDevices,
      'maxEmployees': maxEmployees,
      'reportPeriods': reportPeriods.map((period) => period.key).toList(),
    };
  }

  static PlanLimits fromJson(
    Map<String, dynamic>? source, {
    required PlanKey fallbackPlan,
  }) {
    final fallback = PlanEntitlements.catalogFor(fallbackPlan).limits;
    if (source == null) {
      return fallback;
    }

    final reportPeriods = <ReportPeriodKey>{
      for (final rawPeriod in _readList(source['reportPeriods']))
        if (ReportPeriodKey.fromKey(rawPeriod) case final period?) period,
    };

    return PlanLimits(
      maxDevices: _readPositiveInt(source['maxDevices']) ?? fallback.maxDevices,
      maxEmployees:
          _readNonNegativeInt(source['maxEmployees']) ?? fallback.maxEmployees,
      reportPeriods: reportPeriods.isEmpty
          ? fallback.reportPeriods
          : Set<ReportPeriodKey>.unmodifiable(reportPeriods),
    );
  }

  static int? _readPositiveInt(Object? rawValue) {
    final value = _readInt(rawValue);
    if (value == null || value <= 0) {
      return null;
    }
    return value;
  }

  static int? _readNonNegativeInt(Object? rawValue) {
    final value = _readInt(rawValue);
    if (value == null || value < 0) {
      return null;
    }
    return value;
  }

  static int? _readInt(Object? rawValue) {
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

  static Iterable<Object?> _readList(Object? rawValue) {
    if (rawValue is Iterable) {
      return rawValue.cast<Object?>();
    }
    return const <Object?>[];
  }
}

class PlanEntitlements {
  const PlanEntitlements({
    required this.plan,
    required this.features,
    required this.limits,
  });

  final PlanKey plan;
  final Set<FeatureKey> features;
  final PlanLimits limits;

  static const free = PlanEntitlements(
    plan: PlanKey.free,
    features: _freeFeatures,
    limits: PlanLimits(
      maxDevices: 1,
      maxEmployees: 0,
      reportPeriods: <ReportPeriodKey>{ReportPeriodKey.daily},
    ),
  );

  static const basic = PlanEntitlements(
    plan: PlanKey.basic,
    features: _basicFeatures,
    limits: PlanLimits(
      maxDevices: 1,
      maxEmployees: 0,
      reportPeriods: <ReportPeriodKey>{
        ReportPeriodKey.daily,
        ReportPeriodKey.weekly,
        ReportPeriodKey.monthly,
      },
    ),
  );

  static const pro = PlanEntitlements(
    plan: PlanKey.pro,
    features: _allFeatures,
    limits: PlanLimits(
      maxDevices: 100,
      maxEmployees: 100,
      reportPeriods: <ReportPeriodKey>{
        ReportPeriodKey.daily,
        ReportPeriodKey.weekly,
        ReportPeriodKey.monthly,
        ReportPeriodKey.yearly,
        ReportPeriodKey.custom,
      },
    ),
  );

  bool hasFeature(FeatureKey feature) {
    return features.contains(feature);
  }

  bool allowsReportPeriod(ReportPeriodKey period) {
    return limits.allowsReportPeriod(period);
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'plan': plan.key,
      'features': <String, bool>{
        for (final feature in FeatureKey.values)
          feature.key: features.contains(feature),
      },
      'limits': limits.toJson(),
    };
  }

  static PlanEntitlements freeFallback() => free;

  static PlanEntitlements catalogFor(PlanKey plan) {
    switch (plan) {
      case PlanKey.free:
        return free;
      case PlanKey.basic:
        return basic;
      case PlanKey.pro:
        return pro;
    }
  }

  static PlanKey? requiredPlanForFeature(FeatureKey feature) {
    for (final plan in PlanKey.values) {
      if (catalogFor(plan).hasFeature(feature)) {
        return plan;
      }
    }
    return null;
  }

  static PlanEntitlements fromBootstrapJson(Map<String, dynamic> source) {
    final hasEntitlementPayload =
        source.containsKey('plan') ||
        source.containsKey('features') ||
        source.containsKey('limits');
    if (!hasEntitlementPayload) {
      return freeFallback();
    }
    return fromJson(source);
  }

  static PlanEntitlements fromJson(Map<String, dynamic> source) {
    final plan = PlanKey.normalize(source['plan']);
    final fallback = catalogFor(plan);
    final rawFeatures = source['features'];
    final enabledFeatures = <FeatureKey>{};

    if (rawFeatures is Map) {
      for (final feature in FeatureKey.values) {
        if (rawFeatures[feature.key] == true) {
          enabledFeatures.add(feature);
        }
      }
    } else {
      enabledFeatures.addAll(fallback.features);
    }

    return PlanEntitlements(
      plan: plan,
      features: Set<FeatureKey>.unmodifiable(enabledFeatures),
      limits: PlanLimits.fromJson(
        source['limits'] is Map<String, dynamic>
            ? source['limits'] as Map<String, dynamic>
            : source['limits'] is Map
            ? Map<String, dynamic>.from(source['limits'] as Map)
            : null,
        fallbackPlan: plan,
      ),
    );
  }
}

const _freeFeatures = <FeatureKey>{
  FeatureKey.sales,
  FeatureKey.cash,
  FeatureKey.products,
  FeatureKey.categories,
  FeatureKey.customersBasic,
  FeatureKey.fiadoCreateSale,
  FeatureKey.reportsDaily,
  FeatureKey.inventoryBasic,
};

const _basicFeatures = <FeatureKey>{
  ..._freeFeatures,
  FeatureKey.fiadoManagement,
  FeatureKey.supplies,
  FeatureKey.costs,
  FeatureKey.suppliers,
  FeatureKey.purchases,
  FeatureKey.inventoryAdvanced,
  FeatureKey.reportsBasic,
};

const _allFeatures = <FeatureKey>{
  FeatureKey.sales,
  FeatureKey.cash,
  FeatureKey.products,
  FeatureKey.categories,
  FeatureKey.customersBasic,
  FeatureKey.fiadoCreateSale,
  FeatureKey.fiadoManagement,
  FeatureKey.supplies,
  FeatureKey.costs,
  FeatureKey.suppliers,
  FeatureKey.purchases,
  FeatureKey.inventoryBasic,
  FeatureKey.inventoryAdvanced,
  FeatureKey.reportsDaily,
  FeatureKey.reportsBasic,
  FeatureKey.reportsAdvanced,
  FeatureKey.employees,
  FeatureKey.permissions,
  FeatureKey.multiDevice,
  FeatureKey.ownerWebPanel,
  FeatureKey.commissions,
  FeatureKey.devicesManagement,
};
