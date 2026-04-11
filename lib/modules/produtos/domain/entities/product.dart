import '../../../../app/core/sync/sync_status.dart';

abstract final class ProductCatalogTypes {
  static const simple = 'simple';
  static const variant = 'variant';

  static const values = <String>[simple, variant];

  static String normalize(String? value) {
    return value == variant ? variant : simple;
  }
}

abstract final class ProductNiches {
  static const food = 'alimentacao';
  static const fashion = 'moda';

  static const values = <String>[food, fashion];

  static String normalize(String? value) {
    return value == fashion ? fashion : food;
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
    required this.primaryPhotoPath,
    required this.productType,
    required this.niche,
    required this.catalogType,
    required this.modelName,
    required this.variantLabel,
    required this.baseProductId,
    required this.baseProductName,
    this.variantAttributes = const <ProductVariantAttribute>[],
    this.variants = const <ProductVariant>[],
    this.modifierGroups = const <ProductModifierGroup>[],
    this.sellableVariantId,
    this.sellableVariantSku,
    this.sellableVariantColorLabel,
    this.sellableVariantSizeLabel,
    this.sellableVariantPriceAdditionalCents,
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
  final String? primaryPhotoPath;
  final String productType;
  final String niche;
  final String catalogType;
  final String? modelName;
  final String? variantLabel;
  final int? baseProductId;
  final String? baseProductName;
  final List<ProductVariantAttribute> variantAttributes;
  final List<ProductVariant> variants;
  final List<ProductModifierGroup> modifierGroups;
  final int? sellableVariantId;
  final String? sellableVariantSku;
  final String? sellableVariantColorLabel;
  final String? sellableVariantSizeLabel;
  final int? sellableVariantPriceAdditionalCents;
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

  bool get isFoodNiche => ProductNiches.normalize(niche) == ProductNiches.food;

  bool get isFashionNiche =>
      ProductNiches.normalize(niche) == ProductNiches.fashion;

  bool get hasVariants => variants.isNotEmpty;

  bool get isSellableVariant => sellableVariantId != null;

  bool get hasPhoto =>
      primaryPhotoPath != null && primaryPhotoPath!.trim().isNotEmpty;

  int get modifierGroupCount => modifierGroups.length;

  int get modifierOptionCount => modifierGroups.fold<int>(
    0,
    (total, group) => total + group.options.length,
  );

  int get variantCount => variants.where((variant) => variant.isActive).length;

  int get aggregatedVariantStockMil => variants.fold<int>(
    0,
    (total, variant) => total + (variant.isActive ? variant.stockMil : 0),
  );

  String? get variantSummary {
    if (!isSellableVariant) {
      return null;
    }

    final labels = <String>[
      if ((sellableVariantSizeLabel ?? '').trim().isNotEmpty)
        sellableVariantSizeLabel!.trim(),
      if ((sellableVariantColorLabel ?? '').trim().isNotEmpty)
        sellableVariantColorLabel!.trim(),
    ];
    if (labels.isEmpty) {
      return null;
    }
    return labels.join(' / ');
  }

  String get displayName {
    final sellableSummary = variantSummary;
    if (sellableSummary != null && sellableSummary.isNotEmpty) {
      return '$name - $sellableSummary';
    }

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
    return 'Variação $resolvedVariant';
  }

  String? get variantAttributesSummary {
    if (variantAttributes.isEmpty) {
      return null;
    }
    final labels = variantAttributes
        .where(
          (attribute) =>
              attribute.key != 'model' &&
              attribute.key != 'variant' &&
              !_isReservedNicheAttribute(attribute.key),
        )
        .map((attribute) => '${attribute.key}: ${attribute.value}')
        .toList(growable: false);
    if (labels.isEmpty) {
      return null;
    }
    return labels.join(' - ');
  }

  bool _isReservedNicheAttribute(String key) {
    return key.startsWith('food_') || key.startsWith('fashion_');
  }
}

class ProductInput {
  const ProductInput({
    required this.name,
    this.description,
    this.categoryId,
    this.barcode,
    this.photos = const <ProductPhotoInput>[],
    this.variants = const <ProductVariantInput>[],
    this.productType = 'unidade',
    this.niche = ProductNiches.food,
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
  final List<ProductPhotoInput> photos;
  final List<ProductVariantInput> variants;
  final String productType;
  final String niche;
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

class ProductVariant {
  const ProductVariant({
    required this.id,
    required this.uuid,
    required this.productId,
    required this.sku,
    required this.colorLabel,
    required this.sizeLabel,
    required this.priceAdditionalCents,
    required this.stockMil,
    required this.sortOrder,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String uuid;
  final int productId;
  final String sku;
  final String colorLabel;
  final String sizeLabel;
  final int priceAdditionalCents;
  final int stockMil;
  final int sortOrder;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class ProductVariantInput {
  const ProductVariantInput({
    required this.sku,
    required this.colorLabel,
    required this.sizeLabel,
    this.priceAdditionalCents = 0,
    this.stockMil = 0,
    this.sortOrder = 0,
    this.isActive = true,
  });

  final String sku;
  final String colorLabel;
  final String sizeLabel;
  final int priceAdditionalCents;
  final int stockMil;
  final int sortOrder;
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

class ProductPhoto {
  const ProductPhoto({
    required this.id,
    required this.uuid,
    required this.productId,
    required this.localPath,
    required this.isPrimary,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String uuid;
  final int productId;
  final String localPath;
  final bool isPrimary;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class ProductPhotoInput {
  const ProductPhotoInput({
    required this.localPath,
    this.isPrimary = false,
    this.sortOrder = 0,
  });

  final String localPath;
  final bool isPrimary;
  final int sortOrder;
}
