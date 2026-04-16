import 'package:erp_pdv_app/modules/produtos/domain/services/product_cost_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProductCostCalculator', () {
    test('calcula custo com mesma unidade', () {
      final summary = ProductCostCalculator.calculate(
        salePriceCents: 1500,
        items: const [
          ProductCostComponentInput(
            supplyId: 1,
            supplyName: 'Pao',
            purchaseUnitType: 'un',
            unitType: 'un',
            conversionFactor: 1,
            lastPurchasePriceCents: 250,
            quantityUsedMil: 2000,
          ),
          ProductCostComponentInput(
            supplyId: 2,
            supplyName: 'Queijo',
            purchaseUnitType: 'un',
            unitType: 'un',
            conversionFactor: 1,
            lastPurchasePriceCents: 150,
            quantityUsedMil: 1000,
          ),
        ],
      );

      expect(summary.variableCostSnapshotCents, 650);
      expect(summary.estimatedGrossMarginCents, 850);
      expect(summary.estimatedGrossMarginPercentBasisPoints, 5667);
    });

    test('aplica conversao de kg para g', () {
      final summary = ProductCostCalculator.calculate(
        salePriceCents: 2000,
        items: const [
          ProductCostComponentInput(
            supplyId: 1,
            supplyName: 'Mussarela',
            purchaseUnitType: 'kg',
            unitType: 'g',
            conversionFactor: 1000,
            lastPurchasePriceCents: 3600,
            quantityUsedMil: 50000,
          ),
        ],
      );

      expect(summary.items.single.itemCostCents, 180);
      expect(summary.variableCostSnapshotCents, 180);
    });

    test('aplica perda na quantidade efetiva', () {
      final summary = ProductCostCalculator.calculate(
        salePriceCents: 1800,
        items: const [
          ProductCostComponentInput(
            supplyId: 1,
            supplyName: 'Carne',
            purchaseUnitType: 'kg',
            unitType: 'g',
            conversionFactor: 1000,
            lastPurchasePriceCents: 3000,
            quantityUsedMil: 100000,
            wasteBasisPoints: 1000,
          ),
        ],
      );

      expect(summary.items.single.effectiveQuantityUsedMil, 110000);
      expect(summary.items.single.itemCostCents, 330);
      expect(summary.variableCostSnapshotCents, 330);
    });

    test('retorna custo zero quando ficha tecnica esta vazia', () {
      final summary = ProductCostCalculator.calculate(
        salePriceCents: 2500,
        items: const [],
      );

      expect(summary.hasRecipe, isFalse);
      expect(summary.variableCostSnapshotCents, 0);
      expect(summary.estimatedGrossMarginCents, 2500);
      expect(summary.estimatedGrossMarginPercentBasisPoints, 10000);
    });
  });
}
