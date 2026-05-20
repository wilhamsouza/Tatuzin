import 'package:erp_pdv_app/app/core/theme/app_theme.dart';
import 'package:erp_pdv_app/modules/estoque/domain/entities/inventory_adjustment_input.dart';
import 'package:erp_pdv_app/modules/estoque/domain/entities/inventory_item.dart';
import 'package:erp_pdv_app/modules/estoque/domain/entities/inventory_movement.dart';
import 'package:erp_pdv_app/modules/estoque/domain/repositories/inventory_repository.dart';
import 'package:erp_pdv_app/modules/estoque/presentation/pages/inventory_adjustment_page.dart';
import 'package:erp_pdv_app/modules/estoque/presentation/providers/inventory_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_tenant_session.dart';

void main() {
  testWidgets('abre sem item e bloqueia confirmacao', (tester) async {
    final fakeRepository = _FakeInventoryRepository(items: const []);
    final container = _buildContainer(fakeRepository, const []);
    addTearDown(container.dispose);

    await _pumpPage(tester, container);

    expect(
      find.text('Selecione um item para ajustar o estoque.'),
      findsOneWidget,
    );
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Confirmar ajuste'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets(
    'seleciona produto simples e registra entrada com productId local',
    (tester) async {
      final item = _item(productId: 1, name: 'Farinha 1L');
      final fakeRepository = _FakeInventoryRepository(items: [item]);
      final container = _buildContainer(fakeRepository, [item]);
      addTearDown(container.dispose);

      await _pumpPage(tester, container);
      await _selectItem(tester, 'Farinha 1L');
      await tester.enterText(find.byType(TextFormField).first, '100');
      await tester.tap(find.widgetWithText(FilledButton, 'Confirmar ajuste'));
      await tester.pumpAndSettle();

      expect(fakeRepository.lastInput?.productId, 1);
      expect(fakeRepository.lastInput?.productVariantId, isNull);
      expect(
        fakeRepository.lastInput?.direction,
        InventoryAdjustmentDirection.inbound,
      );
      expect(fakeRepository.lastInput?.quantityMil, 100000);
    },
  );

  testWidgets(
    'seleciona produto simples e registra saida com productId local',
    (tester) async {
      final item = _item(productId: 1, name: 'Farinha 1L', stockMil: 200000);
      final fakeRepository = _FakeInventoryRepository(items: [item]);
      final container = _buildContainer(fakeRepository, [item]);
      addTearDown(container.dispose);

      await _pumpPage(tester, container);
      await _selectItem(tester, 'Farinha 1L');
      await tester.tap(find.text('Saída'));
      await tester.enterText(find.byType(TextFormField).first, '10');
      await tester.tap(find.widgetWithText(FilledButton, 'Confirmar ajuste'));
      await tester.pumpAndSettle();

      expect(fakeRepository.lastInput?.productId, 1);
      expect(fakeRepository.lastInput?.productVariantId, isNull);
      expect(
        fakeRepository.lastInput?.direction,
        InventoryAdjustmentDirection.outbound,
      );
      expect(fakeRepository.lastInput?.quantityMil, 10000);
    },
  );

  testWidgets('seleciona variante e preserva productVariantId no ajuste', (
    tester,
  ) async {
    final item = _item(
      productId: 2,
      productVariantId: 10,
      name: 'Camisa',
      color: 'Preta',
      size: 'P',
    );
    final fakeRepository = _FakeInventoryRepository(items: [item]);
    final container = _buildContainer(fakeRepository, [item]);
    addTearDown(container.dispose);

    await _pumpPage(tester, container);
    await _selectItem(tester, 'Camisa - Preta / P');
    await tester.enterText(find.byType(TextFormField).first, '5');
    await tester.tap(find.widgetWithText(FilledButton, 'Confirmar ajuste'));
    await tester.pumpAndSettle();

    expect(fakeRepository.lastInput?.productId, 2);
    expect(fakeRepository.lastInput?.productVariantId, 10);
    expect(
      fakeRepository.lastInput?.direction,
      InventoryAdjustmentDirection.inbound,
    );
  });

  testWidgets('item inicial vindo da rota usa IDs locais no ajuste', (
    tester,
  ) async {
    final item = _item(
      productId: 4,
      productVariantId: 12,
      name: 'Tenis',
      color: 'Azul',
      size: '38',
    );
    final fakeRepository = _FakeInventoryRepository(items: [item]);
    final container = _buildContainer(fakeRepository, [item]);
    addTearDown(container.dispose);

    await _pumpPage(tester, container, initialItem: item);
    await tester.enterText(find.byType(TextFormField).first, '3');
    await tester.tap(find.widgetWithText(FilledButton, 'Confirmar ajuste'));
    await tester.pumpAndSettle();

    expect(fakeRepository.lastInput?.productId, 4);
    expect(fakeRepository.lastInput?.productVariantId, 12);
    expect(fakeRepository.lastInput?.quantityMil, 3000);
  });

  testWidgets('item removido gera mensagem amigavel', (tester) async {
    final item = _item(productId: 3, name: 'Produto removido');
    final fakeRepository = _FakeInventoryRepository(
      items: [item],
      availableOnFind: false,
    );
    final container = _buildContainer(fakeRepository, [item]);
    addTearDown(container.dispose);

    await _pumpPage(tester, container);
    await _selectItem(tester, 'Produto removido');
    await tester.enterText(find.byType(TextFormField).first, '1');
    await tester.tap(find.widgetWithText(FilledButton, 'Confirmar ajuste'));
    await tester.pumpAndSettle();

    expect(
      find.text('Este item não está mais disponível para ajuste.'),
      findsOneWidget,
    );
    expect(fakeRepository.lastInput, isNull);
  });
}

ProviderContainer _buildContainer(
  _FakeInventoryRepository repository,
  List<InventoryItem> activeItems,
) {
  final container = ProviderContainer(
    overrides: [
      ...testTenantBootstrapOverrides(),
      inventoryRepositoryProvider.overrideWith((ref) => repository),
      inventoryLocalActiveItemOptionsProvider.overrideWith(
        (ref) async => activeItems,
      ),
    ],
  );
  setTestTenantSession(container);
  return container;
}

Future<void> _pumpPage(
  WidgetTester tester,
  ProviderContainer container, {
  InventoryItem? initialItem,
}) {
  tester.view.physicalSize = const Size(800, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  return tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: InventoryAdjustmentPage(initialItem: initialItem),
      ),
    ),
  );
}

Future<void> _selectItem(WidgetTester tester, String label) async {
  await tester.pumpAndSettle();
  await tester.tap(find.text('Selecionar item'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

InventoryItem _item({
  required int productId,
  int? productVariantId,
  required String name,
  String? color,
  String? size,
  int stockMil = 10000,
}) {
  return InventoryItem(
    productId: productId,
    productVariantId: productVariantId,
    productName: name,
    sku: productVariantId == null ? null : 'SKU-$productVariantId',
    variantColorLabel: color,
    variantSizeLabel: size,
    unitMeasure: 'un',
    currentStockMil: stockMil,
    minimumStockMil: 0,
    reorderPointMil: null,
    allowNegativeStock: false,
    costCents: 500,
    salePriceCents: 1000,
    isActive: true,
    updatedAt: DateTime(2026, 5, 20, 10),
  );
}

class _FakeInventoryRepository implements InventoryRepository {
  _FakeInventoryRepository({required this.items, this.availableOnFind = true});

  final List<InventoryItem> items;
  final bool availableOnFind;
  InventoryAdjustmentInput? lastInput;

  @override
  Future<void> adjustStock(InventoryAdjustmentInput input) async {
    lastInput = input;
  }

  @override
  Future<InventoryItem?> findItem({
    required int productId,
    int? productVariantId,
  }) async {
    if (!availableOnFind) {
      return null;
    }
    for (final item in items) {
      if (item.productId == productId &&
          item.productVariantId == productVariantId) {
        return item;
      }
    }
    return null;
  }

  @override
  Future<List<InventoryItem>> listItems({
    String query = '',
    InventoryListFilter filter = InventoryListFilter.all,
  }) async {
    return items;
  }

  @override
  Future<List<InventoryMovement>> listMovements({
    int? productId,
    int? productVariantId,
    bool includeVariantsForProduct = false,
    InventoryMovementType? movementType,
    DateTime? createdFrom,
    DateTime? createdTo,
    int limit = 300,
  }) async {
    return const [];
  }
}
