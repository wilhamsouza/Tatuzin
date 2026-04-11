import '../../domain/entities/product.dart';

class RemoteProductRecord {
  const RemoteProductRecord({
    required this.remoteId,
    required this.localUuid,
    required this.remoteCategoryId,
    required this.name,
    required this.description,
    required this.barcode,
    required this.productType,
    required this.niche,
    required this.catalogType,
    required this.modelName,
    required this.variantLabel,
    required this.unitMeasure,
    required this.costCents,
    required this.salePriceCents,
    required this.stockMil,
    this.variants = const <RemoteProductVariantRecord>[],
    this.modifierGroups = const <RemoteProductModifierGroupRecord>[],
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    required this.deletedAt,
  });

  factory RemoteProductRecord.fromJson(Map<String, dynamic> json) {
    final remoteId = json['id'] as String;
    return RemoteProductRecord(
      remoteId: remoteId,
      localUuid: (json['localUuid'] as String?)?.trim().isNotEmpty == true
          ? json['localUuid'] as String
          : remoteId,
      remoteCategoryId: json['categoryId'] as String?,
      name: json['name'] as String,
      description: json['description'] as String?,
      barcode: json['barcode'] as String?,
      productType: (json['productType'] as String?) ?? 'unidade',
      niche: ProductNiches.normalize(json['niche'] as String?),
      catalogType: ProductCatalogTypes.normalize(
        json['catalogType'] as String?,
      ),
      modelName: json['modelName'] as String?,
      variantLabel: json['variantLabel'] as String?,
      unitMeasure: (json['unitMeasure'] as String?) ?? 'un',
      costCents: json['costPriceCents'] as int? ?? 0,
      salePriceCents: json['salePriceCents'] as int? ?? 0,
      stockMil: json['stockMil'] as int? ?? 0,
      variants: ((json['variants'] as List<dynamic>?) ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(RemoteProductVariantRecord.fromJson)
          .toList(growable: false),
      modifierGroups:
          ((json['modifierGroups'] as List<dynamic>?) ?? const <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .map(RemoteProductModifierGroupRecord.fromJson)
              .toList(growable: false),
      isActive: (json['isActive'] as bool?) ?? true,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      deletedAt: json['deletedAt'] == null
          ? null
          : DateTime.parse(json['deletedAt'] as String),
    );
  }

  factory RemoteProductRecord.fromLocalProduct(
    Product product, {
    String? remoteCategoryId,
  }) {
    return RemoteProductRecord(
      remoteId: product.remoteId ?? '',
      localUuid: product.uuid,
      remoteCategoryId: remoteCategoryId,
      name: product.name,
      description: product.description,
      barcode: product.barcode,
      productType: product.productType,
      niche: product.niche,
      catalogType: product.catalogType,
      modelName: product.modelName,
      variantLabel: product.variantLabel,
      unitMeasure: product.unitMeasure,
      costCents: product.costCents,
      salePriceCents: product.salePriceCents,
      stockMil: product.stockMil,
      variants: product.variants
          .map(
            (variant) => RemoteProductVariantRecord.fromLocalVariant(variant),
          )
          .toList(growable: false),
      modifierGroups: product.modifierGroups
          .map(
            (group) => RemoteProductModifierGroupRecord.fromLocalGroup(group),
          )
          .toList(growable: false),
      isActive: product.isActive,
      createdAt: product.createdAt,
      updatedAt: product.updatedAt,
      deletedAt: product.deletedAt,
    );
  }

  final String remoteId;
  final String localUuid;
  final String? remoteCategoryId;
  final String name;
  final String? description;
  final String? barcode;
  final String productType;
  final String niche;
  final String catalogType;
  final String? modelName;
  final String? variantLabel;
  final String unitMeasure;
  final int costCents;
  final int salePriceCents;
  final int stockMil;
  final List<RemoteProductVariantRecord> variants;
  final List<RemoteProductModifierGroupRecord> modifierGroups;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  String get displayName {
    final resolvedModel = modelName?.trim();
    final resolvedVariant = variantLabel?.trim();
    if (catalogType == ProductCatalogTypes.variant &&
        resolvedModel != null &&
        resolvedModel.isNotEmpty &&
        resolvedVariant != null &&
        resolvedVariant.isNotEmpty) {
      return '$resolvedModel — $resolvedVariant';
    }
    return name;
  }

  Map<String, dynamic> toUpsertBody() {
    return <String, dynamic>{
      'localUuid': localUuid,
      'name': name,
      'categoryId': remoteCategoryId,
      'description': description,
      'barcode': barcode,
      'productType': productType,
      'niche': niche,
      'catalogType': catalogType,
      'modelName': modelName,
      'variantLabel': variantLabel,
      'unitMeasure': unitMeasure,
      'costPriceCents': costCents,
      'salePriceCents': salePriceCents,
      'stockMil': stockMil,
      'variants': variants.map((variant) => variant.toJson()).toList(),
      'modifierGroups': modifierGroups.map((group) => group.toJson()).toList(),
      'isActive': isActive,
      'deletedAt': deletedAt?.toIso8601String(),
    };
  }
}

class RemoteProductVariantRecord {
  const RemoteProductVariantRecord({
    required this.sku,
    required this.colorLabel,
    required this.sizeLabel,
    required this.priceAdditionalCents,
    required this.stockMil,
    required this.sortOrder,
    required this.isActive,
  });

  factory RemoteProductVariantRecord.fromJson(Map<String, dynamic> json) {
    return RemoteProductVariantRecord(
      sku: json['sku'] as String? ?? '',
      colorLabel: json['colorLabel'] as String? ?? '',
      sizeLabel: json['sizeLabel'] as String? ?? '',
      priceAdditionalCents: json['priceAdditionalCents'] as int? ?? 0,
      stockMil: json['stockMil'] as int? ?? 0,
      sortOrder: json['sortOrder'] as int? ?? 0,
      isActive: (json['isActive'] as bool?) ?? true,
    );
  }

  factory RemoteProductVariantRecord.fromLocalVariant(ProductVariant variant) {
    return RemoteProductVariantRecord(
      sku: variant.sku,
      colorLabel: variant.colorLabel,
      sizeLabel: variant.sizeLabel,
      priceAdditionalCents: variant.priceAdditionalCents,
      stockMil: variant.stockMil,
      sortOrder: variant.sortOrder,
      isActive: variant.isActive,
    );
  }

  final String sku;
  final String colorLabel;
  final String sizeLabel;
  final int priceAdditionalCents;
  final int stockMil;
  final int sortOrder;
  final bool isActive;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'sku': sku,
      'colorLabel': colorLabel,
      'sizeLabel': sizeLabel,
      'priceAdditionalCents': priceAdditionalCents,
      'stockMil': stockMil,
      'sortOrder': sortOrder,
      'isActive': isActive,
    };
  }
}

class RemoteProductModifierGroupRecord {
  const RemoteProductModifierGroupRecord({
    required this.name,
    required this.isRequired,
    required this.minSelections,
    required this.maxSelections,
    required this.options,
  });

  factory RemoteProductModifierGroupRecord.fromJson(Map<String, dynamic> json) {
    return RemoteProductModifierGroupRecord(
      name: json['name'] as String? ?? '',
      isRequired: (json['isRequired'] as bool?) ?? false,
      minSelections: json['minSelections'] as int? ?? 0,
      maxSelections: json['maxSelections'] as int?,
      options: ((json['options'] as List<dynamic>?) ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(RemoteProductModifierOptionRecord.fromJson)
          .toList(growable: false),
    );
  }

  factory RemoteProductModifierGroupRecord.fromLocalGroup(
    ProductModifierGroup group,
  ) {
    return RemoteProductModifierGroupRecord(
      name: group.name,
      isRequired: group.isRequired,
      minSelections: group.minSelections,
      maxSelections: group.maxSelections,
      options: group.options
          .map(
            (option) =>
                RemoteProductModifierOptionRecord.fromLocalOption(option),
          )
          .toList(growable: false),
    );
  }

  final String name;
  final bool isRequired;
  final int minSelections;
  final int? maxSelections;
  final List<RemoteProductModifierOptionRecord> options;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'name': name,
      'isRequired': isRequired,
      'minSelections': minSelections,
      'maxSelections': maxSelections,
      'options': options.map((option) => option.toJson()).toList(),
    };
  }
}

class RemoteProductModifierOptionRecord {
  const RemoteProductModifierOptionRecord({
    required this.name,
    required this.adjustmentType,
    required this.priceDeltaCents,
  });

  factory RemoteProductModifierOptionRecord.fromJson(
    Map<String, dynamic> json,
  ) {
    return RemoteProductModifierOptionRecord(
      name: json['name'] as String? ?? '',
      adjustmentType: json['adjustmentType'] as String? ?? 'add',
      priceDeltaCents: json['priceDeltaCents'] as int? ?? 0,
    );
  }

  factory RemoteProductModifierOptionRecord.fromLocalOption(
    ProductModifierOption option,
  ) {
    return RemoteProductModifierOptionRecord(
      name: option.name,
      adjustmentType: option.adjustmentType,
      priceDeltaCents: option.priceDeltaCents,
    );
  }

  final String name;
  final String adjustmentType;
  final int priceDeltaCents;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'name': name,
      'adjustmentType': adjustmentType,
      'priceDeltaCents': priceDeltaCents,
    };
  }
}
