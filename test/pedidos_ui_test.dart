import 'package:tatuzin/app/core/theme/app_theme.dart';
import 'package:tatuzin/app/routes/route_names.dart';
import 'package:tatuzin/modules/pedidos/domain/entities/operational_order.dart';
import 'package:tatuzin/modules/pedidos/domain/entities/operational_order_detail.dart';
import 'package:tatuzin/modules/pedidos/domain/entities/operational_order_item.dart';
import 'package:tatuzin/modules/pedidos/domain/entities/operational_order_summary.dart';
import 'package:tatuzin/modules/pedidos/presentation/pages/kitchen_order_view_page.dart';
import 'package:tatuzin/modules/pedidos/presentation/pages/order_detail_page.dart';
import 'package:tatuzin/modules/pedidos/presentation/pages/orders_page.dart';
import 'package:tatuzin/modules/pedidos/presentation/providers/order_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('tela Pedidos mostra busca, chips e cards compactos', (
    tester,
  ) async {
    await _pumpOrdersApp(tester);

    expect(find.text('Pedidos'), findsWidgets);
    expect(find.text('Novo'), findsOneWidget);
    expect(find.text('Buscar pedido ou cliente'), findsOneWidget);
    expect(find.textContaining('Todos'), findsOneWidget);
    expect(find.textContaining('Pendente/Aberto'), findsOneWidget);
    expect(find.text('Separacao'), findsWidgets);
    expect(find.textContaining('Fiado'), findsOneWidget);

    await tester.drag(find.byType(ListView).first, const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(find.textContaining('Concluido'), findsWidgets);
    expect(find.textContaining('Cancelado'), findsOneWidget);

    expect(find.text('Mariana Costa'), findsOneWidget);
    expect(find.text('R\$ 389,00'), findsAtLeastNWidgets(1));
    expect(find.text('Cancelar pedido'), findsNothing);
    expect(find.text('Finalizar venda'), findsNothing);
    expect(find.text('Imprimir'), findsNothing);
  });

  testWidgets('tocar no card abre detalhe do pedido', (tester) async {
    await _pumpOrdersApp(tester);

    await tester.tap(find.text('Mariana Costa'));
    await tester.pumpAndSettle();

    expect(find.byType(OrderDetailPage), findsOneWidget);
    expect(find.text('Pedido #1042'), findsWidgets);
  });

  testWidgets('detalhe mostra itens e total', (tester) async {
    await _pumpDetailApp(tester, detail: _detail());

    expect(find.text('Mariana Costa'), findsWidgets);
    expect(find.text('Blusa Cropped Listrada'), findsOneWidget);
    expect(find.textContaining('Tam: P'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Total do pedido'),
      220,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Total do pedido'), findsOneWidget);
    expect(find.text('R\$ 389,00'), findsWidgets);

    await tester.scrollUntilVisible(
      find.text('Marcar separado'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Marcar separado'), findsOneWidget);
  });

  testWidgets('novo pedido renderiza campos minimos', (tester) async {
    await _pumpDetailApp(
      tester,
      detail: _detail(status: OperationalOrderStatus.draft),
    );

    expect(find.text('Novo pedido'), findsOneWidget);
    expect(find.text('Cliente ou identificador'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Observacao geral do pedido'),
      220,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Observacao geral do pedido'), findsOneWidget);
    expect(find.text('Adicionar produto'), findsOneWidget);
    expect(find.text('Forma de pagamento'), findsNothing);
    expect(find.text('Frete'), findsNothing);
  });

  testWidgets('separacao usa label Separacao, nao Cozinha', (tester) async {
    await _pumpSeparationApp(tester);

    expect(find.text('Separacao'), findsWidgets);
    expect(find.text('Lista de separacao'), findsOneWidget);
    expect(find.textContaining('Cozinha'), findsNothing);
  });

  testWidgets('tema escuro e largura 360 renderizam sem overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpOrdersApp(tester, themeMode: ThemeMode.dark);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Mariana Costa'), findsOneWidget);
  });
}

Future<void> _pumpOrdersApp(
  WidgetTester tester, {
  ThemeMode themeMode = ThemeMode.light,
}) async {
  final router = GoRouter(
    initialLocation: AppRoutePaths.orders,
    routes: [
      GoRoute(
        path: AppRoutePaths.orders,
        name: AppRouteNames.orders,
        builder: (context, state) => const OrdersPage(),
      ),
      GoRoute(
        path: AppRoutePaths.orderDetail,
        name: AppRouteNames.orderDetail,
        builder: (context, state) => OrderDetailPage(
          orderId: int.parse(state.pathParameters['orderId']!),
        ),
      ),
      GoRoute(
        path: AppRoutePaths.orderKitchen,
        name: AppRouteNames.orderKitchen,
        builder: (context, state) => KitchenOrderViewPage(
          orderId: int.parse(state.pathParameters['orderId']!),
        ),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(),
      child: MaterialApp.router(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: themeMode,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpDetailApp(
  WidgetTester tester, {
  required OperationalOrderDetail detail,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(detail: detail),
      child: MaterialApp(
        theme: AppTheme.light(),
        home: OrderDetailPage(orderId: detail.order.id),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpSeparationApp(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(),
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const KitchenOrderViewPage(orderId: 1042),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

List<Override> _overrides({OperationalOrderDetail? detail}) {
  final orderDetail = detail ?? _detail();
  return [
    operationalOrderBoardProvider.overrideWith(
      (ref) async => OperationalOrderBoardData(orders: [_summary()]),
    ),
    operationalOrderDetailProvider.overrideWith(
      (ref, orderId) async =>
          orderId == orderDetail.order.id ? orderDetail : null,
    ),
  ];
}

OperationalOrderSummary _summary() {
  final detail = _detail();
  return OperationalOrderSummary(
    order: detail.order,
    lineItemsCount: detail.lineItemsCount,
    totalUnits: detail.totalUnits,
    totalCents: detail.totalCents,
    linkedSaleId: null,
  );
}

OperationalOrderDetail _detail({
  OperationalOrderStatus status = OperationalOrderStatus.inPreparation,
}) {
  final createdAt = DateTime(2026, 5, 22, 14, 32);
  final item = OperationalOrderItem(
    id: 10,
    uuid: 'item-10',
    orderId: 1042,
    productId: 20,
    baseProductId: 20,
    productVariantId: 30,
    productRemoteId: 'product-20',
    productVariantRemoteId: 'variant-30',
    variantSkuSnapshot: 'BLU-P-ROSA',
    variantColorSnapshot: 'Rosa',
    variantSizeSnapshot: 'P',
    productNameSnapshot: 'Blusa Cropped Listrada',
    quantityMil: 1000,
    unitPriceCents: 38900,
    subtotalCents: 38900,
    notes: null,
    createdAt: createdAt,
    updatedAt: createdAt,
  );

  return OperationalOrderDetail(
    order: OperationalOrder(
      id: 1042,
      uuid: 'order-1042',
      status: status,
      serviceType: OperationalOrderServiceType.delivery,
      customerIdentifier: 'Mariana Costa',
      customerPhone: '(62) 99123-4567',
      notes: 'Entregar no periodo da tarde.',
      ticketMeta: const OperationalOrderTicketMeta(
        status: OrderTicketDispatchStatus.pending,
        dispatchAttempts: 0,
        lastAttemptAt: null,
        lastSentAt: null,
        lastFailureMessage: null,
      ),
      createdAt: createdAt,
      updatedAt: createdAt,
      sentToKitchenAt: createdAt.add(const Duration(minutes: 3)),
      preparationStartedAt: status == OperationalOrderStatus.inPreparation
          ? createdAt.add(const Duration(minutes: 8))
          : null,
      readyAt: null,
      deliveredAt: null,
      canceledAt: null,
      closedAt: null,
    ),
    items: [OperationalOrderItemDetail(item: item, modifiers: const [])],
    linkedSaleId: null,
  );
}
