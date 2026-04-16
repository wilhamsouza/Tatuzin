abstract final class SupplyCostMath {
  static const int basisPointsScale = 10000;
  static const int milScale = 1000;

  static int normalizeConversionFactor(int value) {
    return value <= 0 ? 1 : value;
  }

  static int normalizeWasteBasisPoints(int value) {
    if (value < 0) {
      return 0;
    }
    return value;
  }

  static int applyWaste({
    required int quantityUsedMil,
    required int wasteBasisPoints,
  }) {
    final normalizedWaste = normalizeWasteBasisPoints(wasteBasisPoints);
    final numerator = quantityUsedMil * (basisPointsScale + normalizedWaste);
    return (numerator + (basisPointsScale ~/ 2)) ~/ basisPointsScale;
  }

  static int unitUsageCostCentsRounded({
    required int lastPurchasePriceCents,
    required int conversionFactor,
  }) {
    final normalizedFactor = normalizeConversionFactor(conversionFactor);
    return _roundDivide(lastPurchasePriceCents, normalizedFactor);
  }

  static int recipeItemCostCents({
    required int lastPurchasePriceCents,
    required int conversionFactor,
    required int quantityUsedMil,
    required int wasteBasisPoints,
  }) {
    final normalizedFactor = normalizeConversionFactor(conversionFactor);
    final effectiveQuantityMil = applyWaste(
      quantityUsedMil: quantityUsedMil,
      wasteBasisPoints: wasteBasisPoints,
    );
    final numerator = lastPurchasePriceCents * effectiveQuantityMil;
    final denominator = normalizedFactor * milScale;
    return _roundDivide(numerator, denominator);
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
