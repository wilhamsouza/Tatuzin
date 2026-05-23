import 'package:tatuzin/app/core/session/app_session.dart';
import 'package:tatuzin/app/core/sync/sync_queue_feature_summary.dart';
import 'package:tatuzin/app/core/session/app_user.dart';
import 'package:tatuzin/app/core/session/company_context.dart';
import 'package:tatuzin/app/core/session/session_provider.dart';
import 'package:tatuzin/modules/account/presentation/providers/account_cloud_providers.dart';
import 'package:tatuzin/modules/system/presentation/providers/system_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'shows pending state when queue has only pending or stale processing',
    () async {
      final container = ProviderContainer(
        overrides: [
          backendConnectionStatusProvider.overrideWith(
            (ref) async => BackendConnectionStatus(
              isConfigured: true,
              isReachable: true,
              companyLookupSucceeded: true,
              endpointLabel: 'API',
              message: 'online',
              checkedAt: DateTime(2026, 4, 21, 9),
              remoteCompanyName: 'Tatuzin',
            ),
          ),
          syncHealthOverviewProvider.overrideWith(
            (ref) => const SyncHealthOverview(
              totalPending: 2,
              totalProcessing: 1,
              totalActiveProcessing: 0,
              totalStaleProcessing: 1,
              totalSynced: 4,
              totalErrors: 0,
              totalBlocked: 0,
              totalConflicts: 0,
              totalAttempts: 7,
              lastProcessedAt: null,
              lastErrorAt: null,
              nextRetryAt: null,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      container
          .read(appSessionProvider.notifier)
          .setAuthenticatedSession(
            scope: SessionScope.authenticatedRemote,
            user: const AppUser(
              localId: 1,
              remoteId: 'user-1',
              displayName: 'Operador',
              email: 'operador@tatuzin.app',
              roleLabel: 'Operador',
              kind: AppUserKind.remoteAuthenticated,
            ),
            company: const CompanyContext(
              localId: 1,
              remoteId: 'company-1',
              displayName: 'Tatuzin',
              legalName: 'Tatuzin LTDA',
              documentNumber: '123',
              licensePlan: 'pro',
              licenseStatus: 'active',
              syncEnabled: true,
            ),
            isOfflineFallback: false,
            clientInstanceId: 'device-1',
          );

      await container.read(backendConnectionStatusProvider.future);
      final snapshot = container.read(accountCloudStatusProvider);

      expect(snapshot.statusLabel, 'Pendente');
      expect(snapshot.pendingCount, 3);
      expect(snapshot.syncingNowCount, 0);
    },
  );

  test('shows syncing state only when processing is active now', () async {
    final container = ProviderContainer(
      overrides: [
        backendConnectionStatusProvider.overrideWith(
          (ref) async => BackendConnectionStatus(
            isConfigured: true,
            isReachable: true,
            companyLookupSucceeded: true,
            endpointLabel: 'API',
            message: 'online',
            checkedAt: DateTime(2026, 4, 21, 9),
          ),
        ),
        syncHealthOverviewProvider.overrideWith(
          (ref) => const SyncHealthOverview(
            totalPending: 1,
            totalProcessing: 2,
            totalActiveProcessing: 2,
            totalStaleProcessing: 0,
            totalSynced: 3,
            totalErrors: 0,
            totalBlocked: 0,
            totalConflicts: 0,
            totalAttempts: 5,
            lastProcessedAt: null,
            lastErrorAt: null,
            nextRetryAt: null,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    container
        .read(appSessionProvider.notifier)
        .setAuthenticatedSession(
          scope: SessionScope.authenticatedRemote,
          user: const AppUser(
            localId: 1,
            remoteId: 'user-1',
            displayName: 'Operador',
            email: 'operador@tatuzin.app',
            roleLabel: 'Operador',
            kind: AppUserKind.remoteAuthenticated,
          ),
          company: const CompanyContext(
            localId: 1,
            remoteId: 'company-1',
            displayName: 'Tatuzin',
            legalName: 'Tatuzin LTDA',
            documentNumber: '123',
            licensePlan: 'pro',
            licenseStatus: 'active',
            syncEnabled: true,
          ),
          isOfflineFallback: false,
          clientInstanceId: 'device-1',
        );

    await container.read(backendConnectionStatusProvider.future);
    final snapshot = container.read(accountCloudStatusProvider);

    expect(snapshot.statusLabel, 'Sincronizando');
    expect(snapshot.syncingNowCount, 2);
  });

  test(
    'shows attention state when queue has errors, blocked items or conflicts',
    () async {
      final container = ProviderContainer(
        overrides: [
          backendConnectionStatusProvider.overrideWith(
            (ref) async => BackendConnectionStatus(
              isConfigured: true,
              isReachable: true,
              companyLookupSucceeded: true,
              endpointLabel: 'API',
              message: 'online',
              checkedAt: DateTime(2026, 4, 21, 9),
            ),
          ),
          syncHealthOverviewProvider.overrideWith(
            (ref) => SyncHealthOverview(
              totalPending: 0,
              totalProcessing: 0,
              totalActiveProcessing: 0,
              totalStaleProcessing: 0,
              totalSynced: 2,
              totalErrors: 1,
              totalBlocked: 2,
              totalConflicts: 1,
              totalAttempts: 8,
              lastProcessedAt: null,
              lastErrorAt: DateTime(2026, 4, 21, 8, 30),
              nextRetryAt: DateTime(2026, 4, 21, 9, 30),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      container
          .read(appSessionProvider.notifier)
          .setAuthenticatedSession(
            scope: SessionScope.authenticatedRemote,
            user: const AppUser(
              localId: 1,
              remoteId: 'user-1',
              displayName: 'Operador',
              email: 'operador@tatuzin.app',
              roleLabel: 'Operador',
              kind: AppUserKind.remoteAuthenticated,
            ),
            company: const CompanyContext(
              localId: 1,
              remoteId: 'company-1',
              displayName: 'Tatuzin',
              legalName: 'Tatuzin LTDA',
              documentNumber: '123',
              licensePlan: 'pro',
              licenseStatus: 'active',
              syncEnabled: true,
            ),
            isOfflineFallback: false,
            clientInstanceId: 'device-1',
          );

      await container.read(backendConnectionStatusProvider.future);
      final snapshot = container.read(accountCloudStatusProvider);

      expect(snapshot.statusLabel, 'Com conflito');
      expect(snapshot.errorCount, 1);
      expect(snapshot.blockedCount, 2);
      expect(snapshot.conflictCount, 1);
    },
  );

  test('destaca o modulo quando ha uma unica falha operacional', () async {
    final container = ProviderContainer(
      overrides: [
        backendConnectionStatusProvider.overrideWith(
          (ref) async => BackendConnectionStatus(
            isConfigured: true,
            isReachable: true,
            companyLookupSucceeded: true,
            endpointLabel: 'API',
            message: 'online',
            checkedAt: DateTime(2026, 4, 21, 9),
          ),
        ),
        syncHealthOverviewProvider.overrideWith(
          (ref) => SyncHealthOverview(
            totalPending: 0,
            totalProcessing: 0,
            totalActiveProcessing: 0,
            totalStaleProcessing: 0,
            totalSynced: 2,
            totalErrors: 1,
            totalBlocked: 0,
            totalConflicts: 0,
            totalAttempts: 3,
            lastProcessedAt: DateTime(2026, 4, 21, 8, 20),
            lastErrorAt: DateTime(2026, 4, 21, 8, 30),
            nextRetryAt: DateTime(2026, 4, 21, 9, 30),
          ),
        ),
        syncQueueFeatureSummariesProvider.overrideWith((ref) async {
          return [
            SyncQueueFeatureSummary(
              featureKey: 'sales',
              displayName: 'Vendas',
              totalTracked: 1,
              pendingCount: 0,
              processingCount: 0,
              activeProcessingCount: 0,
              staleProcessingCount: 0,
              syncedCount: 0,
              errorCount: 1,
              blockedCount: 0,
              conflictCount: 0,
              totalAttemptCount: 3,
              lastProcessedAt: DateTime(2026, 4, 21, 8, 20),
              nextRetryAt: DateTime(2026, 4, 21, 9, 30),
              lastError: 'Falha inesperada ao materializar evento operacional.',
              lastErrorType: null,
              lastErrorAt: DateTime(2026, 4, 21, 8, 30),
            ),
          ];
        }),
      ],
    );
    addTearDown(container.dispose);

    container
        .read(appSessionProvider.notifier)
        .setAuthenticatedSession(
          scope: SessionScope.authenticatedRemote,
          user: const AppUser(
            localId: 1,
            remoteId: 'user-1',
            displayName: 'Operador',
            email: 'operador@tatuzin.app',
            roleLabel: 'Operador',
            kind: AppUserKind.remoteAuthenticated,
          ),
          company: const CompanyContext(
            localId: 1,
            remoteId: 'company-1',
            displayName: 'Tatuzin',
            legalName: 'Tatuzin LTDA',
            documentNumber: '123',
            licensePlan: 'pro',
            licenseStatus: 'active',
            syncEnabled: true,
          ),
          isOfflineFallback: false,
          clientInstanceId: 'device-1',
        );

    await container.read(backendConnectionStatusProvider.future);
    await container.read(syncQueueFeatureSummariesProvider.future);
    final snapshot = container.read(accountCloudStatusProvider);

    expect(snapshot.statusLabel, 'Erro de sincronizacao');
    expect(
      snapshot.statusMessage,
      contains('Ha 1 venda com falha de sincronizacao'),
    );
    expect(snapshot.statusMessage, contains('Ultimo erro em Vendas'));
  });

  test(
    'shows server data stale when push ok but pull or snapshot failed',
    () async {
      final container = ProviderContainer(
        overrides: [
          backendConnectionStatusProvider.overrideWith(
            (ref) async => BackendConnectionStatus(
              isConfigured: true,
              isReachable: true,
              companyLookupSucceeded: true,
              endpointLabel: 'API',
              message: 'online',
              checkedAt: DateTime(2026, 4, 21, 9),
            ),
          ),
          syncHealthOverviewProvider.overrideWith(
            (ref) => const SyncHealthOverview(
              totalPending: 0,
              totalProcessing: 0,
              totalActiveProcessing: 0,
              totalStaleProcessing: 0,
              totalSynced: 2,
              totalErrors: 0,
              totalBlocked: 0,
              totalConflicts: 0,
              totalAttempts: 2,
              lastProcessedAt: null,
              lastErrorAt: null,
              nextRetryAt: null,
              hasServerDataStale: true,
              lastSnapshotError: 'snapshot offline',
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      container
          .read(appSessionProvider.notifier)
          .setAuthenticatedSession(
            scope: SessionScope.authenticatedRemote,
            user: const AppUser(
              localId: 1,
              remoteId: 'user-1',
              displayName: 'Operador',
              email: 'operador@tatuzin.app',
              roleLabel: 'Operador',
              kind: AppUserKind.remoteAuthenticated,
            ),
            company: const CompanyContext(
              localId: 1,
              remoteId: 'company-1',
              displayName: 'Tatuzin',
              legalName: 'Tatuzin LTDA',
              documentNumber: '123',
              licensePlan: 'pro',
              licenseStatus: 'active',
              syncEnabled: true,
            ),
            isOfflineFallback: false,
            clientInstanceId: 'device-1',
          );

      await container.read(backendConnectionStatusProvider.future);
      final snapshot = container.read(accountCloudStatusProvider);

      expect(snapshot.statusLabel, 'Dados do servidor desatualizados');
      expect(snapshot.supportingValue, 'snapshot offline');
    },
  );

  test('does not show next retry before last processed sync', () async {
    final container = ProviderContainer(
      overrides: [
        backendConnectionStatusProvider.overrideWith(
          (ref) async => BackendConnectionStatus(
            isConfigured: true,
            isReachable: true,
            companyLookupSucceeded: true,
            endpointLabel: 'API',
            message: 'online',
            checkedAt: DateTime(2026, 4, 26, 7, 45),
          ),
        ),
        syncHealthOverviewProvider.overrideWith(
          (ref) => SyncHealthOverview(
            totalPending: 0,
            totalProcessing: 0,
            totalActiveProcessing: 0,
            totalStaleProcessing: 0,
            totalSynced: 2,
            totalErrors: 3,
            totalBlocked: 0,
            totalConflicts: 0,
            totalAttempts: 8,
            lastProcessedAt: DateTime(2026, 4, 26, 7, 43),
            lastErrorAt: DateTime(2026, 4, 26, 7, 42),
            nextRetryAt: DateTime(2026, 4, 24, 13, 44),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    container
        .read(appSessionProvider.notifier)
        .setAuthenticatedSession(
          scope: SessionScope.authenticatedRemote,
          user: const AppUser(
            localId: 1,
            remoteId: 'user-1',
            displayName: 'Operador',
            email: 'operador@tatuzin.app',
            roleLabel: 'Operador',
            kind: AppUserKind.remoteAuthenticated,
          ),
          company: const CompanyContext(
            localId: 1,
            remoteId: 'company-1',
            displayName: 'Tatuzin',
            legalName: 'Tatuzin LTDA',
            documentNumber: '123',
            licensePlan: 'pro',
            licenseStatus: 'active',
            syncEnabled: true,
          ),
          isOfflineFallback: false,
          clientInstanceId: 'device-1',
        );

    await container.read(backendConnectionStatusProvider.future);
    final snapshot = container.read(accountCloudStatusProvider);

    expect(snapshot.nextRetryAt, DateTime(2026, 4, 26, 7, 44));
  });
}
