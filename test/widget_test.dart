import 'package:erp_pdv_app/app/app.dart';
import 'package:erp_pdv_app/app/core/config/app_data_mode.dart';
import 'package:erp_pdv_app/app/core/config/app_environment.dart';
import 'package:erp_pdv_app/app/core/database/app_database.dart';
import 'package:erp_pdv_app/app/core/entitlements/plan_entitlements.dart';
import 'package:erp_pdv_app/app/core/network/contracts/auth_gateway.dart';
import 'package:erp_pdv_app/app/core/session/app_session.dart';
import 'package:erp_pdv_app/app/core/session/app_user.dart';
import 'package:erp_pdv_app/app/core/session/auth_provider.dart';
import 'package:erp_pdv_app/app/core/session/company_context.dart';
import 'package:erp_pdv_app/app/core/session/session_provider.dart';
import 'package:erp_pdv_app/app/core/session/session_reset.dart';
import 'package:erp_pdv_app/app/core/sync/sync_queue_feature_summary.dart';
import 'package:erp_pdv_app/app/core/widgets/app_main_drawer.dart';
import 'package:erp_pdv_app/modules/dashboard/domain/entities/operational_dashboard_snapshot.dart';
import 'package:erp_pdv_app/modules/dashboard/presentation/pages/dashboard_page.dart';
import 'package:erp_pdv_app/modules/dashboard/presentation/providers/dashboard_providers.dart';
import 'package:erp_pdv_app/modules/estoque/domain/entities/inventory_count_session.dart';
import 'package:erp_pdv_app/modules/estoque/domain/entities/inventory_item.dart';
import 'package:erp_pdv_app/modules/estoque/presentation/providers/inventory_providers.dart';
import 'package:erp_pdv_app/modules/produtos/domain/entities/product.dart';
import 'package:erp_pdv_app/modules/produtos/presentation/providers/product_providers.dart';
import 'package:erp_pdv_app/modules/system/presentation/providers/system_providers.dart';
import 'package:erp_pdv_app/app/routes/route_names.dart';
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
      find.text('Produtos'),
      120,
      scrollable: drawerScrollable,
    );
    await tester.pumpAndSettle();

    expect(find.text('Produtos'), findsOneWidget);

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
      find.text('Produtos'),
      120,
      scrollable: drawerScrollable,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Produtos'));
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

    await tester.ensureVisible(find.text('Últimas vendas'));
    await tester.pumpAndSettle();

    expect(find.text('Venda recebida'), findsOneWidget);
    expect(find.text('Pagamento em dinheiro.'), findsOneWidget);
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

Future<void> _pumpAuthenticatedApp(
  WidgetTester tester, {
  List<Override> additionalOverrides = const [],
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
    UncontrolledProviderScope(container: container, child: const ErpPdvApp()),
  );

  await tester.pumpAndSettle();

  expect(find.text('Continuar offline'), findsNothing);
}

Future<void> _openMainDrawer(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.menu).first);
  await tester.pumpAndSettle();

  expect(find.byType(AppMainDrawer), findsOneWidget);
}

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
