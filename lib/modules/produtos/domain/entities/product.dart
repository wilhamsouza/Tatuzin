import '../../../../app/core/sync/sync_status.dart';

abstract final class ProductCatalogTypes {
  static const simple = 'simple';
  static const variant = 'variant';

  static const values = <String>[simple, variant];

  static String normalize(String? value) {
    return value == variant ? variant : simple;
  }
}

class Product {
  const Product({
    required this.id,
    required this.uuid,
    required this.name,
    required this.description,
    required this.categoryId,
    required this.categoryName,
    required this.barcode,
    required this.productType,
    required this.catalogType,
    required this.modelName,
    required this.variantLabel,
    required this.baseProductId,
    required this.baseProductName,
    this.variantAttributes = const <ProductVariantAttribute>[],
    this.modifierGroups = const <ProductModifierGroup>[],
    required this.unitMeasure,
    required this.costCents,
    required this.salePriceCents,
    required this.stockMil,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    required this.deletedAt,
    this.remoteId,
    this.syncStatus = SyncStatus.localOnly,
    this.lastSyncedAt,
  });

  final int id;
  final String uuid;
  final String name;
  final String? description;
  final int? categoryId;
  final String? categoryName;
  final String? barcode;
  final String productType;
  final String catalogType;
  final String? modelName;
  final String? variantLabel;
  final int? baseProductId;
  final String? baseProductName;
  final List<ProductVariantAttribute> variantAttributes;
  final List<ProductModifierGroup> modifierGroups;
  final String unitMeasure;
  final int costCents;
  final int salePriceCents;
  final int stockMil;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String? remoteId;
  final SyncStatus syncStatus;
  final DateTime? lastSyncedAt;

  int get stockUnits => stockMil ~/ 1000;

  bool get isVariantCatalog =>
      ProductCatalogTypes.normalize(catalogType) == ProductCatalogTypes.variant;

  int get modifierGroupCount => modifierGroups.length;

  int get modifierOptionCount => modifierGroups.fold<int>(
    0,
    (total, group) => total + group.options.length,
  );

  String get displayName {
    final resolvedModel = modelName?.trim();
    final resolvedVariant = variantLabel?.trim();
    if (isVariantCatalog &&
        resolvedModel != null &&
        resolvedModel.isNotEmpty &&
        resolvedVariant != null &&
        resolvedVariant.isNotEmpty) {
      return '$resolvedModel - $resolvedVariant';
    }
    return name;
  }

  String? get catalogSubtitle {
    final resolvedModel = modelName?.trim();
    final resolvedVariant = variantLabel?.trim();
    if (!isVariantCatalog ||
        resolvedModel == null ||
        resolvedModel.isEmpty ||
        resolvedVariant == null ||
        resolvedVariant.isEmpty) {
      return null;
    }
    return 'Variacao $resolvedVariant';
  }

  String? get variantAttributesSummary {
    if (variantAttributes.isEmpty) {
      return null;
    }
    final labels = variantAttributes
        .where(
          (attribute) =>
              attribute.key != 'legacy_variant_label' &&
              attribute.key != 'model' &&
              attribute.key != 'variant',
        )
        .map((attribute) => '${attribute.key}: ${attribute.value}')
        .toList(growable: false);
    if (labels.isEmpty) {
      return null;
    }
    return labels.join(' - ');
  }
}

class ProductInput {
  const ProductInput({
    required this.name,
    this.description,
    this.categoryId,
    this.barcode,
    this.catalogType = ProductCatalogTypes.simple,
    this.modelName,
    this.variantLabel,
    this.baseProductId,
    this.variantAttributes = const <ProductVariantAttributeInput>[],
    this.modifierGroups,
    required this.unitMeasure,
    required this.costCents,
    required this.salePriceCents,
    required this.stockMil,
    this.isActive = true,
  });

  final String name;
  final String? description;
  final int? categoryId;
  final String? barcode;
  final String catalogType;
  final String? modelName;
  final String? variantLabel;
  final int? baseProductId;
  final List<ProductVariantAttributeInput> variantAttributes;
  final List<ProductModifierGroupInput>? modifierGroups;
  final String unitMeasure;
  final int costCents;
  final int salePriceCents;
  final int stockMil;
  final bool isActive;
}

class ProductVariantAttribute {
  const ProductVariantAttribute({required this.key, required this.value});

  final String key;
  final String value;
}

class ProductVariantAttributeInput {
  const ProductVariantAttributeInput({required this.key, required this.value});

  final String key;
  final String value;
}

class ProductModifierGroup {
  const ProductModifierGroup({
    required this.name,
    required this.isRequired,
    required this.minSelections,
    required this.maxSelections,
    this.options = const <ProductModifierOption>[],
  });

  final String name;
  final bool isRequired;
  final int minSelections;
  final int? maxSelections;
  final List<ProductModifierOption> options;
}

class ProductModifierOption {
  const ProductModifierOption({
    required this.name,
    required this.adjustmentType,
    required this.priceDeltaCents,
  });

  final String name;
  final String adjustmentType;
  final int priceDeltaCents;
}

class ProductModifierGroupInput {
  const ProductModifierGroupInput({
    required this.name,
    this.isRequired = false,
    this.minSelections = 0,
    this.maxSelections,
    this.options = const <ProductModifierOptionInput>[],
  });

  final String name;
  final bool isRequired;
  final int minSelections;
  final int? maxSelections;
  final List<ProductModifierOptionInput> options;
}

class ProductModifierOptionInput {
  const ProductModifierOptionInput({
    required this.name,
    this.adjustmentType = 'add',
    this.priceDeltaCents = 0,
  });

  final String name;
  final String adjustmentType;
  final int priceDeltaCents;
}
