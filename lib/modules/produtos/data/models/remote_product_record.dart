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
      'isActive': isActive,
      'deletedAt': deletedAt?.toIso8601String(),
    };
  }
}
