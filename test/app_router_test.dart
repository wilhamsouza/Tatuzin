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
import 'package:erp_pdv_app/app/routes/app_router.dart';
import 'package:erp_pdv_app/app/routes/route_names.dart';
import 'package:erp_pdv_app/modules/auth/presentation/pages/login_page.dart';
import 'package:erp_pdv_app/modules/dashboard/domain/entities/operational_dashboard_snapshot.dart';
import 'package:erp_pdv_app/modules/dashboard/presentation/pages/dashboard_page.dart';
import 'package:erp_pdv_app/modules/dashboard/presentation/providers/dashboard_providers.dart';
import 'package:erp_pdv_app/modules/estoque/domain/entities/inventory_item.dart';
import 'package:erp_pdv_app/modules/estoque/presentation/providers/inventory_providers.dart';
import 'package:erp_pdv_app/modules/system/presentation/providers/system_providers.dart';
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
        router.namedLocation(AppRouteNames.subscription),
        AppRoutePaths.subscription,
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

  testWidgets('rota protegida sem sessao redireciona para login', (
    tester,
  ) async {
    await _pumpApp(tester);

    final router = GoRouter.of(tester.element(find.byType(LoginPage)));
    router.go(AppRoutePaths.sales);
    await tester.pumpAndSettle();

    expect(find.byType(LoginPage), findsOneWidget);
  });

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
    expect(find.text('Atualizar plano'), findsOneWidget);
    expect(find.textContaining('plano Pro'), findsOneWidget);
  });

  testWidgets('PRO sem employees.manage mostra sem permissão', (tester) async {
    await _pumpApp(tester, configureSession: _setProTenantSession);

    final router = GoRouter.of(tester.element(find.byType(DashboardPage)));
    router.go(AppRoutePaths.employees);
    await tester.pumpAndSettle();

    expect(find.text('Funcionários'), findsWidgets);
    expect(find.text('Sem permissão'), findsOneWidget);
    expect(find.text('Atualizar plano'), findsNothing);
  });
}

List<Override> _baseOverrides() {
  return <Override>[
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
  Future<void> signOut() async {}
}
