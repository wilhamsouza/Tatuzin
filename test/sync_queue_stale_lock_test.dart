import 'package:erp_pdv_app/app/core/database/app_database.dart';
import 'package:erp_pdv_app/app/core/database/table_names.dart';
import 'package:erp_pdv_app/app/core/session/app_session.dart';
import 'package:erp_pdv_app/app/core/session/app_user.dart';
import 'package:erp_pdv_app/app/core/session/company_context.dart';
import 'package:erp_pdv_app/app/core/session/session_provider.dart';
import 'package:erp_pdv_app/app/core/sync/sqlite_sync_audit_repository.dart';
import 'package:erp_pdv_app/app/core/sync/sqlite_sync_queue_repository.dart';
import 'package:erp_pdv_app/app/core/sync/sync_audit_event_type.dart';
import 'package:erp_pdv_app/app/core/sync/sync_feature_keys.dart';
import 'package:erp_pdv_app/app/core/sync/sync_providers.dart';
import 'package:erp_pdv_app/app/core/sync/sync_queue_operation.dart';
import 'package:erp_pdv_app/app/core/sync/sync_queue_status.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'recupera processing stale como pendencia reprocessavel e registra auditoria',
    () async {
      final session = _remoteSession();
      final isolationKey = SessionIsolation.keyFor(session);
      await AppDatabase.deleteDatabaseForIsolationKeyForTesting(isolationKey);

      final container = ProviderContainer();
      addTearDown(() async {
        container.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await AppDatabase.deleteDatabaseForIsolationKeyForTesting(isolationKey);
      });

      container
          .read(appSessionProvider.notifier)
          .setAuthenticatedSession(
            scope: session.scope,
            user: session.user,
            company: session.company,
            isOfflineFallback: session.isOfflineFallback,
          );
      await container.read(appStartupProvider.future);

      final repository = container.read(syncQueueRepositoryProvider);
      final database = await container.read(appDatabaseProvider).database;
      final now = DateTime.now();
      await database.transaction((txn) async {
        await repository.enqueueMutation(
          txn,
          featureKey: SyncFeatureKeys.products,
          entityType: 'product',
          localEntityId: 1,
          localUuid: 'prod-1',
          remoteId: null,
          operation: SyncQueueOperation.create,
          localUpdatedAt: now,
        );
      });

      final queueRows = await database.query(TableNames.syncQueue, limit: 1);
      final queueId = queueRows.first['id'] as int;
      final staleLockedAt = now.subtract(
        SqliteSyncQueueRepository.staleLockThreshold +
            const Duration(seconds: 5),
      );
      await database.update(
        TableNames.syncQueue,
        {
          'status': SyncQueueStatus.processing.storageValue,
          'locked_at': staleLockedAt.toIso8601String(),
          'updated_at': staleLockedAt.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [queueId],
      );

      final beforeRecovery = await repository.listFeatureSummaries();
      expect(beforeRecovery.single.activeProcessingCount, 0);
      expect(beforeRecovery.single.staleProcessingCount, 1);
      expect(beforeRecovery.single.pendingForDisplay, 1);

      final recoveredCount = await repository.recoverStaleProcessingLocks(
        now: now,
      );
      expect(recoveredCount, 1);

      final afterRecovery = await database.query(
        TableNames.syncQueue,
        where: 'id = ?',
        whereArgs: [queueId],
        limit: 1,
      );
      expect(
        afterRecovery.single['status'],
        SyncQueueStatus.pendingUpload.storageValue,
      );
      expect(afterRecovery.single['locked_at'], isNull);

      final eligibleItems = await repository.listEligibleItems(
        retryOnly: false,
        now: now,
      );
      expect(eligibleItems, hasLength(1));
      expect(eligibleItems.single.status, SyncQueueStatus.pendingUpload);

      final auditLogs = await SqliteSyncAuditRepository(
        container.read(appDatabaseProvider),
      ).listRecent(limit: 10);
      expect(
        auditLogs.any(
          (log) => log.eventType == SyncAuditEventType.staleBlockCleared,
        ),
        isTrue,
      );
    },
  );

  test(
    'respeita backoff automatico e permite sincronizacao manual forcar retry',
    () async {
      final session = _remoteSession();
      final isolationKey = SessionIsolation.keyFor(session);
      await AppDatabase.deleteDatabaseForIsolationKeyForTesting(isolationKey);

      final container = ProviderContainer();
      addTearDown(() async {
        container.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await AppDatabase.deleteDatabaseForIsolationKeyForTesting(isolationKey);
      });

      container
          .read(appSessionProvider.notifier)
          .setAuthenticatedSession(
            scope: session.scope,
            user: session.user,
            company: session.company,
            isOfflineFallback: session.isOfflineFallback,
          );
      await container.read(appStartupProvider.future);

      final repository = container.read(syncQueueRepositoryProvider);
      final database = await container.read(appDatabaseProvider).database;
      final now = DateTime.now();
      await database.transaction((txn) async {
        await repository.enqueueMutation(
          txn,
          featureKey: SyncFeatureKeys.products,
          entityType: 'product',
          localEntityId: 1,
          localUuid: 'prod-backoff',
          remoteId: null,
          operation: SyncQueueOperation.create,
          localUpdatedAt: now,
        );
      });

      final queueRows = await database.query(TableNames.syncQueue, limit: 1);
      final queueId = queueRows.first['id'] as int;
      final nextRetryAt = now.add(const Duration(minutes: 10));
      await database.update(
        TableNames.syncQueue,
        {
          'status': SyncQueueStatus.syncError.storageValue,
          'next_retry_at': nextRetryAt.toIso8601String(),
          'last_error': 'Falha temporaria',
          'updated_at': now.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [queueId],
      );

      final automaticEligible = await repository.listEligibleItems(
        retryOnly: false,
        now: now,
      );
      expect(automaticEligible, isEmpty);

      final forcedEligible = await repository.listEligibleItems(
        retryOnly: false,
        ignoreRetryBackoff: true,
        now: now,
      );
      expect(forcedEligible, hasLength(1));
      expect(forcedEligible.single.id, queueId);
    },
  );
}

AppSession _remoteSession() {
  final suffix = DateTime.now().microsecondsSinceEpoch;
  return AppSession(
    scope: SessionScope.authenticatedRemote,
    user: AppUser(
      localId: null,
      remoteId: 'usr_stale_$suffix',
      displayName: 'Operador Sync',
      email: 'sync_$suffix@tatuzin.test',
      roleLabel: 'Operador',
      kind: AppUserKind.remoteAuthenticated,
    ),
    company: CompanyContext(
      localId: null,
      remoteId: 'cmp_stale_$suffix',
      displayName: 'Empresa Sync',
      legalName: 'Empresa Sync LTDA',
      documentNumber: null,
      licensePlan: 'pro',
      licenseStatus: 'active',
      syncEnabled: true,
    ),
    startedAt: DateTime.now(),
    isOfflineFallback: false,
  );
}
