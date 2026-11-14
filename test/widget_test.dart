import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:tatuzin/app/app.dart';
import 'package:tatuzin/app/core/config/app_data_mode.dart';
import 'package:tatuzin/app/core/config/app_environment.dart';
import 'package:tatuzin/app/core/database/app_database.dart';
import 'package:tatuzin/app/core/entitlements/plan_entitlements.dart';
import 'package:tatuzin/app/core/network/contracts/auth_gateway.dart';
import 'package:tatuzin/app/core/session/app_session.dart';
import 'package:tatuzin/app/core/session/app_user.dart';
import 'package:tatuzin/app/core/session/auth_provider.dart';
import 'package:tatuzin/app/core/session/company_context.dart';
import 'package:tatuzin/app/core/session/session_provider.dart';
import 'package:tatuzin/app/core/session/session_reset.dart';
import 'package:tatuzin/app/core/sync/sync_queue_feature_summary.dart';
import 'package:tatuzin/app/core/widgets/app_main_drawer.dart';
import 'package:tatuzin/modules/dashboard/domain/entities/operational_dashboard_snapshot.dart';
import 'package:tatuzin/modules/dashboard/presentation/pages/dashboard_page.dart';
import 'package:tatuzin/modules/dashboard/presentation/providers/dashboard_providers.dart';
import 'package:tatuzin/modules/dashboard/presentation/widgets/dashboard_feed_widgets.dart';
import 'package:tatuzin/modules/relatorios/domain/entities/report_overview_summary.dart';
import 'package:tatuzin/modules/relatorios/domain/entities/report_sales_trend_point.dart';
import 'package:tatuzin/modules/relatorios/domain/entities/report_filter.dart';
import 'package:tatuzin/modules/relatorios/presentation/providers/report_providers.dart';
import 'package:tatuzin/modules/onboarding/presentation/onboarding_providers.dart';
import 'package:tatuzin/modules/estoque/domain/entities/inventory_count_session.dart';
import 'package:tatuzin/modules/estoque/domain/entities/inventory_item.dart';
import 'package:tatuzin/modules/estoque/presentation/providers/inventory_providers.dart';
import 'package:tatuzin/modules/produtos/domain/entities/product.dart';
import 'package:tatuzin/modules/produtos/presentation/providers/product_providers.dart';
import 'package:tatuzin/modules/system/presentation/providers/system_providers.dart';
import 'package:tatuzin/app/routes/route_names.dart';
import 'package:tatuzin/app/routes/app_router.dart';
import 'package:tatuzin/modules/activity/presentation/activity_providers.dart';
import 'package:tatuzin/modules/vendas/domain/entities/sale_record.dart';
import 'package:tatuzin/modules/vendas/presentation/providers/sales_providers.dart';
import 'package:tatuzin/app/routes/sale_receipt_navigation.dart';
import 'package:tatuzin/modules/comprovantes/domain/entities/commercial_receipt.dart';
import 'package:tatuzin/modules/comprovantes/presentation/providers/receipt_providers.dart';
import 'package:tatuzin/modules/comprovantes/presentation/pages/receipt_preview_page.dart';
import 'package:tatuzin/modules/historico_vendas/presentation/providers/sale_history_providers.dart';
import 'package:tatuzin/app/core/theme/app_theme_mode_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  for (final variant in [
    (width: 360.0, height: 800.0, scale: 1.0, mode: AppThemeMode.light),
    (width: 360.0, height: 640.0, scale: 1.8, mode: AppThemeMode.dark),
    (width: 412.0, height: 915.0, scale: 2.0, mode: AppThemeMode.light),
  ]) {
    testWidgets(
      'feed mobile ${variant.width} ${variant.scale} ${variant.mode.name}',
      (tester) async {
        tester.view.physicalSize = Size(variant.width, variant.height);
        final disableShadows = debugDisableShadows;
        debugDisableShadows = false;
        addTearDown(() => debugDisableShadows = disableShadows);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = variant.scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final fonts = FontLoader('NotoSans')
          ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
        await fonts.load();
        final container = await _pumpAuthenticatedApp(
          tester,
          additionalOverrides: [
            companyOnboardingProvider.overrideWith((ref) async => null),
            dashboardDailyOverviewProvider.overrideWith(
              (ref) async => _dashboardOverview(),
            ),
            dashboardSalesTrendProvider.overrideWith(
              (ref) async => [
                for (var day = 1; day <= 7; day++)
                  ReportSalesTrendPoint(
                    bucketStart: DateTime(2026, 11, day),
                    bucketEndExclusive: DateTime(2026, 11, day + 1),
                    label: '$day/11',
                    salesCount: day == 2 ? 0 : day,
                    grossSalesCents: day == 2 ? 0 : day * 1000,
                    netSalesCents: day == 2 ? 0 : day * 1000,
                  ),
              ],
            ),
            operationalDashboardSnapshotProvider.overrideWith(
              (ref) async => OperationalDashboardSnapshot(
                soldTodayCents: 152340,
                todaySalesCount: 12,
                hasOpenCashSession: true,
                currentCashCents: 81300,
                pendingFiadoCount: 4,
                pendingFiadoCents: 92750,
                activeOperationalOrdersCount: 3,
                recentMovements: [
                  OperationalDashboardRecentMovement(
                    label: 'Venda recebida',
                    amountCents: 12000,
                    createdAt: DateTime(2026, 11, 7, 15),
                    direction: OperationalDashboardMovementDirection.inflow,
                  ),
                ],
              ),
            ),
          ],
        );
        await container
            .read(appThemeModeControllerProvider.notifier)
            .setThemeMode(variant.mode);
        await tester.pumpAndSettle();
        final prefix =
            '${variant.width.toInt()}x${variant.height.toInt()}-${variant.mode.name}-${variant.scale}';
        await _captureDashboard(tester, '$prefix-top');
        final semantics = tester.ensureSemantics();
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        semantics.dispose();
        final feed = find.byKey(const PageStorageKey('dashboard-feed'));
        for (final title in [
          'Resumo do dia',
          'Lucro realizado',
          'Movimento da loja',
          'Pendências',
          'Últimas movimentações',
          'Seus dados',
        ]) {
          await tester.scrollUntilVisible(
            find.text(title),
            180,
            scrollable: find
                .descendant(of: feed, matching: find.byType(Scrollable))
                .first,
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: title);
          if (title == 'Movimento da loja' || title == 'Pendências') {
            await _captureDashboard(
              tester,
              '$prefix-${title == 'Pendências' ? 'pending' : 'movement'}',
            );
          }
        }
        expect(find.text('Nova venda'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        debugDisableShadows = disableShadows;
      },
    );
  }

  testWidgets(
    'lucro sem custo e série vazia não exibem indicadores inventados',
    (tester) async {
      await _pumpAuthenticatedApp(
        tester,
        additionalOverrides: [
          companyOnboardingProvider.overrideWith((ref) async => null),
          dashboardDailyOverviewProvider.overrideWith(
            (ref) async => _dashboardOverview(costsKnown: false),
          ),
        ],
      );
      await tester.ensureVisible(find.text('Lucro realizado'));
      expect(find.text('Custo não informado'), findsOneWidget);
      expect(find.text('Indisponível'), findsOneWidget);
      await tester.ensureVisible(find.text('Movimento da loja'));
      expect(find.text('Ainda não há vendas neste período.'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow), findsNothing);
      expect(find.byIcon(Icons.favorite_border), findsNothing);
    },
  );

  testWidgets(
    'offline preserva métricas locais sem tratar falha de estoque como zero',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _pumpAuthenticatedApp(
        tester,
        additionalOverrides: [
          companyOnboardingProvider.overrideWith((ref) async => null),
          inventoryItemOptionsProvider.overrideWith(
            (ref) async => throw StateError('stock-query-failed'),
          ),
          backendConnectionStatusProvider.overrideWith(
            (ref) async => BackendConnectionStatus(
              isConfigured: true,
              isReachable: false,
              companyLookupSucceeded: false,
              endpointLabel: 'https://api.tatuzin.com.br/api',
              message: 'offline',
              checkedAt: DateTime.now(),
            ),
          ),
        ],
      );
      expect(find.text('Sem internet'), findsAtLeastNWidgets(1));
      await tester.ensureVisible(
        find.byKey(const ValueKey('dashboard-today-sales')),
      );
      expect(find.text('R\$ 1.523,40'), findsOneWidget);
      await tester.ensureVisible(
        find.textContaining('Não foi possível consultar o estoque.'),
      );
      expect(find.text('Estoque em dia'), findsNothing);
      expect(find.textContaining('stock-query-failed'), findsNothing);
      await _captureDashboard(tester, 'offline-partial');
    },
  );

  testWidgets('feed conserva filtros dos relatórios e respeita permissões', (
    tester,
  ) async {
    final container = await _pumpAuthenticatedApp(tester);
    final filter = ReportFilter(
      start: DateTime(2025),
      endExclusive: DateTime(2025, 2),
    );
    container.read(reportFilterProvider.notifier).replace(filter);
    final session = container.read(appSessionProvider);
    container
        .read(appSessionProvider.notifier)
        .setAuthenticatedSession(
          scope: session.scope,
          user: session.user,
          company: session.company,
          clientInstanceId: session.clientInstanceId,
          membership: const AppMembershipContext(
            role: 'OPERATOR',
            permissions: {'sales.create'},
          ),
        );
    await tester.pumpAndSettle();
    final shortcuts = find.byType(DashboardShortcut);
    expect(
      find.descendant(of: shortcuts, matching: find.text('Equipe')),
      findsNothing,
    );
    expect(
      find.descendant(of: shortcuts, matching: find.text('Relatórios')),
      findsNothing,
    );
    expect(
      find.descendant(of: shortcuts, matching: find.text('Caixa')),
      findsNothing,
    );
    expect(find.text('Lucro realizado'), findsNothing);
    expect(container.read(reportFilterProvider), same(filter));
    expect(find.text('Nova venda'), findsOneWidget);
    expect(await container.read(dashboardDailyOverviewProvider.future), isNull);
  });

  testWidgets('falha da série preserva resumo e oferece nova tentativa', (
    tester,
  ) async {
    await _pumpAuthenticatedApp(
      tester,
      additionalOverrides: [
        companyOnboardingProvider.overrideWith((ref) async => null),
        dashboardSalesTrendProvider.overrideWith(
          (ref) async => throw StateError('private-db-error'),
        ),
      ],
    );
    await tester.ensureVisible(find.text('Movimento da loja'));
    expect(
      find.textContaining('Não foi possível consultar a série'),
      findsOneWidget,
    );
    expect(find.text('Tentar novamente'), findsAtLeastNWidgets(1));
    expect(find.text('Resumo do dia'), findsOneWidget);
    expect(find.textContaining('private-db-error'), findsNothing);
  });

  testWidgets('carregamento preserva atalhos e botão de nova venda', (
    tester,
  ) async {
    final pending = Completer<OperationalDashboardSnapshot>();
    await _pumpAuthenticatedApp(
      tester,
      settle: false,
      additionalOverrides: [
        companyOnboardingProvider.overrideWith((ref) async => null),
        operationalDashboardSnapshotProvider.overrideWith(
          (ref) => pending.future,
        ),
      ],
    );
    expect(find.text('Atualizando dashboard'), findsOneWidget);
    expect(find.byType(DashboardShortcut), findsWidgets);
    expect(find.text('Nova venda'), findsOneWidget);
  });

  testWidgets(
    'duas vendas fecham comprovante fora das abas e preservam busca',
    (tester) async {
      final container = await _pumpAuthenticatedApp(
        tester,
        additionalOverrides: [
          productListProvider.overrideWith((ref) async => []),
          salesCatalogProvider.overrideWith((ref) async => []),
          dailySaleActivityProvider.overrideWith((ref) async => []),
          saleReturnsProvider.overrideWith((ref, id) async => []),
          saleDetailProvider.overrideWith(
            (ref, id) async => throw StateError(
              'Detalhe indisponível no fixture de navegação',
            ),
          ),
          commercialReceiptProvider.overrideWith(
            (ref, request) async => CommercialReceipt(
              type: CommercialReceiptType.cashSale,
              identifier: '${request.saleId}',
              issuedAt: DateTime(2026),
              businessName: 'Loja',
              title: 'Comprovante',
              statusLabel: 'Ativa',
              operationDetails: const [],
              items: const [],
              extraDetails: const [],
              subtotalCents: 1000,
              discountCents: 0,
              surchargeCents: 0,
              totalCents: 1000,
              subtotalLabel: 'Subtotal',
              totalLabel: 'Total',
              footerMessage: 'Teste de navegação',
            ),
          ),
        ],
      );
      final router = container.read(appRouterProvider);
      router.goNamed(AppRouteNames.products);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Camiseta');
      for (final id in [1, 2]) {
        showCompletedSaleReceipt(
          router,
          saleId: id,
          isCurrentSession: () => true,
        );
        await tester.pumpAndSettle();
        expect(find.byType(ReceiptPreviewPage), findsOneWidget);
        if (id == 1) {
          await tester.tap(find.text('Voltar para vendas'));
        } else {
          await tester.binding.handlePopRoute();
        }
        await tester.pumpAndSettle();
        expect(find.byType(ReceiptPreviewPage), findsNothing);
        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text('Atividade'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Vendas de hoje'), findsOneWidget);
        expect(find.byType(ReceiptPreviewPage), findsNothing);
      }
      router.goNamed(AppRouteNames.saleDetail, pathParameters: {'saleId': '1'});
      await tester.pumpAndSettle();
      router.pushNamed(
        AppRouteNames.saleReceipt,
        pathParameters: {'saleId': '1'},
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Detalhe da venda'), findsOneWidget);
      router.goNamed(AppRouteNames.products);
      await tester.pumpAndSettle();
      expect(find.text('Camiseta'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('menu por toque e gesto nas cinco abas com fonte ampliada', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final container = await _pumpAuthenticatedApp(
      tester,
      additionalOverrides: [
        productListProvider.overrideWith((ref) async => []),
        salesCatalogProvider.overrideWith((ref) async => []),
        dailySaleActivityProvider.overrideWith(
          (ref) async => const <SaleRecord>[],
        ),
      ],
    );
    final router = container.read(appRouterProvider);
    for (final mode in [AppThemeMode.light, AppThemeMode.dark]) {
      await container
          .read(appThemeModeControllerProvider.notifier)
          .setThemeMode(mode);
      await tester.pumpAndSettle();
      for (final route in [
        AppRouteNames.dashboard,
        AppRouteNames.products,
        AppRouteNames.sales,
        AppRouteNames.activity,
        AppRouteNames.profile,
      ]) {
        router.goNamed(route);
        await tester.pumpAndSettle();
        final scaffoldFinder = find.byWidgetPredicate(
          (w) => w is Scaffold && w.drawer != null,
        );
        final scaffold = tester.state<ScaffoldState>(scaffoldFinder.last);
        final menuIcon = find.byWidgetPredicate(
          (widget) =>
              widget is Icon &&
              (widget.icon == Icons.menu || widget.icon == Icons.menu_rounded),
        );
        await tester.tap(menuIcon.last);
        await tester.pumpAndSettle();
        expect(find.byType(AppMainDrawer), findsOneWidget);
        expect(find.textContaining('Tatuzin v'), findsOneWidget);
        expect(tester.takeException(), isNull);
        scaffold.closeDrawer();
        await tester.pumpAndSettle();
        await tester.dragFrom(const Offset(1, 180), const Offset(280, 0));
        await tester.pumpAndSettle();
        expect(scaffold.isDrawerOpen, true);
        expect(tester.takeException(), isNull);
        scaffold.closeDrawer();
        await tester.pumpAndSettle();
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('app abre shell somente com sessão tenant válida', (
    tester,
  ) async {
    await _pumpAuthenticatedApp(tester);

    expect(find.byType(DashboardPage), findsOneWidget);
    expect(find.text('Início'), findsAtLeastNWidgets(1));
    expect(find.text('Nova venda'), findsAtLeastNWidgets(1));
    expect(find.text('Vendas de hoje'), findsOneWidget);

    await _openMainDrawer(tester);

    expect(find.byType(Drawer), findsOneWidget);

    final drawerScrollable = _mainDrawerScrollable();

    await tester.scrollUntilVisible(
      find.descendant(of: find.byType(Drawer), matching: find.text('Produtos')),
      120,
      scrollable: drawerScrollable,
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: find.byType(Drawer), matching: find.text('Produtos')),
      findsOneWidget,
    );

    await tester.scrollUntilVisible(
      find.text('Configurações'),
      200,
      scrollable: drawerScrollable,
    );
    await tester.pumpAndSettle();

    expect(find.text('Conta'), findsOneWidget);
    expect(find.text('Empresa'), findsOneWidget);
    expect(find.text('Configurações'), findsOneWidget);
    expect(find.text('Backup'), findsNothing);
    expect(find.text('Assinatura e planos'), findsNothing);
    expect(find.text('Sistema'), findsNothing);
    expect(find.text('Admin cloud'), findsNothing);

    Navigator.of(tester.element(find.byType(Drawer))).pop();
    await tester.pumpAndSettle();

    GoRouter.of(
      tester.element(find.byType(DashboardPage)),
    ).goNamed(AppRouteNames.accountCloud);
    await tester.pumpAndSettle();

    expect(find.text('Conta'), findsAtLeastNWidgets(1));
    expect(find.text('Sessão atual'), findsOneWidget);

    final accountScrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('Assinatura'),
      200,
      scrollable: accountScrollable,
    );
    await tester.pumpAndSettle();

    expect(find.text('Assinatura'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Nuvem'),
      200,
      scrollable: accountScrollable,
    );
    await tester.pumpAndSettle();

    expect(find.text('Nuvem'), findsOneWidget);
    expect(find.text('Ferramentas internas'), findsNothing);
    expect(find.text('Painel cloud interno'), findsNothing);
  });

  testWidgets('abre a tela de produtos pelo drawer', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpAuthenticatedApp(
      tester,
      additionalOverrides: [
        inventoryItemsProvider.overrideWith(
          (ref) async => const <InventoryItem>[],
        ),
        productListProvider.overrideWith((ref) async => const <Product>[]),
      ],
    );

    expect(find.byType(DashboardPage), findsOneWidget);

    await _openMainDrawer(tester);

    final drawerScrollable = _mainDrawerScrollable();

    await tester.scrollUntilVisible(
      find.descendant(of: find.byType(Drawer), matching: find.text('Produtos')),
      120,
      scrollable: drawerScrollable,
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(of: find.byType(Drawer), matching: find.text('Produtos')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Drawer), findsNothing);
    expect(find.text('Produtos'), findsWidgets);
    expect(find.text('Novo produto'), findsAtLeastNWidgets(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Configurações no drawer abre tela própria', (tester) async {
    await _pumpAuthenticatedApp(tester);

    await _openMainDrawer(tester);

    final drawerScrollable = _mainDrawerScrollable();

    await tester.scrollUntilVisible(
      find.text('Configurações'),
      200,
      scrollable: drawerScrollable,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Configurações'));
    await tester.pumpAndSettle();

    expect(find.byType(Drawer), findsNothing);
    expect(find.text('Configurações'), findsWidgets);
    expect(find.textContaining('Preferências do aplicativo'), findsOneWidget);
    expect(find.text('Mais'), findsNothing);
  });

  testWidgets('Dashboard mostra últimas vendas sem código interno', (
    tester,
  ) async {
    await _pumpAuthenticatedApp(
      tester,
      additionalOverrides: [
        operationalDashboardSnapshotProvider.overrideWith(
          (ref) async => OperationalDashboardSnapshot(
            soldTodayCents: 1200,
            currentCashCents: 1200,
            pendingFiadoCount: 0,
            pendingFiadoCents: 0,
            activeOperationalOrdersCount: 0,
            recentMovements: [
              OperationalDashboardRecentMovement(
                label: 'Venda recebida',
                amountCents: 1200,
                createdAt: DateTime(2026, 5, 9, 10, 30),
                direction: OperationalDashboardMovementDirection.inflow,
                description:
                    '[pm:dinheiro] Venda 177811123456 recebida via Dinheiro.',
              ),
            ],
          ),
        ),
      ],
    );

    await tester.ensureVisible(find.text('Últimas movimentações'));
    await tester.pumpAndSettle();

    expect(find.text('Venda recebida'), findsOneWidget);
    expect(find.textContaining('Pagamento em dinheiro.'), findsOneWidget);
    expect(find.textContaining('[pm:dinheiro]'), findsNothing);
    expect(find.textContaining('177811123456'), findsNothing);
  });

  testWidgets('Dashboard vazio com conflitos mostra aviso de hidratacao', (
    tester,
  ) async {
    await _pumpAuthenticatedApp(
      tester,
      additionalOverrides: [
        operationalDashboardSnapshotProvider.overrideWith(
          (ref) async => const OperationalDashboardSnapshot(
            soldTodayCents: 0,
            currentCashCents: 0,
            pendingFiadoCount: 0,
            pendingFiadoCents: 0,
            activeOperationalOrdersCount: 0,
            recentMovements: <OperationalDashboardRecentMovement>[],
          ),
        ),
        syncHealthOverviewProvider.overrideWith(
          (ref) => const SyncHealthOverview(
            totalPending: 0,
            totalProcessing: 0,
            totalActiveProcessing: 0,
            totalStaleProcessing: 0,
            totalSynced: 17,
            totalErrors: 1,
            totalBlocked: 0,
            totalConflicts: 8,
            totalAttempts: 29,
            lastProcessedAt: null,
            lastErrorAt: null,
            nextRetryAt: null,
          ),
        ),
      ],
    );

    expect(find.text('Sincronização precisa de revisão'), findsOneWidget);
    expect(find.textContaining('Seus dados existem na nuvem'), findsOneWidget);
    expect(find.textContaining('precisam de revisão'), findsOneWidget);
  });

  testWidgets('Dashboard nao exibe erro tecnico de banco fechado', (
    tester,
  ) async {
    await _pumpAuthenticatedApp(
      tester,
      additionalOverrides: [
        operationalDashboardSnapshotProvider.overrideWith((ref) async {
          throw Exception('DatabaseException(error database_closed)');
        }),
      ],
    );

    expect(find.text('Falha ao carregar o dashboard'), findsOneWidget);
    expect(
      find.text('Nao foi possivel atualizar o dashboard.'),
      findsOneWidget,
    );
    expect(find.textContaining('DatabaseException'), findsNothing);
    expect(find.textContaining('database_closed'), findsNothing);
  });

  testWidgets('drawer preserva versao com badge longo em tela pequena', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpAuthenticatedApp(
      tester,
      additionalOverrides: [
        syncHealthOverviewProvider.overrideWith(
          (ref) => const SyncHealthOverview(
            totalPending: 0,
            totalProcessing: 0,
            totalActiveProcessing: 0,
            totalStaleProcessing: 0,
            totalSynced: 0,
            totalErrors: 0,
            totalBlocked: 0,
            totalConflicts: 0,
            totalAttempts: 0,
            lastProcessedAt: null,
            lastErrorAt: null,
            nextRetryAt: null,
            hasServerDataStale: true,
            lastSnapshotError: 'snapshot offline',
          ),
        ),
      ],
    );

    await _openMainDrawer(tester);

    expect(find.byType(Drawer), findsOneWidget);
    expect(find.textContaining('Tatuzin v'), findsOneWidget);
    expect(
      find.text('Dados do servidor desatualizados'),
      findsAtLeastNWidgets(1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('abre o inventario fisico pelo drawer', (tester) async {
    await _pumpAuthenticatedApp(
      tester,
      additionalOverrides: [
        inventoryItemsProvider.overrideWith(
          (ref) async => const <InventoryItem>[],
        ),
        inventoryCountSessionsProvider.overrideWith(
          (ref) async => const <InventoryCountSession>[],
        ),
      ],
    );

    await _openMainDrawer(tester);

    final drawerScrollable = _mainDrawerScrollable();

    await tester.scrollUntilVisible(
      find.text('Inventário físico'),
      120,
      scrollable: drawerScrollable,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Inventário físico'));
    await tester.pumpAndSettle();

    expect(find.byType(Drawer), findsNothing);
    expect(find.text('Nova sessão'), findsAtLeastNWidgets(1));
    expect(find.text('Em andamento'), findsOneWidget);
  });
}

Future<ProviderContainer> _pumpAuthenticatedApp(
  WidgetTester tester, {
  List<Override> additionalOverrides = const [],
  bool settle = true,
}) async {
  final container = ProviderContainer(
    overrides: [
      initialAppEnvironmentProvider.overrideWith(
        (ref) => AppEnvironment.remoteDefault().copyWith(
          dataMode: AppDataMode.futureHybridReady,
        ),
      ),
      sessionContextResetProvider.overrideWith((ref) {}),
      remoteAuthGatewayProvider.overrideWith((ref) => _NoSessionGateway()),
      appStartupProvider.overrideWith(
        (ref) async => const AppStartupState.success(),
      ),
      operationalDashboardSnapshotProvider.overrideWith(
        (ref) async => const OperationalDashboardSnapshot(
          soldTodayCents: 152340,
          currentCashCents: 81300,
          pendingFiadoCount: 4,
          pendingFiadoCents: 92750,
          activeOperationalOrdersCount: 3,
          recentMovements: <OperationalDashboardRecentMovement>[],
        ),
      ),
      dashboardDailyOverviewProvider.overrideWith((ref) async => null),
      dashboardSalesTrendProvider.overrideWith((ref) async => []),
      inventoryItemOptionsProvider.overrideWith(
        (ref) async => const <InventoryItem>[],
      ),
      backendConnectionStatusProvider.overrideWith(
        (ref) async => BackendConnectionStatus(
          isConfigured: true,
          isReachable: true,
          companyLookupSucceeded: true,
          endpointLabel: 'https://api.tatuzin.com.br/api',
          message: 'online',
          checkedAt: DateTime(2026, 4, 5, 10),
          remoteCompanyName: 'Cafe Oliveira',
        ),
      ),
      syncHealthOverviewProvider.overrideWith(
        (ref) => const SyncHealthOverview(
          totalPending: 0,
          totalProcessing: 0,
          totalActiveProcessing: 0,
          totalStaleProcessing: 0,
          totalSynced: 0,
          totalErrors: 0,
          totalBlocked: 0,
          totalConflicts: 0,
          totalAttempts: 0,
          lastProcessedAt: null,
          lastErrorAt: null,
          nextRetryAt: null,
        ),
      ),
      syncQueueFeatureSummariesProvider.overrideWith(
        (ref) async => const <SyncQueueFeatureSummary>[],
      ),
      ...additionalOverrides,
    ],
  );
  addTearDown(container.dispose);
  container
      .read(appSessionProvider.notifier)
      .setAuthenticatedSession(
        scope: SessionScope.authenticatedRemote,
        user: const AppUser(
          localId: null,
          remoteId: 'user-1',
          displayName: 'Operador',
          email: 'operador@tatuzin.test',
          roleLabel: 'Operador',
          kind: AppUserKind.remoteAuthenticated,
        ),
        company: const CompanyContext(
          experienceRefreshEnabled: true,
          localId: null,
          remoteId: 'company-1',
          displayName: 'Cafe Oliveira',
          legalName: 'Cafe Oliveira LTDA',
          documentNumber: null,
          licensePlan: 'basic',
          licenseStatus: 'active',
          syncEnabled: true,
          entitlements: PlanEntitlements.basic,
        ),
        clientInstanceId: 'device-1',
        membership: const AppMembershipContext(
          role: 'OWNER',
          permissions: <String>{},
        ),
      );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const RepaintBoundary(
        key: ValueKey('dashboard-preview'),
        child: ErpPdvApp(),
      ),
    ),
  );

  if (settle) {
    await tester.pumpAndSettle();
  } else {
    for (var frame = 0; frame < 5; frame++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  expect(find.text('Continuar offline'), findsNothing);
  return container;
}

Future<void> _openMainDrawer(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.menu).first);
  await tester.pumpAndSettle();

  expect(find.byType(AppMainDrawer), findsOneWidget);
}

// Preview artifacts use test fixtures only, never real company/customer data.
Future<void> _captureDashboard(WidgetTester tester, String name) async {
  final icons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icons.load();
  await tester.runAsync(
    () => precacheImage(
      const AssetImage('assets/branding/logo-transparent.png'),
      tester.element(find.byType(DashboardPage)),
    ),
  );
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('dashboard-preview')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('build/phase1-mobile');
    await dir.create(recursive: true);
    await File(
      '${dir.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

ReportOverviewSummary _dashboardOverview({bool costsKnown = true}) =>
    ReportOverviewSummary(
      filter: ReportFilter(
        start: DateTime(2026, 11, 7),
        endExclusive: DateTime(2026, 11, 8),
      ),
      grossSalesCents: 152340,
      netSalesCents: 152340,
      totalReceivedCents: 120000,
      costOfGoodsSoldCents: 80000,
      realizedProfitCents: costsKnown ? 40000 : 0,
      isRealizedProfitAvailable: costsKnown,
      realizedProfitUnavailableReason: costsKnown
          ? null
          : 'Custo não informado',
      salesCount: 12,
      totalDiscountCents: 0,
      totalSurchargeCents: 0,
      pendingFiadoCents: 92750,
      pendingFiadoCount: 4,
      cancelledSalesCount: 0,
      cancelledSalesCents: 0,
      totalPurchasedCents: 0,
      totalPurchasePaymentsCents: 0,
      totalPurchasePendingCents: 0,
      cashSalesReceivedCents: 120000,
      fiadoReceiptsCents: 0,
      totalCreditGeneratedCents: 0,
      totalCreditUsedCents: 0,
      totalOutstandingCreditCents: 0,
      topCreditCustomers: const [],
      paymentSummaries: const [],
    );

Finder _mainDrawerScrollable() {
  final drawerScrollable = find.descendant(
    of: find.byType(AppMainDrawer),
    matching: find.byType(Scrollable),
  );
  expect(drawerScrollable, findsOneWidget);
  return drawerScrollable;
}

class _NoSessionGateway implements AuthGateway {
  @override
  Future<AppSession?> restoreSession() async => null;

  @override
  Future<AppSession> refreshSession() => throw UnimplementedError();

  @override
  Future<AppSession> signIn({
    required String identifier,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<AppSession> signUp({
    required String companyName,
    required String companySlug,
    required String userName,
    required String email,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<String> requestPasswordReset({required String email}) async => 'ok';

  @override
  Future<String> resetPassword({
    required String token,
    required String newPassword,
  }) async => 'ok';

  @override
  Future<AppSession> changeInitialPassword({required String newPassword}) {
    throw UnimplementedError();
  }

  @override
  Future<void> signOut() async {}
}
