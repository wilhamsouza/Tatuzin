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

  String get displayName {
    final resolvedModel = modelName?.trim();
    final resolvedVariant = variantLabel?.trim();
    if (isVariantCatalog &&
        resolvedModel != null &&
        resolvedModel.isNotEmpty &&
        resolvedVariant != null &&
        resolvedVariant.isNotEmpty) {
      return '$resolvedModel — $resolvedVariant';
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
  final String unitMeasure;
  final int costCents;
  final int salePriceCents;
  final int stockMil;
  final bool isActive;
}
