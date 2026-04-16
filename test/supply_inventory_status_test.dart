import 'package:flutter_test/flutter_test.dart';

import 'package:erp_pdv_app/modules/insumos/domain/entities/supply.dart';
import 'package:erp_pdv_app/modules/insumos/domain/entities/supply_inventory.dart';
import 'package:erp_pdv_app/modules/insumos/domain/services/supply_inventory_math.dart';

void main() {
  group('Saldo / alerta', () {
    test('insumo abaixo do minimo entra em alerta', () {
      final supply = _buildSupply(
        currentStockMil: 50000,
        minimumStockMil: 80000,
      );
      final overview = SupplyInventoryOverview(
        supply: supply,
        hasOperationalBaseline: true,
        inventoryStatus: SupplyInventoryMath.resolveStatus(
          isActive: true,
          hasOperationalBaseline: true,
          currentStockMil: 50000,
          minimumStockMil: 80000,
        ),
        lastMovementAt: null,
        lastPurchaseAt: null,
      );

      expect(overview.inventoryStatus, SupplyInventoryStatus.low);
      expect(overview.isAlert, isTrue);
      expect(overview.shortageMil, 30000);
    });

    test('insumo inativo nao polui alerta', () {
      final supply = _buildSupply(
        currentStockMil: 0,
        minimumStockMil: 50000,
        isActive: false,
      );
      final overview = SupplyInventoryOverview(
        supply: supply,
        hasOperationalBaseline: true,
        inventoryStatus: SupplyInventoryMath.resolveStatus(
          isActive: false,
          hasOperationalBaseline: true,
          currentStockMil: 0,
          minimumStockMil: 50000,
        ),
        lastMovementAt: null,
        lastPurchaseAt: null,
      );

      expect(overview.isAlert, isFalse);
      expect(overview.statusLabel, 'Inativo');
    });

    test('sugestao de recompra usa a diferenca faltante', () {
      final overview = SupplyInventoryOverview(
        supply: _buildSupply(currentStockMil: 20000, minimumStockMil: 100000),
        hasOperationalBaseline: true,
        inventoryStatus: SupplyInventoryStatus.low,
        lastMovementAt: null,
        lastPurchaseAt: null,
      );
      final suggestion = SupplyReorderSuggestion(
        overview: overview,
        shortageMil: overview.shortageMil,
      );

      expect(suggestion.shortageMil, 80000);
      expect(suggestion.overview.isAlert, isTrue);
    });

    test('ordenacao operacional prioriza criticos, falta e nome', () {
      final sorted = SupplyReorderSuggestion.sortOperational([
        SupplyReorderSuggestion(
          overview: _buildOverview(
            name: 'Cebola',
            currentStockMil: 0,
            minimumStockMil: 100000,
            status: SupplyInventoryStatus.critical,
          ),
          shortageMil: 100000,
        ),
        SupplyReorderSuggestion(
          overview: _buildOverview(
            name: 'Alface',
            currentStockMil: 50000,
            minimumStockMil: 100000,
            status: SupplyInventoryStatus.low,
          ),
          shortageMil: 50000,
        ),
        SupplyReorderSuggestion(
          overview: _buildOverview(
            name: 'Bacon',
            currentStockMil: 10000,
            minimumStockMil: 50000,
            status: SupplyInventoryStatus.low,
          ),
          shortageMil: 40000,
        ),
        SupplyReorderSuggestion(
          overview: _buildOverview(
            name: 'Acem',
            currentStockMil: 0,
            minimumStockMil: 50000,
            status: SupplyInventoryStatus.critical,
          ),
          shortageMil: 50000,
        ),
      ]);

      expect(sorted.map((item) => item.overview.supply.name).toList(), [
        'Cebola',
        'Acem',
        'Alface',
        'Bacon',
      ]);
    });

    test('filtro de recompra pode isolar apenas itens criticos', () {
      final filtered = SupplyReorderSuggestion.sortOperational([
        SupplyReorderSuggestion(
          overview: _buildOverview(
            name: 'Molho',
            currentStockMil: 0,
            minimumStockMil: 100000,
            status: SupplyInventoryStatus.critical,
          ),
          shortageMil: 100000,
        ),
        SupplyReorderSuggestion(
          overview: _buildOverview(
            name: 'Queijo',
            currentStockMil: 70000,
            minimumStockMil: 100000,
            status: SupplyInventoryStatus.low,
          ),
          shortageMil: 30000,
        ),
      ], filter: SupplyReorderFilter.critical);

      expect(filtered, hasLength(1));
      expect(filtered.single.overview.supply.name, 'Molho');
    });

    test('rotulos do historico permanecem auditaveis e amigaveis', () {
      final movement = SupplyInventoryMovement(
        id: 1,
        uuid: 'movement-1',
        remoteId: null,
        supplyId: 1,
        supplyName: 'Queijo',
        movementType: SupplyInventoryMovementType.reversal,
        sourceType: SupplyInventorySourceType.purchaseCancel,
        sourceLocalUuid: 'purchase-1',
        sourceRemoteId: null,
        quantityDeltaMil: -1000,
        unitType: 'g',
        balanceAfterMil: null,
        notes: 'Estorno operacional.',
        occurredAt: DateTime.parse('2026-04-15T12:00:00Z'),
        createdAt: DateTime.parse('2026-04-15T12:00:00Z'),
        updatedAt: DateTime.parse('2026-04-15T12:00:00Z'),
      );

      expect(
        SupplyInventorySourceType.migrationSeed.historyLabel,
        'Saldo inicial migrado',
      );
      expect(movement.historyLabel, 'Estorno de compra');
      expect(movement.auditReferenceLabel, 'Ref. purchase-1');
    });
  });
}

Supply _buildSupply({
  String name = 'Queijo',
  required int? currentStockMil,
  required int? minimumStockMil,
  bool isActive = true,
}) {
  return Supply(
    id: 1,
    uuid: 'supply-1',
    name: name,
    sku: null,
    unitType: 'g',
    purchaseUnitType: 'kg',
    conversionFactor: 1000,
    lastPurchasePriceCents: 3000,
    averagePurchasePriceCents: 2900,
    currentStockMil: currentStockMil,
    minimumStockMil: minimumStockMil,
    defaultSupplierId: null,
    defaultSupplierName: null,
    isActive: isActive,
    createdAt: DateTime.parse('2026-04-15T12:00:00Z'),
    updatedAt: DateTime.parse('2026-04-15T12:00:00Z'),
  );
}

SupplyInventoryOverview _buildOverview({
  required String name,
  required int? currentStockMil,
  required int? minimumStockMil,
  required SupplyInventoryStatus status,
}) {
  return SupplyInventoryOverview(
    supply: _buildSupply(
      name: name,
      currentStockMil: currentStockMil,
      minimumStockMil: minimumStockMil,
    ),
    hasOperationalBaseline: true,
    inventoryStatus: status,
    lastMovementAt: null,
    lastPurchaseAt: null,
  );
}
