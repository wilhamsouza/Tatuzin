import 'package:tatuzin/app/core/theme/app_theme.dart';
import 'package:tatuzin/app/core/errors/app_exceptions.dart';
import 'package:tatuzin/app/routes/route_names.dart';
import 'package:tatuzin/modules/pedidos/domain/entities/bluetooth_printer_device.dart';
import 'package:tatuzin/modules/pedidos/domain/entities/kitchen_printer_config.dart';
import 'package:tatuzin/modules/pedidos/domain/entities/operational_order.dart';
import 'package:tatuzin/modules/pedidos/domain/entities/operational_order_detail.dart';
import 'package:tatuzin/modules/pedidos/domain/entities/operational_order_item.dart';
import 'package:tatuzin/modules/pedidos/domain/entities/operational_order_summary.dart';
import 'package:tatuzin/modules/pedidos/domain/entities/order_ticket_document.dart';
import 'package:tatuzin/modules/pedidos/domain/repositories/bluetooth_printer_discovery_repository.dart';
import 'package:tatuzin/modules/pedidos/domain/repositories/kitchen_printer_settings_repository.dart';
import 'package:tatuzin/modules/pedidos/domain/services/kitchen_print_service.dart';
import 'package:tatuzin/modules/pedidos/presentation/pages/kitchen_order_view_page.dart';
import 'package:tatuzin/modules/pedidos/presentation/pages/order_detail_page.dart';
import 'package:tatuzin/modules/pedidos/presentation/pages/orders_page.dart';
import 'package:tatuzin/modules/pedidos/presentation/providers/order_print_providers.dart';
import 'package:tatuzin/modules/pedidos/presentation/providers/order_providers.dart';
import 'package:tatuzin/modules/pedidos/presentation/widgets/kitchen_printer_config_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('tela Pedidos mostra busca, filtros e lista sem resumo', (
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
    expect(find.text('Hoje'), findsNothing);
    expect(find.text('Em separacao'), findsNothing);
    expect(find.text('Total aberto'), findsNothing);
    expect(find.text('Ticket medio'), findsNothing);

    await tester.drag(find.byType(ListView).first, const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(find.textContaining('Vendidos'), findsWidgets);
    expect(find.textContaining('Cancelado'), findsOneWidget);

    expect(find.text('Mariana Costa'), findsOneWidget);
    expect(find.text('R\$ 389,00'), findsAtLeastNWidgets(1));
    expect(find.text('Cancelar pedido'), findsNothing);
    expect(find.text('Finalizar venda'), findsNothing);
    expect(find.text('Imprimir'), findsNothing);
  });

  testWidgets('busca e filtros de Pedidos continuam filtrando a lista', (
    tester,
  ) async {
    await _pumpOrdersApp(tester);

    await tester.enterText(find.byType(TextField), 'sem resultado');
    await tester.pumpAndSettle();

    expect(find.text('Mariana Costa'), findsNothing);
    expect(find.text('Nenhum pedido encontrado'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Mariana');
    await tester.pumpAndSettle();

    expect(find.text('Mariana Costa'), findsOneWidget);

    await tester.tap(find.textContaining('Pendente/Aberto'));
    await tester.pumpAndSettle();

    expect(find.text('Mariana Costa'), findsNothing);
    expect(find.text('Nenhum pedido encontrado'), findsOneWidget);

    await tester.tap(find.textContaining('Todos'));
    await tester.pumpAndSettle();

    expect(find.text('Mariana Costa'), findsOneWidget);
  });

  testWidgets('pedido pronto mostra acao clara para finalizar venda', (
    tester,
  ) async {
    await _pumpOrdersApp(
      tester,
      detail: _detail(status: OperationalOrderStatus.ready),
    );

    expect(find.text('Finalizar venda'), findsOneWidget);
    expect(find.text('Separado'), findsWidgets);
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

  testWidgets('modal de impressora renderiza Bluetooth e Rede', (tester) async {
    await _pumpPrinterDialog(tester);

    expect(find.text('Configurar impressora'), findsOneWidget);
    expect(
      find.text('Escolha como o Tatuzin deve enviar as impressoes.'),
      findsOneWidget,
    );
    expect(find.text('Bluetooth'), findsOneWidget);
    expect(find.text('Rede Wi-Fi'), findsOneWidget);
    expect(find.text('Procurar impressoras Bluetooth'), findsOneWidget);
    expect(
      find.textContaining('informar endereco manualmente'),
      findsOneWidget,
    );

    await tester.tap(find.text('Rede Wi-Fi'));
    await tester.pumpAndSettle();

    expect(find.text('IP da impressora'), findsOneWidget);
    expect(find.text('Porta'), findsOneWidget);
    expect(find.text('Procurar na rede'), findsOneWidget);
    expect(find.text('Testar impressao'), findsOneWidget);
  });

  testWidgets('selecionar Bluetooth preenche dados e salva', (tester) async {
    final settings = _FakeKitchenPrinterSettingsRepository();
    await _pumpPrinterDialog(
      tester,
      overrides: [
        kitchenPrinterSettingsRepositoryProvider.overrideWithValue(settings),
        bluetoothPrinterDiscoveryRepositoryProvider.overrideWithValue(
          const _FakeBluetoothPrinterDiscoveryRepository([
            BluetoothPrinterDevice(
              name: 'Tatuzin BT 58',
              address: '00:11:22:33:44:55',
            ),
          ]),
        ),
      ],
    );

    await tester.tap(find.text('Procurar impressoras Bluetooth'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Tatuzin BT 58'));
    await tester.tap(find.widgetWithText(ListTile, 'Tatuzin BT 58'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.textContaining('informar endereco manualmente'),
    );
    await tester.tap(find.textContaining('informar endereco manualmente'));
    await tester.pumpAndSettle();

    expect(find.text('00:11:22:33:44:55'), findsWidgets);

    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(settings.saved?.displayName, 'Tatuzin BT 58');
    expect(
      settings.saved?.connectionType,
      KitchenPrinterConnectionType.bluetooth,
    );
    expect(settings.saved?.bluetoothAddress, '00:11:22:33:44:55');
  });

  testWidgets('busca Bluetooth vazia mostra mensagem amigavel', (tester) async {
    await _pumpPrinterDialog(
      tester,
      overrides: [
        bluetoothPrinterDiscoveryRepositoryProvider.overrideWithValue(
          const _FakeBluetoothPrinterDiscoveryRepository([]),
        ),
      ],
    );

    await tester.tap(find.text('Procurar impressoras Bluetooth'));
    await tester.pumpAndSettle();

    expect(
      find.text('Nenhuma impressora Bluetooth encontrada.'),
      findsOneWidget,
    );
    expect(find.textContaining('ligada e pareada'), findsOneWidget);
    expect(
      find.textContaining('informar endereco manualmente'),
      findsOneWidget,
    );
  });

  testWidgets('teste de impressao trata sucesso e erro amigavel', (
    tester,
  ) async {
    final printService = _FakeKitchenPrintService();
    await _pumpPrinterDialog(
      tester,
      initialConfig: const KitchenPrinterConfig(
        displayName: 'Rede Balcao',
        connectionType: KitchenPrinterConnectionType.network,
        host: '192.168.0.120',
      ),
      overrides: [kitchenPrintServiceProvider.overrideWithValue(printService)],
    );

    await tester.tap(find.text('Testar impressao'));
    await tester.pumpAndSettle();

    expect(printService.tested?.host, '192.168.0.120');
    expect(find.text('Teste de impressao enviado.'), findsOneWidget);

    printService.fail = true;
    await tester.tap(find.text('Testar impressao'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Falha no teste:'), findsOneWidget);
    expect(
      find.textContaining('Verifique se a impressora esta ligada'),
      findsOneWidget,
    );
  });
}

Future<void> _pumpOrdersApp(
  WidgetTester tester, {
  ThemeMode themeMode = ThemeMode.light,
  OperationalOrderDetail? detail,
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
      overrides: _overrides(detail: detail),
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

Future<void> _pumpPrinterDialog(
  WidgetTester tester, {
  KitchenPrinterConfig? initialConfig,
  List<Override> overrides = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => KitchenPrinterConfigDialog(
                      initialConfig: initialConfig,
                    ),
                  ),
                  child: const Text('Abrir configuracao'),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.tap(find.text('Abrir configuracao'));
  await tester.pumpAndSettle();
}

List<Override> _overrides({OperationalOrderDetail? detail}) {
  final orderDetail = detail ?? _detail();
  return [
    operationalOrderBoardProvider.overrideWith((ref) async {
      final query = ref
          .watch(operationalOrderSearchQueryProvider)
          .trim()
          .toLowerCase();
      final summary = _summary(orderDetail);
      if (query.isEmpty ||
          summary.order.id.toString().contains(query) ||
          summary.order.customerLabel.toLowerCase().contains(query)) {
        return OperationalOrderBoardData(orders: [summary]);
      }
      return const OperationalOrderBoardData(orders: []);
    }),
    operationalOrderDetailProvider.overrideWith(
      (ref, orderId) async =>
          orderId == orderDetail.order.id ? orderDetail : null,
    ),
  ];
}

OperationalOrderSummary _summary([OperationalOrderDetail? source]) {
  final detail = source ?? _detail();
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

class _FakeBluetoothPrinterDiscoveryRepository
    implements BluetoothPrinterDiscoveryRepository {
  const _FakeBluetoothPrinterDiscoveryRepository(this.devices);

  final List<BluetoothPrinterDevice> devices;

  @override
  Future<BluetoothPrinterDiscoveryResult> listPrinters() async {
    return BluetoothPrinterDiscoveryResult(
      status: BluetoothPrinterDiscoveryStatus.available,
      devices: devices,
      message: devices.isEmpty
          ? 'Nenhuma impressora Bluetooth encontrada.'
          : '${devices.length} impressora(s) Bluetooth encontrada(s).',
    );
  }
}

class _FakeKitchenPrinterSettingsRepository
    implements KitchenPrinterSettingsRepository {
  KitchenPrinterConfig? saved;

  @override
  Future<void> clearDefault() async {
    saved = null;
  }

  @override
  Future<KitchenPrinterConfig?> loadDefault() async => saved;

  @override
  Future<void> saveDefault(KitchenPrinterConfig config) async {
    saved = config;
  }
}

class _FakeKitchenPrintService implements KitchenPrintService {
  KitchenPrinterConfig? tested;
  bool fail = false;

  @override
  Future<void> print({
    required KitchenPrinterConfig printer,
    required OrderTicketDocument ticket,
  }) async {}

  @override
  Future<void> printTest({required KitchenPrinterConfig printer}) async {
    tested = printer;
    if (fail) {
      throw const ValidationException(
        'Verifique se a impressora esta ligada e pareada.',
      );
    }
  }
}
