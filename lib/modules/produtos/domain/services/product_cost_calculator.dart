import '../../../insumos/domain/services/supply_cost_math.dart';

class ProductCostComponentInput {
  const ProductCostComponentInput({
    required this.supplyId,
    required this.supplyName,
    required this.purchaseUnitType,
    required this.unitType,
    required this.conversionFactor,
    required this.lastPurchasePriceCents,
    required this.quantityUsedMil,
    this.wasteBasisPoints = 0,
    this.notes,
  });

  final int supplyId;
  final String supplyName;
  final String purchaseUnitType;
  final String unitType;
  final int conversionFactor;
  final int lastPurchasePriceCents;
  final int quantityUsedMil;
  final int wasteBasisPoints;
  final String? notes;
}

class ProductCostComponentSummary {
  const ProductCostComponentSummary({
    required this.supplyId,
    required this.supplyName,
    required this.purchaseUnitType,
    required this.unitType,
    required this.quantityUsedMil,
    required this.effectiveQuantityUsedMil,
    required this.wasteBasisPoints,
    required this.unitUsageCostCentsRounded,
    required this.itemCostCents,
    this.notes,
  });

  final int supplyId;
  final String supplyName;
  final String purchaseUnitType;
  final String unitType;
  final int quantityUsedMil;
  final int effectiveQuantityUsedMil;
  final int wasteBasisPoints;
  final int unitUsageCostCentsRounded;
  final int itemCostCents;
  final String? notes;
}

class ProductCostSummary {
  const ProductCostSummary({
    required this.salePriceCents,
    required this.variableCostSnapshotCents,
    required this.estimatedGrossMarginCents,
    required this.estimatedGrossMarginPercentBasisPoints,
    required this.items,
  });

  const ProductCostSummary.empty({required this.salePriceCents})
    : variableCostSnapshotCents = 0,
      estimatedGrossMarginCents = salePriceCents,
      estimatedGrossMarginPercentBasisPoints = salePriceCents <= 0 ? 0 : 10000,
      items = const <ProductCostComponentSummary>[];

  final int salePriceCents;
  final int variableCostSnapshotCents;
  final int estimatedGrossMarginCents;
  final int estimatedGrossMarginPercentBasisPoints;
  final List<ProductCostComponentSummary> items;

  bool get hasRecipe => items.isNotEmpty;
}

abstract final class ProductCostCalculator {
  static ProductCostSummary calculate({
    required int salePriceCents,
    required Iterable<ProductCostComponentInput> items,
  }) {
    final summaries = items
        .map(
          (item) => ProductCostComponentSummary(
            supplyId: item.supplyId,
            supplyName: item.supplyName,
            purchaseUnitType: item.purchaseUnitType,
            unitType: item.unitType,
            quantityUsedMil: item.quantityUsedMil,
            effectiveQuantityUsedMil: SupplyCostMath.applyWaste(
              quantityUsedMil: item.quantityUsedMil,
              wasteBasisPoints: item.wasteBasisPoints,
            ),
            wasteBasisPoints: item.wasteBasisPoints,
            unitUsageCostCentsRounded: SupplyCostMath.unitUsageCostCentsRounded(
              lastPurchasePriceCents: item.lastPurchasePriceCents,
              conversionFactor: item.conversionFactor,
            ),
            itemCostCents: SupplyCostMath.recipeItemCostCents(
              lastPurchasePriceCents: item.lastPurchasePriceCents,
              conversionFactor: item.conversionFactor,
              quantityUsedMil: item.quantityUsedMil,
              wasteBasisPoints: item.wasteBasisPoints,
            ),
            notes: item.notes,
          ),
        )
        .toList(growable: false);

    if (summaries.isEmpty) {
      return ProductCostSummary.empty(salePriceCents: salePriceCents);
    }

    final variableCostSnapshotCents = summaries.fold<int>(
      0,
      (total, item) => total + item.itemCostCents,
    );
    final estimatedGrossMarginCents =
        salePriceCents - variableCostSnapshotCents;
    final estimatedGrossMarginPercentBasisPoints = salePriceCents <= 0
        ? 0
        : _roundDivide(estimatedGrossMarginCents * 10000, salePriceCents);

    return ProductCostSummary(
      salePriceCents: salePriceCents,
      variableCostSnapshotCents: variableCostSnapshotCents,
      estimatedGrossMarginCents: estimatedGrossMarginCents,
      estimatedGrossMarginPercentBasisPoints:
          estimatedGrossMarginPercentBasisPoints,
      items: summaries,
    );
  }

  static int _roundDivide(int numerator, int denominator) {
    if (denominator <= 0) {
      return 0;
    }
    if (numerator >= 0) {
      return (numerator + (denominator ~/ 2)) ~/ denominator;
    }
    return (numerator - (denominator ~/ 2)) ~/ denominator;
  }
}
