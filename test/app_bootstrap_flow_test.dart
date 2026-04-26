import 'dart:async';

import 'package:erp_pdv_app/app/app.dart';
import 'package:erp_pdv_app/app/core/config/app_data_mode.dart';
import 'package:erp_pdv_app/app/core/config/app_environment.dart';
import 'package:erp_pdv_app/app/core/database/app_database.dart';
import 'package:erp_pdv_app/app/core/errors/app_exceptions.dart';
import 'package:erp_pdv_app/app/core/network/contracts/auth_gateway.dart';
import 'package:erp_pdv_app/app/core/session/app_session.dart';
import 'package:erp_pdv_app/app/core/session/app_user.dart';
import 'package:erp_pdv_app/app/core/session/auth_provider.dart';
import 'package:erp_pdv_app/app/core/session/company_context.dart';
import 'package:erp_pdv_app/app/core/session/session_reset.dart';
import 'package:erp_pdv_app/modules/account/presentation/providers/account_cloud_providers.dart';
import 'package:erp_pdv_app/modules/dashboard/domain/entities/operational_dashboard_snapshot.dart';
import 'package:erp_pdv_app/modules/dashboard/presentation/pages/dashboard_page.dart';
import 'package:erp_pdv_app/modules/dashboard/presentation/providers/dashboard_providers.dart';
import 'package:erp_pdv_app/modules/system/presentation/providers/system_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  testWidgets(
    'trial login opens dashboard even when sync coordinator fails to start',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          initialAppEnvironmentProvider.overrideWith(
            (ref) => _remoteEnvironment,
          ),
          sessionContextResetProvider.overrideWith((ref) {}),
          remoteAuthGatewayProvider.overrideWith((ref) {
            return _FakeAuthGateway(signInSession: _trialSession);
          }),
          appStartupOpenDatabaseProvider.overrideWith((ref) {
            return (isolationKey) async {};
          }),
          appStartupSyncKickoffProvider.overrideWith((ref) {
            return (session) async {
              throw StateError('sync startup failed');
            };
          }),
          operationalDashboardSnapshotProvider.overrideWith((ref) async {
            return const OperationalDashboardSnapshot(
              soldTodayCents: 1500,
              currentCashCents: 3200,
              pendingFiadoCount: 0,
              pendingFiadoCents: 0,
              activeOperationalOrdersCount: 1,
              recentMovements: <OperationalDashboardRecentMovement>[],
            );
          }),
          backendConnectionStatusProvider.overrideWith((ref) async {
            return BackendConnectionStatus(
              isConfigured: true,
              isReachable: true,
              companyLookupSucceeded: true,
              endpointLabel: 'https://api.tatuzin.com.br/api',
              message: 'online',
              checkedAt: DateTime(2026, 4, 23, 10),
              remoteCompanyName: 'Cafe Oliveira',
            );
          }),
          syncHealthOverviewProvider.overrideWith((ref) {
            return const SyncHealthOverview(
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
            );
          }),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const ErpPdvApp(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextField).at(0),
        'operador@tatuzin.test',
      );
      await tester.enterText(find.byType(TextField).at(1), '12345678');
      await tester.tap(find.text('Entrar'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byType(DashboardPage), findsOneWidget);
      expect(find.text('Dashboard operacional'), findsAtLeastNWidgets(1));

      await container.read(backendConnectionStatusProvider.future);
      final cloudStatus = container.read(accountCloudStatusProvider);
      expect(cloudStatus.statusLabel, 'Precisa de atencao');
      expect(cloudStatus.cloudAvailabilityLabel, 'Auto-sync com alerta');
    },
  );

  testWidgets('slow sync kickoff still opens dashboard immediately', (
    tester,
  ) async {
    final syncStarted = Completer<void>();
    final slowKickoff = Completer<void>();
    final container = ProviderContainer(
      overrides: [
        initialAppEnvironmentProvider.overrideWith((ref) => _remoteEnvironment),
        sessionContextResetProvider.overrideWith((ref) {}),
        remoteAuthGatewayProvider.overrideWith((ref) {
          return _FakeAuthGateway(signInSession: _trialSession);
        }),
        appStartupOpenDatabaseProvider.overrideWith((ref) {
          return (isolationKey) async {};
        }),
        appStartupSyncKickoffProvider.overrideWith((ref) {
          return (session) async {
            syncStarted.complete();
            return slowKickoff.future;
          };
        }),
        operationalDashboardSnapshotProvider.overrideWith((ref) async {
          return const OperationalDashboardSnapshot(
            soldTodayCents: 1500,
            currentCashCents: 3200,
            pendingFiadoCount: 0,
            pendingFiadoCents: 0,
            activeOperationalOrdersCount: 1,
            recentMovements: <OperationalDashboardRecentMovement>[],
          );
        }),
        backendConnectionStatusProvider.overrideWith((ref) async {
          return BackendConnectionStatus(
            isConfigured: true,
            isReachable: true,
            companyLookupSucceeded: true,
            endpointLabel: 'https://api.tatuzin.com.br/api',
            message: 'online',
            checkedAt: DateTime(2026, 4, 23, 10),
            remoteCompanyName: 'Cafe Oliveira',
          );
        }),
        syncHealthOverviewProvider.overrideWith((ref) {
          return const SyncHealthOverview(
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
          );
        }),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(() {
      if (!slowKickoff.isCompleted) {
        slowKickoff.complete();
      }
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const ErpPdvApp()),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField).at(0),
      'operador@tatuzin.test',
    );
    await tester.enterText(find.byType(TextField).at(1), '12345678');
    await tester.tap(find.text('Entrar'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byType(DashboardPage), findsOneWidget);
    expect(syncStarted.isCompleted, isTrue);
    expect(slowKickoff.isCompleted, isFalse);
  });

  testWidgets('bootstrap timeout shows retry and logout instead of spinner', (
    tester,
  ) async {
    final stalledPreflight = Completer<void>();
    final container = ProviderContainer(
      overrides: [
        initialAppEnvironmentProvider.overrideWith((ref) => _remoteEnvironment),
        sessionContextResetProvider.overrideWith((ref) {}),
        remoteAuthGatewayProvider.overrideWith((ref) {
          return _FakeAuthGateway(signInSession: _trialSession);
        }),
        appStartupTimeoutProvider.overrideWith((ref) {
          return const Duration(milliseconds: 50);
        }),
        appStartupRemotePreflightProvider.overrideWith((ref) {
          return (session) {
            if (session.scope == SessionScope.localDefault) {
              return Future<void>.value();
            }
            return stalledPreflight.future;
          };
        }),
        operationalDashboardSnapshotProvider.overrideWith((ref) async {
          return const OperationalDashboardSnapshot(
            soldTodayCents: 0,
            currentCashCents: 0,
            pendingFiadoCount: 0,
            pendingFiadoCents: 0,
            activeOperationalOrdersCount: 0,
            recentMovements: <OperationalDashboardRecentMovement>[],
          );
        }),
        backendConnectionStatusProvider.overrideWith((ref) async {
          return BackendConnectionStatus(
            isConfigured: true,
            isReachable: true,
            companyLookupSucceeded: true,
            endpointLabel: 'https://api.tatuzin.com.br/api',
            message: 'online',
            checkedAt: DateTime(2026, 4, 23, 10),
            remoteCompanyName: 'Cafe Oliveira',
          );
        }),
        syncHealthOverviewProvider.overrideWith((ref) {
          return const SyncHealthOverview(
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
          );
        }),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(() {
      if (!stalledPreflight.isCompleted) {
        stalledPreflight.complete();
      }
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const ErpPdvApp()),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField).at(0),
      'operador@tatuzin.test',
    );
    await tester.enterText(find.byType(TextField).at(1), '12345678');
    await tester.tap(find.text('Entrar'));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pumpAndSettle();

    expect(
      find.text('O preparo demorou mais do que o esperado'),
      findsOneWidget,
    );
    expect(find.text('Tentar novamente'), findsOneWidget);
    expect(find.text('Sair da conta'), findsOneWidget);
    expect(
      find.textContaining('Ultima etapa concluida: tenant_key_resolved'),
      findsOneWidget,
    );
    expect(find.textContaining('Parou em: nenhuma'), findsOneWidget);
    expect(find.text('Preparando o Tatuzin'), findsNothing);

    await tester.ensureVisible(find.text('Sair da conta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sair da conta'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Acesse sua conta'), findsOneWidget);
    await tester.pump(const Duration(seconds: 8));
  });
}

AppEnvironment get _remoteEnvironment {
  return AppEnvironment.remoteDefault().copyWith(
    dataMode: AppDataMode.futureHybridReady,
    remoteSyncEnabled: true,
  );
}

AppSession get _trialSession {
  return AppSession(
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
      documentNumber: '123456789',
      licensePlan: 'trial',
      licenseStatus: 'trial',
      syncEnabled: true,
    ),
    startedAt: DateTime(2026, 4, 23, 12),
    isOfflineFallback: false,
  );
}

class _FakeAuthGateway implements AuthGateway {
  _FakeAuthGateway({this.signInSession});

  final AppSession? signInSession;

  @override
  Future<AppSession?> restoreSession() async => null;

  @override
  Future<AppSession> refreshSession() async {
    throw const AuthenticationException('no refresh session');
  }

  @override
  Future<AppSession> signIn({
    required String identifier,
    required String password,
  }) async {
    final session = signInSession;
    if (session == null) {
      throw const AuthenticationException('missing sign-in session');
    }
    return session;
  }

  @override
  Future<AppSession> signUp({
    required String companyName,
    required String companySlug,
    required String userName,
    required String email,
    required String password,
  }) async {
    throw UnimplementedError();
  }

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
