import 'package:erp_pdv_app/app/core/session/app_session.dart';
import 'package:erp_pdv_app/app/core/session/app_user.dart';
import 'package:erp_pdv_app/app/core/session/company_context.dart';
import 'package:erp_pdv_app/app/core/session/session_provider.dart';
import 'package:erp_pdv_app/modules/account/presentation/providers/account_cloud_providers.dart';
import 'package:erp_pdv_app/modules/system/presentation/providers/system_providers.dart';
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
          );

      await container.read(backendConnectionStatusProvider.future);
      final snapshot = container.read(accountCloudStatusProvider);

      expect(snapshot.statusLabel, 'Pendencias para sincronizar');
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
          );

      await container.read(backendConnectionStatusProvider.future);
      final snapshot = container.read(accountCloudStatusProvider);

      expect(snapshot.statusLabel, 'Precisa de atencao');
      expect(snapshot.errorCount, 1);
      expect(snapshot.blockedCount, 2);
      expect(snapshot.conflictCount, 1);
    },
  );
}
