import 'package:erp_pdv_app/app/app.dart';
import 'package:erp_pdv_app/app/core/database/app_database.dart';
import 'package:erp_pdv_app/app/core/session/session_reset.dart';
import 'package:erp_pdv_app/modules/dashboard/domain/entities/operational_dashboard_snapshot.dart';
import 'package:erp_pdv_app/modules/dashboard/presentation/pages/dashboard_page.dart';
import 'package:erp_pdv_app/modules/dashboard/presentation/providers/dashboard_providers.dart';
import 'package:erp_pdv_app/modules/estoque/domain/entities/inventory_count_session.dart';
import 'package:erp_pdv_app/modules/estoque/domain/entities/inventory_item.dart';
import 'package:erp_pdv_app/modules/estoque/presentation/providers/inventory_providers.dart';
import 'package:erp_pdv_app/modules/system/presentation/providers/system_providers.dart';
import 'package:erp_pdv_app/app/routes/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  testWidgets('app starts on login and allows offline entry', (tester) async {
    await _pumpOfflineApp(tester);

    expect(find.byType(DashboardPage), findsOneWidget);
    expect(find.text('Dashboard operacional'), findsAtLeastNWidgets(1));
    expect(find.text('Nova venda'), findsAtLeastNWidgets(1));
    expect(find.text('Vendido hoje'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.menu).first);
    await tester.pumpAndSettle();

    expect(find.byType(Drawer), findsOneWidget);

    final drawerScrollable = find.descendant(
      of: find.byType(Drawer),
      matching: find.byType(Scrollable),
    );

    await tester.scrollUntilVisible(
      find.text('Estoque'),
      120,
      scrollable: drawerScrollable,
    );
    await tester.pumpAndSettle();

    expect(find.text('Estoque'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Conta e nuvem'),
      200,
      scrollable: drawerScrollable,
    );
    await tester.pumpAndSettle();

    expect(find.text('Conta e nuvem'), findsOneWidget);
    expect(find.text('Sistema'), findsNothing);
    expect(find.text('Admin cloud'), findsNothing);

    Navigator.of(tester.element(find.byType(Drawer))).pop();
    await tester.pumpAndSettle();

    GoRouter.of(
      tester.element(find.byType(DashboardPage)),
    ).goNamed(AppRouteNames.accountCloud);
    await tester.pumpAndSettle();

    expect(find.text('Conta e nuvem'), findsAtLeastNWidgets(1));
    expect(find.text('Sua conta'), findsOneWidget);
    expect(find.text('Sua empresa'), findsOneWidget);
    expect(find.text('Modo local'), findsWidgets);

    final accountScrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('Nuvem'),
      200,
      scrollable: accountScrollable,
    );
    await tester.scrollUntilVisible(
      find.text('Ajuda e suporte'),
      200,
      scrollable: accountScrollable,
    );
    await tester.pumpAndSettle();

    expect(find.text('Nuvem'), findsOneWidget);
    expect(find.text('Sessao'), findsOneWidget);
    expect(find.text('Ajuda e suporte'), findsOneWidget);
    expect(find.text('Ferramentas internas'), findsNothing);
    expect(find.text('Painel cloud interno'), findsNothing);
  });

  testWidgets('abre a tela de estoque pelo drawer', (tester) async {
    await _pumpOfflineApp(
      tester,
      additionalOverrides: [
        inventoryItemsProvider.overrideWith(
          (ref) async => const <InventoryItem>[],
        ),
      ],
    );

    expect(find.byType(DashboardPage), findsOneWidget);

    await tester.tap(find.byIcon(Icons.menu).first);
    await tester.pumpAndSettle();

    final drawerScrollable = find.descendant(
      of: find.byType(Drawer),
      matching: find.byType(Scrollable),
    );

    await tester.scrollUntilVisible(
      find.text('Estoque'),
      120,
      scrollable: drawerScrollable,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Estoque'));
    await tester.pumpAndSettle();

    expect(find.byType(Drawer), findsNothing);
    expect(find.text('Estoque atual'), findsOneWidget);
    expect(find.text('Ver movimentacoes'), findsOneWidget);
    expect(find.text('Novo ajuste'), findsOneWidget);
    expect(find.text('Inventario fisico'), findsOneWidget);
  });

  testWidgets('abre o inventario fisico pelo drawer', (tester) async {
    await _pumpOfflineApp(
      tester,
      additionalOverrides: [
        inventoryCountSessionsProvider.overrideWith(
          (ref) async => const <InventoryCountSession>[],
        ),
      ],
    );

    await tester.tap(find.byIcon(Icons.menu).first);
    await tester.pumpAndSettle();

    final drawerScrollable = find.descendant(
      of: find.byType(Drawer),
      matching: find.byType(Scrollable),
    );

    await tester.scrollUntilVisible(
      find.text('Inventario fisico'),
      120,
      scrollable: drawerScrollable,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Inventario fisico'));
    await tester.pumpAndSettle();

    expect(find.byType(Drawer), findsNothing);
    expect(find.text('Nova sessao'), findsAtLeastNWidgets(1));
    expect(find.text('Em andamento'), findsOneWidget);
  });
}

Future<void> _pumpOfflineApp(
  WidgetTester tester, {
  List<Override> additionalOverrides = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionContextResetProvider.overrideWith((ref) {}),
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
        backendConnectionStatusProvider.overrideWith(
          (ref) async => BackendConnectionStatus(
            isConfigured: false,
            isReachable: false,
            companyLookupSucceeded: false,
            endpointLabel: 'Uso local',
            message: 'Modo local ativo.',
            checkedAt: DateTime(2026, 4, 5, 10),
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
        ...additionalOverrides,
      ],
      child: const ErpPdvApp(),
    ),
  );

  await tester.pumpAndSettle();

  expect(find.text('Tatuzin'), findsAtLeastNWidgets(1));
  expect(find.text('Continuar offline'), findsOneWidget);

  final continueOfflineButton = find.widgetWithText(
    OutlinedButton,
    'Continuar offline',
  );

  await tester.ensureVisible(continueOfflineButton);
  await tester.pumpAndSettle();
  await tester.tap(continueOfflineButton);
  await tester.pump();
  await tester.pumpAndSettle();
}
