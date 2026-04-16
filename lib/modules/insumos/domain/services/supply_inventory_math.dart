import '../entities/supply_inventory.dart';

abstract final class SupplyInventoryMath {
  static const int milScale = 1000;
  static const int basisPointsScale = 10000;

  static int normalizeConversionFactor(int value) {
    return value <= 0 ? 1 : value;
  }

  static int normalizeWasteBasisPoints(int value) {
    return value < 0 ? 0 : value;
  }

  static int purchaseToOperationalQuantityMil({
    required int purchaseQuantityMil,
    required int conversionFactor,
  }) {
    return purchaseQuantityMil * normalizeConversionFactor(conversionFactor);
  }

  static int applyWaste({
    required int quantityUsedMil,
    required int wasteBasisPoints,
  }) {
    final normalizedWaste = normalizeWasteBasisPoints(wasteBasisPoints);
    final numerator = quantityUsedMil * (basisPointsScale + normalizedWaste);
    return _roundDivide(numerator, basisPointsScale);
  }

  static int saleConsumptionQuantityMil({
    required int quantityUsedMil,
    required int soldQuantityMil,
    required int wasteBasisPoints,
  }) {
    final effectivePerUnitMil = applyWaste(
      quantityUsedMil: quantityUsedMil,
      wasteBasisPoints: wasteBasisPoints,
    );
    return _roundDivide(effectivePerUnitMil * soldQuantityMil, milScale);
  }

  static int balanceFromDeltas(Iterable<int> deltas) {
    return deltas.fold<int>(0, (total, delta) => total + delta);
  }

  static SupplyInventoryStatus resolveStatus({
    required bool isActive,
    required bool hasOperationalBaseline,
    required int? currentStockMil,
    required int? minimumStockMil,
  }) {
    if (!isActive || !hasOperationalBaseline || currentStockMil == null) {
      return SupplyInventoryStatus.unknown;
    }
    if (minimumStockMil == null) {
      return SupplyInventoryStatus.normal;
    }
    if (currentStockMil <= 0) {
      return SupplyInventoryStatus.critical;
    }
    if (currentStockMil <= minimumStockMil) {
      return SupplyInventoryStatus.low;
    }
    return SupplyInventoryStatus.normal;
  }

  static int _roundDivide(int numerator, int denominator) {
    if (denominator <= 0) {
      return 0;
    }
    if (numerator == 0) {
      return 0;
    }
    if (numerator > 0) {
      return (numerator + (denominator ~/ 2)) ~/ denominator;
    }
    return (numerator - (denominator ~/ 2)) ~/ denominator;
  }
}
