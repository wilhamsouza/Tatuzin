import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:tatuzin/app/core/widgets/product_stock_surface.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tatuzin/app/core/entitlements/plan_entitlements.dart';
import 'package:tatuzin/app/core/session/app_session.dart';
import 'package:tatuzin/app/core/session/company_context.dart';
import 'package:tatuzin/app/core/session/session_provider.dart';
import 'package:tatuzin/app/theme/app_theme.dart';
import 'package:tatuzin/modules/estoque/data/central_inventory_api.dart';
import 'package:tatuzin/modules/estoque/presentation/pages/stock_workspace_page.dart';
import 'package:tatuzin/modules/estoque/presentation/pages/central_count_page.dart';
import 'package:tatuzin/modules/produtos/presentation/pages/products_page.dart';
import 'package:tatuzin/modules/produtos/presentation/providers/product_providers.dart';
import 'package:tatuzin/modules/categorias/presentation/providers/category_providers.dart';
import 'central_inventory_api_test.dart'
    show InventoryTestClient, testInventoryApi;
import 'test_tenant_session.dart';

ProviderContainer _container(InventoryTestClient client) {
  final container = ProviderContainer(
    overrides: [
      centralInventoryApiProvider.overrideWithValue(testInventoryApi(client)),
      categoryOptionsProvider.overrideWith((ref) async => []),
      productListProvider.overrideWith((ref) async => []),
    ],
  );
  setTestTenantSession(container, userId: 'operator');
  final session = container.read(appSessionProvider);
  container
      .read(appSessionProvider.notifier)
      .setAuthenticatedSession(
        scope: session.scope,
        user: session.user,
        company: CompanyContext(
          localId: 1,
          remoteId: session.company.remoteId,
          displayName: 'Empresa de teste',
          legalName: 'Empresa de teste',
          documentNumber: null,
          entitlements: PlanEntitlements.pro,
        ),
        clientInstanceId: session.clientInstanceId,
        membership: const AppMembershipContext(role: 'OWNER', permissions: {}),
      );
  return container;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final width in [360, 390, 768, 1280, 1440]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('estoque $width texto $scale não transborda e mantém abas', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width.toDouble(), 960);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final fonts = FontLoader('NotoSans')
          ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
        await fonts.load();
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await icons.load();
        final client = InventoryTestClient()
          ..items = {
            'items': [
              {
                'productId': 'p',
                'name': 'Camiseta de algodão',
                'sku': 'CAM-AZ-P',
                'currentStockMil': 3000,
                'minimumStockMil': 5000,
                'unitMeasure': 'un',
                'stockRevision': 1,
              },
            ],
            'pagination': {'total': 1},
          };
        final container = _container(client);
        addTearDown(container.dispose);
        final key = GlobalKey();
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: AppTheme.light(),
              home: RepaintBoundary(
                key: key,
                child: const ProductStockSurface(child: StockWorkspacePage()),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Camiseta de algodão'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject() as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory('build/products-stock').create(recursive: true);
          await File(
            'build/products-stock/mobile-$width-$scale.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        await tester.ensureVisible(find.text('Movimentações'));
        await tester.tap(find.text('Movimentações'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Contagens'));
        await tester.tap(find.text('Contagens'));
        await tester.pumpAndSettle();
        expect(find.text('Nova contagem'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
  testWidgets(
    'rascunho de contagem não trata pendente como zero e não confirma saldo',
    (tester) async {
      final client = InventoryTestClient();
      final container = _container(client);
      addTearDown(container.dispose);
      final api = container.read(centralInventoryApiProvider);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: CentralCountPage(
              draft: {
                ...api.newDraft('Contagem de teste'),
                'items': const [
                  {
                    'productId': 'p',
                    'name': 'Produto conferido depois',
                    'currentStockMil': 3000,
                    'stockRevision': 2,
                    'countedStockMil': null,
                  },
                ],
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('0/1 itens contados'), findsOneWidget);
      expect(find.textContaining('Contado: Pendente'), findsOneWidget);
      expect(client.writes, isEmpty);
      expect(find.text('Aplicar diferenças ao estoque'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('Produtos não embute estoque como aba e mantém atalho dedicado', (
    tester,
  ) async {
    final client = InventoryTestClient();
    final container = _container(client);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ProductStockSurface(child: ProductsPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SegmentedButton<int>), findsNothing);
    expect(find.byTooltip('Abrir estoque'), findsOneWidget);
    expect(find.text('Novo produto'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
