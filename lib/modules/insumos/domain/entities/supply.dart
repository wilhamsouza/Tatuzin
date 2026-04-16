import '../services/supply_cost_math.dart';

abstract final class SupplyUnitTypes {
  static const unit = 'un';
  static const box = 'cx';
  static const kilogram = 'kg';
  static const gram = 'g';
  static const liter = 'l';
  static const milliliter = 'ml';

  static const values = <String>[unit, box, kilogram, gram, liter, milliliter];

  static String normalize(String? value) {
    return switch (value) {
      kilogram => kilogram,
      gram => gram,
      liter => liter,
      milliliter => milliliter,
      box => box,
      _ => unit,
    };
  }

  static bool areCompatible(String a, String b) {
    return _dimensionOf(normalize(a)) == _dimensionOf(normalize(b));
  }

  static String _dimensionOf(String value) {
    return switch (value) {
      kilogram || gram => 'mass',
      liter || milliliter => 'volume',
      _ => 'count',
    };
  }
}

class Supply {
  const Supply({
    required this.id,
    required this.uuid,
    required this.name,
    required this.sku,
    required this.unitType,
    required this.purchaseUnitType,
    required this.conversionFactor,
    required this.lastPurchasePriceCents,
    required this.averagePurchasePriceCents,
    required this.currentStockMil,
    required this.minimumStockMil,
    required this.defaultSupplierId,
    required this.defaultSupplierName,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String uuid;
  final String name;
  final String? sku;
  final String unitType;
  final String purchaseUnitType;
  final int conversionFactor;
  final int lastPurchasePriceCents;
  final int? averagePurchasePriceCents;
  final int? currentStockMil;
  final int? minimumStockMil;
  final int? defaultSupplierId;
  final String? defaultSupplierName;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get hasStockReference => currentStockMil != null;

  bool get hasMinimumStock => minimumStockMil != null;

  bool get hasPurchaseHistory => lastPurchasePriceCents > 0;

  int get normalizedConversionFactor =>
      SupplyCostMath.normalizeConversionFactor(conversionFactor);

  int get usageUnitCostCentsRounded => SupplyCostMath.unitUsageCostCentsRounded(
    lastPurchasePriceCents: lastPurchasePriceCents,
    conversionFactor: normalizedConversionFactor,
  );
}

class SupplyInput {
  const SupplyInput({
    required this.name,
    this.sku,
    required this.unitType,
    required this.purchaseUnitType,
    required this.conversionFactor,
    required this.lastPurchasePriceCents,
    this.averagePurchasePriceCents,
    this.currentStockMil,
    this.minimumStockMil,
    this.defaultSupplierId,
    this.isActive = true,
  });

  final String name;
  final String? sku;
  final String unitType;
  final String purchaseUnitType;
  final int conversionFactor;
  final int lastPurchasePriceCents;
  final int? averagePurchasePriceCents;
  final int? currentStockMil;
  final int? minimumStockMil;
  final int? defaultSupplierId;
  final bool isActive;
}
