import 'product.dart';

enum ProductProfitabilityMarginStatus { notAvailable, healthy, attention, low }

extension ProductProfitabilityMarginStatusX
    on ProductProfitabilityMarginStatus {
  String get label {
    return switch (this) {
      ProductProfitabilityMarginStatus.notAvailable => 'Sem ficha tecnica',
      ProductProfitabilityMarginStatus.healthy => 'Saudavel',
      ProductProfitabilityMarginStatus.attention => 'Atencao',
      ProductProfitabilityMarginStatus.low => 'Margem baixa',
    };
  }
}

enum ProductProfitabilityFilter {
  all,
  derived,
  manual,
  healthy,
  attention,
  low,
}

extension ProductProfitabilityFilterX on ProductProfitabilityFilter {
  String get label {
    return switch (this) {
      ProductProfitabilityFilter.all => 'Todos',
      ProductProfitabilityFilter.derived => 'Calculo derivado',
      ProductProfitabilityFilter.manual => 'Sem ficha tecnica',
      ProductProfitabilityFilter.healthy => 'Saudavel',
      ProductProfitabilityFilter.attention => 'Atencao',
      ProductProfitabilityFilter.low => 'Margem baixa',
    };
  }
}

enum ProductProfitabilitySort {
  marginDesc,
  marginAsc,
  costDesc,
  updatedDesc,
  nameAsc,
}

extension ProductProfitabilitySortX on ProductProfitabilitySort {
  String get label {
    return switch (this) {
      ProductProfitabilitySort.marginDesc => 'Maior margem',
      ProductProfitabilitySort.marginAsc => 'Menor margem',
      ProductProfitabilitySort.costDesc => 'Maior custo',
      ProductProfitabilitySort.updatedDesc => 'Atualizacao recente',
      ProductProfitabilitySort.nameAsc => 'Nome',
    };
  }
}

class ProductProfitabilityRow {
  const ProductProfitabilityRow({
    required this.productId,
    required this.productName,
    required this.categoryName,
    required this.salePriceCents,
    required this.activeCostCents,
    required this.manualCostCents,
    required this.costSource,
    required this.variableCostSnapshotCents,
    required this.grossMarginCents,
    required this.grossMarginPercentBasisPoints,
    required this.lastCostUpdatedAt,
    required this.marginStatus,
  });

  factory ProductProfitabilityRow.fromProduct(Product product) {
    final hasDerivedCalculation =
        product.usesRecipeSnapshot && product.hasCostSnapshot;
    final marginStatus =
        switch (product.estimatedGrossMarginPercentBasisPoints ?? 0) {
          _ when !hasDerivedCalculation =>
            ProductProfitabilityMarginStatus.notAvailable,
          >= 2000 => ProductProfitabilityMarginStatus.healthy,
          >= 1000 => ProductProfitabilityMarginStatus.attention,
          _ => ProductProfitabilityMarginStatus.low,
        };

    return ProductProfitabilityRow(
      productId: product.id,
      productName: product.displayName,
      categoryName: product.categoryName,
      salePriceCents: product.salePriceCents,
      activeCostCents: product.costCents,
      manualCostCents: product.manualCostCents,
      costSource: product.costSource,
      variableCostSnapshotCents: product.variableCostSnapshotCents,
      grossMarginCents: product.estimatedGrossMarginCents,
      grossMarginPercentBasisPoints:
          product.estimatedGrossMarginPercentBasisPoints,
      lastCostUpdatedAt: product.lastCostUpdatedAt,
      marginStatus: marginStatus,
    );
  }

  final int productId;
  final String productName;
  final String? categoryName;
  final int salePriceCents;
  final int activeCostCents;
  final int manualCostCents;
  final ProductCostSource costSource;
  final int? variableCostSnapshotCents;
  final int? grossMarginCents;
  final int? grossMarginPercentBasisPoints;
  final DateTime? lastCostUpdatedAt;
  final ProductProfitabilityMarginStatus marginStatus;

  bool get hasDerivedCalculation =>
      costSource == ProductCostSource.recipeSnapshot &&
      variableCostSnapshotCents != null &&
      grossMarginCents != null &&
      grossMarginPercentBasisPoints != null;

  bool get usesManualCost => costSource == ProductCostSource.manual;

  String get sourceLabel {
    return hasDerivedCalculation ? 'Calculo derivado' : 'Custo manual';
  }

  String get contextLabel {
    return hasDerivedCalculation ? 'Ficha tecnica ativa' : 'Sem ficha tecnica';
  }
}
