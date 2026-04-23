class AdminHybridGovernanceQuery {
  const AdminHybridGovernanceQuery({required this.companyId});

  final String companyId;

  Map<String, String> toQueryParameters() {
    return <String, String>{'companyId': companyId};
  }

  @override
  bool operator ==(Object other) {
    return other is AdminHybridGovernanceQuery && other.companyId == companyId;
  }

  @override
  int get hashCode => companyId.hashCode;
}

class AdminHybridGovernanceProfile {
  const AdminHybridGovernanceProfile({
    required this.requireCategoryForGovernedCatalog,
    required this.requireVariantSku,
    required this.requireRemoteImageForGovernedCatalog,
    required this.allowOfflinePriceOverride,
    required this.allowLocalCatalogDeactivation,
    required this.minMarginBasisPoints,
    required this.maxOfflineDiscountBasisPoints,
    required this.pricePolicyMode,
    required this.stockDivergenceAlertThresholdMil,
    required this.allowOfflineStockAdjustments,
    required this.requireStockReconciliationReview,
    required this.customerMasterMode,
    required this.allowOperationalCustomerNotes,
    required this.allowOperationalCustomerAddressOverride,
    required this.requireCustomerConflictReview,
    required this.promotionMode,
    required this.allowPromotionStacking,
    required this.requireGovernedPriceForPromotion,
    required this.alertOnCatalogDrift,
    required this.alertOnStockDivergence,
    required this.alertOnCustomerConflict,
    required this.createdAt,
    required this.updatedAt,
  });

  final bool requireCategoryForGovernedCatalog;
  final bool requireVariantSku;
  final bool requireRemoteImageForGovernedCatalog;
  final bool allowOfflinePriceOverride;
  final bool allowLocalCatalogDeactivation;
  final int minMarginBasisPoints;
  final int maxOfflineDiscountBasisPoints;
  final String pricePolicyMode;
  final int stockDivergenceAlertThresholdMil;
  final bool allowOfflineStockAdjustments;
  final bool requireStockReconciliationReview;
  final String customerMasterMode;
  final bool allowOperationalCustomerNotes;
  final bool allowOperationalCustomerAddressOverride;
  final bool requireCustomerConflictReview;
  final String promotionMode;
  final bool allowPromotionStacking;
  final bool requireGovernedPriceForPromotion;
  final bool alertOnCatalogDrift;
  final bool alertOnStockDivergence;
  final bool alertOnCustomerConflict;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory AdminHybridGovernanceProfile.fromMap(Map<String, dynamic> map) {
    return AdminHybridGovernanceProfile(
      requireCategoryForGovernedCatalog:
          map['requireCategoryForGovernedCatalog'] == true,
      requireVariantSku: map['requireVariantSku'] == true,
      requireRemoteImageForGovernedCatalog:
          map['requireRemoteImageForGovernedCatalog'] == true,
      allowOfflinePriceOverride: map['allowOfflinePriceOverride'] == true,
      allowLocalCatalogDeactivation:
          map['allowLocalCatalogDeactivation'] == true,
      minMarginBasisPoints: _readOptionalInt(map, 'minMarginBasisPoints') ?? 0,
      maxOfflineDiscountBasisPoints:
          _readOptionalInt(map, 'maxOfflineDiscountBasisPoints') ?? 0,
      pricePolicyMode: _readString(
        map,
        'pricePolicyMode',
        fallback: 'advisory',
      ),
      stockDivergenceAlertThresholdMil:
          _readOptionalInt(map, 'stockDivergenceAlertThresholdMil') ?? 0,
      allowOfflineStockAdjustments: map['allowOfflineStockAdjustments'] == true,
      requireStockReconciliationReview:
          map['requireStockReconciliationReview'] == true,
      customerMasterMode: _readString(
        map,
        'customerMasterMode',
        fallback: 'cloud_master',
      ),
      allowOperationalCustomerNotes:
          map['allowOperationalCustomerNotes'] == true,
      allowOperationalCustomerAddressOverride:
          map['allowOperationalCustomerAddressOverride'] == true,
      requireCustomerConflictReview:
          map['requireCustomerConflictReview'] == true,
      promotionMode: _readString(
        map,
        'promotionMode',
        fallback: 'manual_preview',
      ),
      allowPromotionStacking: map['allowPromotionStacking'] == true,
      requireGovernedPriceForPromotion:
          map['requireGovernedPriceForPromotion'] == true,
      alertOnCatalogDrift: map['alertOnCatalogDrift'] == true,
      alertOnStockDivergence: map['alertOnStockDivergence'] == true,
      alertOnCustomerConflict: map['alertOnCustomerConflict'] == true,
      createdAt: _readOptionalDateTime(map, 'createdAt'),
      updatedAt: _readOptionalDateTime(map, 'updatedAt'),
    );
  }

  Map<String, dynamic> toUpdateBody(String companyId) {
    return <String, dynamic>{
      'companyId': companyId,
      'requireCategoryForGovernedCatalog': requireCategoryForGovernedCatalog,
      'requireVariantSku': requireVariantSku,
      'requireRemoteImageForGovernedCatalog':
          requireRemoteImageForGovernedCatalog,
      'allowOfflinePriceOverride': allowOfflinePriceOverride,
      'allowLocalCatalogDeactivation': allowLocalCatalogDeactivation,
      'minMarginBasisPoints': minMarginBasisPoints,
      'maxOfflineDiscountBasisPoints': maxOfflineDiscountBasisPoints,
      'pricePolicyMode': pricePolicyMode,
      'stockDivergenceAlertThresholdMil': stockDivergenceAlertThresholdMil,
      'allowOfflineStockAdjustments': allowOfflineStockAdjustments,
      'requireStockReconciliationReview': requireStockReconciliationReview,
      'customerMasterMode': customerMasterMode,
      'allowOperationalCustomerNotes': allowOperationalCustomerNotes,
      'allowOperationalCustomerAddressOverride':
          allowOperationalCustomerAddressOverride,
      'requireCustomerConflictReview': requireCustomerConflictReview,
      'promotionMode': promotionMode,
      'allowPromotionStacking': allowPromotionStacking,
      'requireGovernedPriceForPromotion': requireGovernedPriceForPromotion,
      'alertOnCatalogDrift': alertOnCatalogDrift,
      'alertOnStockDivergence': alertOnStockDivergence,
      'alertOnCustomerConflict': alertOnCustomerConflict,
    };
  }

  AdminHybridGovernanceProfile copyWith({
    bool? requireCategoryForGovernedCatalog,
    bool? requireVariantSku,
    bool? requireRemoteImageForGovernedCatalog,
    bool? allowOfflinePriceOverride,
    bool? allowLocalCatalogDeactivation,
    int? minMarginBasisPoints,
    int? maxOfflineDiscountBasisPoints,
    String? pricePolicyMode,
    int? stockDivergenceAlertThresholdMil,
    bool? allowOfflineStockAdjustments,
    bool? requireStockReconciliationReview,
    String? customerMasterMode,
    bool? allowOperationalCustomerNotes,
    bool? allowOperationalCustomerAddressOverride,
    bool? requireCustomerConflictReview,
    String? promotionMode,
    bool? allowPromotionStacking,
    bool? requireGovernedPriceForPromotion,
    bool? alertOnCatalogDrift,
    bool? alertOnStockDivergence,
    bool? alertOnCustomerConflict,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AdminHybridGovernanceProfile(
      requireCategoryForGovernedCatalog:
          requireCategoryForGovernedCatalog ??
          this.requireCategoryForGovernedCatalog,
      requireVariantSku: requireVariantSku ?? this.requireVariantSku,
      requireRemoteImageForGovernedCatalog:
          requireRemoteImageForGovernedCatalog ??
          this.requireRemoteImageForGovernedCatalog,
      allowOfflinePriceOverride:
          allowOfflinePriceOverride ?? this.allowOfflinePriceOverride,
      allowLocalCatalogDeactivation:
          allowLocalCatalogDeactivation ?? this.allowLocalCatalogDeactivation,
      minMarginBasisPoints: minMarginBasisPoints ?? this.minMarginBasisPoints,
      maxOfflineDiscountBasisPoints:
          maxOfflineDiscountBasisPoints ?? this.maxOfflineDiscountBasisPoints,
      pricePolicyMode: pricePolicyMode ?? this.pricePolicyMode,
      stockDivergenceAlertThresholdMil:
          stockDivergenceAlertThresholdMil ??
          this.stockDivergenceAlertThresholdMil,
      allowOfflineStockAdjustments:
          allowOfflineStockAdjustments ?? this.allowOfflineStockAdjustments,
      requireStockReconciliationReview:
          requireStockReconciliationReview ??
          this.requireStockReconciliationReview,
      customerMasterMode: customerMasterMode ?? this.customerMasterMode,
      allowOperationalCustomerNotes:
          allowOperationalCustomerNotes ?? this.allowOperationalCustomerNotes,
      allowOperationalCustomerAddressOverride:
          allowOperationalCustomerAddressOverride ??
          this.allowOperationalCustomerAddressOverride,
      requireCustomerConflictReview:
          requireCustomerConflictReview ?? this.requireCustomerConflictReview,
      promotionMode: promotionMode ?? this.promotionMode,
      allowPromotionStacking:
          allowPromotionStacking ?? this.allowPromotionStacking,
      requireGovernedPriceForPromotion:
          requireGovernedPriceForPromotion ??
          this.requireGovernedPriceForPromotion,
      alertOnCatalogDrift: alertOnCatalogDrift ?? this.alertOnCatalogDrift,
      alertOnStockDivergence:
          alertOnStockDivergence ?? this.alertOnStockDivergence,
      alertOnCustomerConflict:
          alertOnCustomerConflict ?? this.alertOnCustomerConflict,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class AdminHybridGovernanceCompanyRef {
  const AdminHybridGovernanceCompanyRef({
    required this.id,
    required this.name,
    required this.slug,
  });

  final String id;
  final String name;
  final String slug;

  factory AdminHybridGovernanceCompanyRef.fromMap(Map<String, dynamic> map) {
    return AdminHybridGovernanceCompanyRef(
      id: _readString(map, 'id'),
      name: _readString(map, 'name'),
      slug: _readString(map, 'slug'),
    );
  }
}

class AdminHybridGovernanceCapabilities {
  const AdminHybridGovernanceCapabilities({
    required this.remoteImageMirrorAvailable,
    required this.localStockTelemetryAvailable,
    required this.futurePromotionEngineReady,
  });

  final bool remoteImageMirrorAvailable;
  final bool localStockTelemetryAvailable;
  final bool futurePromotionEngineReady;

  factory AdminHybridGovernanceCapabilities.fromMap(Map<String, dynamic> map) {
    return AdminHybridGovernanceCapabilities(
      remoteImageMirrorAvailable: map['remoteImageMirrorAvailable'] == true,
      localStockTelemetryAvailable: map['localStockTelemetryAvailable'] == true,
      futurePromotionEngineReady: map['futurePromotionEngineReady'] == true,
    );
  }
}

class AdminHybridGovernanceTruthRule {
  const AdminHybridGovernanceTruthRule({
    required this.domain,
    required this.operationalSource,
    required this.cloudSource,
    required this.conflictPolicy,
    required this.offlineBehavior,
  });

  final String domain;
  final String operationalSource;
  final String cloudSource;
  final String conflictPolicy;
  final String offlineBehavior;

  factory AdminHybridGovernanceTruthRule.fromMap(Map<String, dynamic> map) {
    return AdminHybridGovernanceTruthRule(
      domain: _readString(map, 'domain'),
      operationalSource: _readString(map, 'operationalSource'),
      cloudSource: _readString(map, 'cloudSource'),
      conflictPolicy: _readString(map, 'conflictPolicy'),
      offlineBehavior: _readString(map, 'offlineBehavior'),
    );
  }
}

class AdminHybridCatalogOverview {
  const AdminHybridCatalogOverview({
    required this.totalProducts,
    required this.activeProducts,
    required this.activeCategories,
    required this.variantProducts,
    required this.productsWithoutCategory,
    required this.productsWithBlankVariantSku,
    required this.remoteImageMirrorAvailable,
    required this.imageGovernanceStatus,
    required this.governanceReadiness,
  });

  final int totalProducts;
  final int activeProducts;
  final int activeCategories;
  final int variantProducts;
  final int productsWithoutCategory;
  final int productsWithBlankVariantSku;
  final bool remoteImageMirrorAvailable;
  final String imageGovernanceStatus;
  final String governanceReadiness;

  factory AdminHybridCatalogOverview.fromMap(Map<String, dynamic> map) {
    return AdminHybridCatalogOverview(
      totalProducts: _readOptionalInt(map, 'totalProducts') ?? 0,
      activeProducts: _readOptionalInt(map, 'activeProducts') ?? 0,
      activeCategories: _readOptionalInt(map, 'activeCategories') ?? 0,
      variantProducts: _readOptionalInt(map, 'variantProducts') ?? 0,
      productsWithoutCategory:
          _readOptionalInt(map, 'productsWithoutCategory') ?? 0,
      productsWithBlankVariantSku:
          _readOptionalInt(map, 'productsWithBlankVariantSku') ?? 0,
      remoteImageMirrorAvailable: map['remoteImageMirrorAvailable'] == true,
      imageGovernanceStatus: _readString(
        map,
        'imageGovernanceStatus',
        fallback: 'not_mirrored_to_cloud',
      ),
      governanceReadiness: _readString(
        map,
        'governanceReadiness',
        fallback: 'not_seeded',
      ),
    );
  }
}

class AdminHybridPricingOverview {
  const AdminHybridPricingOverview({
    required this.pricedProductsCount,
    required this.productsBelowMarginPolicy,
    required this.lowestMarginBasisPoints,
    required this.minMarginBasisPoints,
    required this.maxOfflineDiscountBasisPoints,
    required this.allowOfflinePriceOverride,
    required this.policyMode,
  });

  final int pricedProductsCount;
  final int productsBelowMarginPolicy;
  final int? lowestMarginBasisPoints;
  final int minMarginBasisPoints;
  final int maxOfflineDiscountBasisPoints;
  final bool allowOfflinePriceOverride;
  final String policyMode;

  factory AdminHybridPricingOverview.fromMap(Map<String, dynamic> map) {
    return AdminHybridPricingOverview(
      pricedProductsCount: _readOptionalInt(map, 'pricedProductsCount') ?? 0,
      productsBelowMarginPolicy:
          _readOptionalInt(map, 'productsBelowMarginPolicy') ?? 0,
      lowestMarginBasisPoints: _readOptionalInt(map, 'lowestMarginBasisPoints'),
      minMarginBasisPoints: _readOptionalInt(map, 'minMarginBasisPoints') ?? 0,
      maxOfflineDiscountBasisPoints:
          _readOptionalInt(map, 'maxOfflineDiscountBasisPoints') ?? 0,
      allowOfflinePriceOverride: map['allowOfflinePriceOverride'] == true,
      policyMode: _readString(map, 'policyMode', fallback: 'advisory'),
    );
  }
}

class AdminHybridStockOverview {
  const AdminHybridStockOverview({
    required this.totalCloudStockMil,
    required this.productsWithoutCloudStock,
    required this.variantAggregationMismatchCount,
    required this.divergenceAlertThresholdMil,
    required this.localTelemetryAvailable,
    required this.reconciliationReadiness,
  });

  final int totalCloudStockMil;
  final int productsWithoutCloudStock;
  final int variantAggregationMismatchCount;
  final int divergenceAlertThresholdMil;
  final bool localTelemetryAvailable;
  final String reconciliationReadiness;

  factory AdminHybridStockOverview.fromMap(Map<String, dynamic> map) {
    return AdminHybridStockOverview(
      totalCloudStockMil: _readOptionalInt(map, 'totalCloudStockMil') ?? 0,
      productsWithoutCloudStock:
          _readOptionalInt(map, 'productsWithoutCloudStock') ?? 0,
      variantAggregationMismatchCount:
          _readOptionalInt(map, 'variantAggregationMismatchCount') ?? 0,
      divergenceAlertThresholdMil:
          _readOptionalInt(map, 'divergenceAlertThresholdMil') ?? 0,
      localTelemetryAvailable: map['localTelemetryAvailable'] == true,
      reconciliationReadiness: _readString(
        map,
        'reconciliationReadiness',
        fallback: 'requires_future_local_snapshot',
      ),
    );
  }
}

class AdminHybridCustomerOverview {
  const AdminHybridCustomerOverview({
    required this.totalCustomers,
    required this.activeCustomers,
    required this.customersWithoutPhone,
    required this.duplicatePhoneConflictCount,
    required this.duplicateNameConflictCount,
    required this.crmEnrichedCustomersCount,
    required this.masterMode,
  });

  final int totalCustomers;
  final int activeCustomers;
  final int customersWithoutPhone;
  final int duplicatePhoneConflictCount;
  final int duplicateNameConflictCount;
  final int crmEnrichedCustomersCount;
  final String masterMode;

  factory AdminHybridCustomerOverview.fromMap(Map<String, dynamic> map) {
    return AdminHybridCustomerOverview(
      totalCustomers: _readOptionalInt(map, 'totalCustomers') ?? 0,
      activeCustomers: _readOptionalInt(map, 'activeCustomers') ?? 0,
      customersWithoutPhone:
          _readOptionalInt(map, 'customersWithoutPhone') ?? 0,
      duplicatePhoneConflictCount:
          _readOptionalInt(map, 'duplicatePhoneConflictCount') ?? 0,
      duplicateNameConflictCount:
          _readOptionalInt(map, 'duplicateNameConflictCount') ?? 0,
      crmEnrichedCustomersCount:
          _readOptionalInt(map, 'crmEnrichedCustomersCount') ?? 0,
      masterMode: _readString(map, 'masterMode', fallback: 'cloud_master'),
    );
  }
}

class AdminHybridGovernanceAlert {
  const AdminHybridGovernanceAlert({
    required this.code,
    required this.domain,
    required this.severity,
    required this.title,
    required this.summary,
    required this.count,
  });

  final String code;
  final String domain;
  final String severity;
  final String title;
  final String summary;
  final int count;

  factory AdminHybridGovernanceAlert.fromMap(Map<String, dynamic> map) {
    return AdminHybridGovernanceAlert(
      code: _readString(map, 'code'),
      domain: _readString(map, 'domain'),
      severity: _readString(map, 'severity'),
      title: _readString(map, 'title'),
      summary: _readString(map, 'summary'),
      count: _readOptionalInt(map, 'count') ?? 0,
    );
  }
}

class AdminHybridGovernanceOverview {
  const AdminHybridGovernanceOverview({
    required this.company,
    required this.profile,
    required this.capabilities,
    required this.truthRules,
    required this.catalog,
    required this.pricing,
    required this.stock,
    required this.customers,
    required this.alerts,
  });

  final AdminHybridGovernanceCompanyRef company;
  final AdminHybridGovernanceProfile profile;
  final AdminHybridGovernanceCapabilities capabilities;
  final List<AdminHybridGovernanceTruthRule> truthRules;
  final AdminHybridCatalogOverview catalog;
  final AdminHybridPricingOverview pricing;
  final AdminHybridStockOverview stock;
  final AdminHybridCustomerOverview customers;
  final List<AdminHybridGovernanceAlert> alerts;

  factory AdminHybridGovernanceOverview.fromMap(Map<String, dynamic> map) {
    return AdminHybridGovernanceOverview(
      company: AdminHybridGovernanceCompanyRef.fromMap(
        _readMap(map, 'company'),
      ),
      profile: AdminHybridGovernanceProfile.fromMap(_readMap(map, 'profile')),
      capabilities: AdminHybridGovernanceCapabilities.fromMap(
        _readMap(map, 'capabilities'),
      ),
      truthRules: _readList(
        map,
        'truthRules',
      ).map(AdminHybridGovernanceTruthRule.fromMap).toList(),
      catalog: AdminHybridCatalogOverview.fromMap(_readMap(map, 'catalog')),
      pricing: AdminHybridPricingOverview.fromMap(_readMap(map, 'pricing')),
      stock: AdminHybridStockOverview.fromMap(_readMap(map, 'stock')),
      customers: AdminHybridCustomerOverview.fromMap(
        _readMap(map, 'customers'),
      ),
      alerts: _readList(
        map,
        'alerts',
      ).map(AdminHybridGovernanceAlert.fromMap).toList(),
    );
  }
}

Map<String, dynamic> _readMap(
  Map<String, dynamic> map,
  String key, {
  Map<String, dynamic>? fallback,
}) {
  final value = map[key];
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (fallback != null) {
    return fallback;
  }
  throw FormatException(
    'Campo "$key" ausente no payload de governanca hibrida.',
  );
}

List<Map<String, dynamic>> _readList(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! List<dynamic>) {
    return const <Map<String, dynamic>>[];
  }
  return value.whereType<Map<String, dynamic>>().toList(growable: false);
}

String _readString(Map<String, dynamic> map, String key, {String? fallback}) {
  final value = map[key];
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  if (fallback != null) {
    return fallback;
  }
  throw FormatException(
    'Campo "$key" ausente no payload de governanca hibrida.',
  );
}

int? _readOptionalInt(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String && value.trim().isNotEmpty) {
    return int.tryParse(value.trim());
  }
  return null;
}

DateTime? _readOptionalDateTime(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is String && value.trim().isNotEmpty) {
    return DateTime.tryParse(value.trim());
  }
  return null;
}
