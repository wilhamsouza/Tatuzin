import 'package:erp_pdv_app/app/app.dart';
import 'package:erp_pdv_app/app/core/config/app_data_mode.dart';
import 'package:erp_pdv_app/app/core/config/app_environment.dart';
import 'package:erp_pdv_app/app/core/database/app_database.dart';
import 'package:erp_pdv_app/app/core/entitlements/feature_gate.dart';
import 'package:erp_pdv_app/app/core/entitlements/plan_entitlements.dart';
import 'package:erp_pdv_app/app/core/errors/app_exceptions.dart';
import 'package:erp_pdv_app/app/core/network/contracts/auth_gateway.dart';
import 'package:erp_pdv_app/app/core/session/app_session.dart';
import 'package:erp_pdv_app/app/core/session/app_user.dart';
import 'package:erp_pdv_app/app/core/session/auth_provider.dart';
import 'package:erp_pdv_app/app/core/session/company_context.dart';
import 'package:erp_pdv_app/app/core/session/session_provider.dart';
import 'package:erp_pdv_app/app/core/session/session_reset.dart';
import 'package:erp_pdv_app/app/core/sync/sync_queue_feature_summary.dart';
import 'package:erp_pdv_app/app/routes/app_router.dart';
import 'package:erp_pdv_app/app/routes/route_names.dart';
import 'package:erp_pdv_app/modules/auth/presentation/pages/login_page.dart';
import 'package:erp_pdv_app/modules/dashboard/domain/entities/operational_dashboard_snapshot.dart';
import 'package:erp_pdv_app/modules/dashboard/presentation/pages/dashboard_page.dart';
import 'package:erp_pdv_app/modules/dashboard/presentation/providers/dashboard_providers.dart';
import 'package:erp_pdv_app/modules/estoque/domain/entities/inventory_item.dart';
import 'package:erp_pdv_app/modules/estoque/presentation/providers/inventory_providers.dart';
import 'package:erp_pdv_app/modules/produtos/presentation/providers/product_providers.dart';
import 'package:erp_pdv_app/modules/system/presentation/providers/system_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'rotas principais continuam registradas com os mesmos nomes e paths',
    () {
      final container = ProviderContainer(overrides: _baseOverrides());
      addTearDown(container.dispose);

      final router = container.read(appRouterProvider);

      expect(router.namedLocation(AppRouteNames.login), AppRoutePaths.login);
      expect(
        router.namedLocation(AppRouteNames.dashboard),
        AppRoutePaths.dashboard,
      );
      expect(router.namedLocation(AppRouteNames.sales), AppRoutePaths.sales);
      expect(router.namedLocation(AppRouteNames.cart), AppRoutePaths.cart);
      expect(router.namedLocation(AppRouteNames.cash), AppRoutePaths.cash);
      expect(router.namedLocation(AppRouteNames.orders), AppRoutePaths.orders);
      expect(
        router.namedLocation(AppRouteNames.products),
        AppRoutePaths.products,
      );
      expect(
        router.namedLocation(AppRouteNames.inventory),
        AppRoutePaths.inventory,
      );
      expect(
        router.namedLocation(AppRouteNames.inventoryCounts),
        AppRoutePaths.inventoryCounts,
      );
      expect(
        router.namedLocation(
          AppRouteNames.inventoryCountSessionDetail,
          pathParameters: {'sessionId': '12'},
        ),
        '/estoque/inventarios/12',
      );
      expect(
        router.namedLocation(AppRouteNames.inventoryMovements),
        AppRoutePaths.inventoryMovements,
      );
      expect(
        router.namedLocation(AppRouteNames.inventoryAdjustment),
        AppRoutePaths.inventoryAdjustment,
      );
      expect(
        router.namedLocation(AppRouteNames.clients),
        AppRoutePaths.clients,
      );
      expect(
        router.namedLocation(AppRouteNames.reports),
        AppRoutePaths.reports,
      );
      expect(
        router.namedLocation(AppRouteNames.employees),
        AppRoutePaths.employees,
      );
      expect(
        router.namedLocation(AppRouteNames.employeeActivity),
        AppRoutePaths.employeeActivity,
      );
      expect(
        router.namedLocation(AppRouteNames.employeeCommissions),
        AppRoutePaths.employeeCommissions,
      );
      expect(
        router.namedLocation(
          AppRouteNames.employeeActivityDetail,
          pathParameters: {'employeeId': 'abc'},
        ),
        '/funcionarios/abc/atividade',
      );
      expect(
        router.namedLocation(
          AppRouteNames.employeeCommissionDetail,
          pathParameters: {'employeeId': 'abc'},
        ),
        '/funcionarios/abc/comissoes',
      );
      expect(
        router.namedLocation(AppRouteNames.subscription),
        AppRoutePaths.subscription,
      );
      expect(
        router.namedLocation(AppRouteNames.company),
        AppRoutePaths.company,
      );
      expect(
        router.namedLocation(AppRouteNames.settings),
        AppRoutePaths.settings,
      );
      expect(
        router.namedLocation(
          AppRouteNames.orderDetail,
          pathParameters: {'orderId': '42'},
        ),
        '/pedidos/42',
      );
      expect(
        router.namedLocation(
          AppRouteNames.fiadoPaymentReceipt,
          pathParameters: {'fiadoId': '7', 'entryId': '9'},
        ),
        '/comprovantes/fiado/7/pagamentos/9',
      );
    },
  );

  testWidgets('rota de detalhe com id invalido mostra erro amigavel', (
    tester,
  ) async {
    await _pumpApp(tester, authenticated: true);

    final router = GoRouter.of(tester.element(find.byType(DashboardPage)));
    router.go('/pedidos/id-invalido');
    await tester.pumpAndSettle();

    expect(find.text('Rota invalida'), findsOneWidget);
    expect(find.textContaining('orderId'), findsAtLeastNWidgets(1));
  });

  testWidgets('deep link inexistente mostra fallback seguro', (tester) async {
    await _pumpApp(tester, authenticated: true);

    final router = GoRouter.of(tester.element(find.byType(DashboardPage)));
    router.go('/link-que-nao-existe');
    await tester.pumpAndSettle();

    expect(find.text('Rota indisponivel'), findsOneWidget);
  });

  testWidgets('/produtos e /estoque abrem o hub na aba correta', (
    tester,
  ) async {
    await _pumpApp(tester, authenticated: true);

    final router = GoRouter.of(tester.element(find.byType(DashboardPage)));
    router.go(AppRoutePaths.products);
    await tester.pumpAndSettle();

    expect(find.text('Produtos'), findsWidgets);
    expect(find.text('Novo produto'), findsWidgets);
    expect(find.text('Movimentações'), findsNothing);

    router.go(AppRoutePaths.inventory);
    await tester.pumpAndSettle();

    expect(find.text('Produtos'), findsWidgets);
    expect(find.text('Novo ajuste'), findsWidgets);
    expect(find.text('Movimentações'), findsOneWidget);
    expect(find.text('Ajuste'), findsNothing);
  });

  testWidgets('rota protegida sem sessao redireciona para login', (
    tester,
  ) async {
    await _pumpApp(tester);

    final router = GoRouter.of(tester.element(find.byType(LoginPage)));
    router.go(AppRoutePaths.sales);
    await tester.pumpAndSettle();

    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets(
    'sessao com mustChangePassword restaura na troca e bloqueia rota protegida',
    (tester) async {
      final container = ProviderContainer(
        overrides: _baseOverrides(remoteGateway: _InitialPasswordGateway()),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const ErpPdvApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Crie sua nova senha'), findsOneWidget);

      final router = GoRouter.of(
        tester.element(find.text('Crie sua nova senha')),
      );
      router.go(AppRoutePaths.sales);
      await tester.pumpAndSettle();

      expect(find.text('Crie sua nova senha'), findsOneWidget);
      expect(find.byType(DashboardPage), findsNothing);
    },
  );

  testWidgets('rota operacional sem tenant nao abre shell', (tester) async {
    await _pumpApp(tester, configureSession: _setSessionWithoutTenant);

    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byType(DashboardPage), findsNothing);
  });

  testWidgets('rotas internas continuam protegidas sem sessao', (tester) async {
    await _pumpApp(tester);

    final router = GoRouter.of(tester.element(find.byType(LoginPage)));
    router.go(AppRoutePaths.admin);
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);

    router.go(AppRoutePaths.technicalSystem);
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets('deep link de funcionarios bloqueia FREE com página locked', (
    tester,
  ) async {
    await _pumpApp(tester, authenticated: true);

    final router = GoRouter.of(tester.element(find.byType(DashboardPage)));
    router.go(AppRoutePaths.employees);
    await tester.pumpAndSettle();

    expect(find.text('Funcionários'), findsWidgets);
    expect(find.text('Ativar teste gratis'), findsOneWidget);
    expect(find.textContaining('plano Pro'), findsOneWidget);
  });

  testWidgets('PRO sem employees.manage mostra sem permissão', (tester) async {
    await _pumpApp(tester, configureSession: _setProTenantSession);

    final router = GoRouter.of(tester.element(find.byType(DashboardPage)));
    router.go(AppRoutePaths.employees);
    await tester.pumpAndSettle();

    expect(find.text('Sem permissão'), findsWidgets);
    expect(find.text('Ver planos'), findsNothing);
  });

  testWidgets('Caixa não acessa deep link administrativo', (tester) async {
    await _pumpApp(tester, configureSession: _setCashierSession);

    final router = GoRouter.of(tester.element(find.byType(DashboardPage)));
    router.go(AppRoutePaths.reports);
    await tester.pumpAndSettle();

    expect(find.text('Sem permissão'), findsWidgets);
    expect(
      find.text('Você não tem permissão para acessar esta área.'),
      findsOneWidget,
    );
    expect(find.byType(DashboardPage), findsNothing);
  });

  testWidgets('drawer de Caixa mostra só módulos permitidos', (tester) async {
    await _pumpApp(tester, configureSession: _setCashierSession);

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    expect(find.text('PDV / Vendas'), findsOneWidget);
    expect(find.text('Caixa'), findsWidgets);
    expect(find.text('Produtos'), findsOneWidget);
    expect(find.text('Funcionários'), findsNothing);
    expect(find.text('Configurações'), findsNothing);
    expect(find.text('Relatórios'), findsNothing);
  });
  testWidgets('Caixa nao acessa deep link de estoque sem stock.adjust', (
    tester,
  ) async {
    await _pumpApp(tester, configureSession: _setCashierSession);

    final router = GoRouter.of(tester.element(find.byType(DashboardPage)));
    router.go(AppRoutePaths.inventory);
    await tester.pumpAndSettle();

    expect(find.byType(PermissionDeniedPage), findsOneWidget);
    expect(find.byType(DashboardPage), findsNothing);
  });

  testWidgets('Caixa ve catalogo sem acoes de escrita ou estoque', (
    tester,
  ) async {
    await _pumpApp(tester, configureSession: _setCashierSession);

    final router = GoRouter.of(tester.element(find.byType(DashboardPage)));
    router.go(AppRoutePaths.products);
    await tester.pumpAndSettle();

    expect(find.text('Produtos'), findsWidgets);
    expect(find.text('Novo produto'), findsNothing);
    expect(find.text('Estoque'), findsNothing);
    expect(find.text('Editar'), findsNothing);
    expect(find.text('Excluir'), findsNothing);
  });
}

List<Override> _baseOverrides({AuthGateway? remoteGateway}) {
  return <Override>[
    initialAppEnvironmentProvider.overrideWith(
      (ref) => AppEnvironment.remoteDefault().copyWith(
        dataMode: AppDataMode.futureHybridReady,
      ),
    ),
    sessionContextResetProvider.overrideWith((ref) {}),
    remoteAuthGatewayProvider.overrideWith(
      (ref) => remoteGateway ?? _NoSessionGateway(),
    ),
    appStartupProvider.overrideWith(
      (ref) async => const AppStartupState.success(),
    ),
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
    inventoryItemOptionsProvider.overrideWith(
      (ref) async => const <InventoryItem>[],
    ),
    inventoryItemsProvider.overrideWith((ref) async => const <InventoryItem>[]),
    productListProvider.overrideWith((ref) async => []),
    backendConnectionStatusProvider.overrideWith(
      (ref) async => BackendConnectionStatus(
        isConfigured: true,
        isReachable: true,
        companyLookupSucceeded: true,
        endpointLabel: 'https://api.tatuzin.test/api',
        message: 'online',
        checkedAt: DateTime(2026, 5, 5, 10),
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
  ];
}

Future<void> _pumpApp(
  WidgetTester tester, {
  bool authenticated = false,
  void Function(ProviderContainer container)? configureSession,
}) async {
  final container = ProviderContainer(overrides: _baseOverrides());
  addTearDown(container.dispose);

  if (authenticated) {
    _setValidTenantSession(container);
  }
  configureSession?.call(container);

  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const ErpPdvApp()),
  );
  await tester.pumpAndSettle();
}

void _setValidTenantSession(ProviderContainer container) {
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
          licensePlan: 'trial',
          licenseStatus: 'trial',
          syncEnabled: true,
          entitlements: PlanEntitlements.free,
        ),
        clientInstanceId: 'device-1',
        membership: const AppMembershipContext(
          role: 'OWNER',
          permissions: {'*'},
        ),
      );
}

void _setProTenantSession(ProviderContainer container) {
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
          licensePlan: 'pro',
          licenseStatus: 'active',
          syncEnabled: true,
          entitlements: PlanEntitlements.pro,
        ),
        clientInstanceId: 'device-1',
      );
}

void _setCashierSession(ProviderContainer container) {
  container
      .read(appSessionProvider.notifier)
      .setAuthenticatedSession(
        scope: SessionScope.authenticatedRemote,
        user: const AppUser(
          localId: null,
          remoteId: 'user-cashier',
          displayName: 'Caixa',
          email: 'caixa@tatuzin.test',
          roleLabel: 'Caixa',
          kind: AppUserKind.remoteAuthenticated,
        ),
        company: const CompanyContext(
          localId: null,
          remoteId: 'company-1',
          displayName: 'Cafe Oliveira',
          legalName: 'Cafe Oliveira LTDA',
          documentNumber: null,
          licensePlan: 'pro',
          licenseStatus: 'active',
          syncEnabled: true,
          entitlements: PlanEntitlements.pro,
        ),
        clientInstanceId: 'device-1',
        membership: const AppMembershipContext(
          role: 'OPERATOR',
          permissions: {
            'sales.create',
            'cash.open',
            'cash.close',
            'products.read',
          },
        ),
        employee: const AppEmployeeContext(
          id: 'employee-cashier',
          role: 'CASHIER',
          status: 'ACTIVE',
          permissions: {
            'sales.create',
            'cash.open',
            'cash.close',
            'products.read',
          },
        ),
      );
}

void _setSessionWithoutTenant(ProviderContainer container) {
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
          remoteId: null,
          displayName: 'Empresa sem tenant',
          legalName: 'Empresa sem tenant LTDA',
          documentNumber: null,
          licensePlan: 'trial',
          licenseStatus: 'trial',
          syncEnabled: true,
        ),
        clientInstanceId: 'device-1',
      );
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

class _InitialPasswordGateway extends _NoSessionGateway {
  @override
  Future<AppSession?> restoreSession() async {
    throw const InitialPasswordChangeRequiredException(
      'Voce precisa criar uma nova senha para continuar.',
    );
  }
}
