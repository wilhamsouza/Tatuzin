import 'package:erp_pdv_app/app/app.dart';
import 'package:erp_pdv_app/app/core/config/app_data_mode.dart';
import 'package:erp_pdv_app/app/core/config/app_environment.dart';
import 'package:erp_pdv_app/app/core/database/app_database.dart';
import 'package:erp_pdv_app/app/core/network/contracts/auth_gateway.dart';
import 'package:erp_pdv_app/app/core/session/app_session.dart';
import 'package:erp_pdv_app/app/core/session/app_user.dart';
import 'package:erp_pdv_app/app/core/session/auth_provider.dart';
import 'package:erp_pdv_app/app/core/session/company_context.dart';
import 'package:erp_pdv_app/app/core/session/session_provider.dart';
import 'package:erp_pdv_app/app/core/session/session_reset.dart';
import 'package:erp_pdv_app/app/core/sync/sync_queue_feature_summary.dart';
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

  testWidgets('app abre shell somente com sessao tenant valida', (
    tester,
  ) async {
    await _pumpAuthenticatedApp(tester);

    expect(find.byType(DashboardPage), findsOneWidget);
    expect(find.text('Inicio'), findsAtLeastNWidgets(1));
    expect(find.text('Nova venda'), findsAtLeastNWidgets(1));
    expect(find.text('Vendas de hoje'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.menu).first);
    await tester.pumpAndSettle();

    expect(find.byType(Drawer), findsOneWidget);

    final drawerScrollable = find.descendant(
      of: find.byType(Drawer),
      matching: find.byType(Scrollable),
    );

    await tester.scrollUntilVisible(
      find.text('Estoque do produto'),
      120,
      scrollable: drawerScrollable,
    );
    await tester.pumpAndSettle();

    expect(find.text('Estoque do produto'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Configuracoes'),
      200,
      scrollable: drawerScrollable,
    );
    await tester.pumpAndSettle();

    expect(find.text('Configuracoes'), findsOneWidget);
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

    final accountScrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('Sua empresa'),
      200,
      scrollable: accountScrollable,
    );
    await tester.pumpAndSettle();

    expect(find.text('Sua empresa'), findsOneWidget);
    expect(find.text('Conta conectada'), findsWidgets);

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
    await _pumpAuthenticatedApp(
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
      find.text('Estoque do produto'),
      120,
      scrollable: drawerScrollable,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Estoque do produto'));
    await tester.pumpAndSettle();

    expect(find.byType(Drawer), findsNothing);
    expect(find.text('Estoque atual'), findsOneWidget);
    expect(find.text('Ver movimentacoes'), findsOneWidget);
    expect(find.text('Novo ajuste'), findsOneWidget);
    expect(find.text('Inventario fisico'), findsOneWidget);
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

    await tester.tap(find.byIcon(Icons.menu).first);
    await tester.pumpAndSettle();

    final drawerScrollable = find.descendant(
      of: find.byType(Drawer),
      matching: find.byType(Scrollable),
    );

    await tester.scrollUntilVisible(
      find.text('Estoque do produto'),
      120,
      scrollable: drawerScrollable,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Estoque do produto'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Inventario fisico'));
    await tester.pumpAndSettle();

    expect(find.byType(Drawer), findsNothing);
    expect(find.text('Nova sessao'), findsAtLeastNWidgets(1));
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
          licensePlan: 'trial',
          licenseStatus: 'trial',
          syncEnabled: true,
        ),
        clientInstanceId: 'device-1',
      );

  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const ErpPdvApp()),
  );

  await tester.pumpAndSettle();

  expect(find.text('Continuar offline'), findsNothing);
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
