import 'package:erp_pdv_app/app/core/database/app_database.dart';
import 'package:erp_pdv_app/app/core/database/table_names.dart';
import 'package:erp_pdv_app/app/core/session/app_session.dart';
import 'package:erp_pdv_app/app/core/session/app_user.dart';
import 'package:erp_pdv_app/app/core/session/company_context.dart';
import 'package:erp_pdv_app/app/core/session/session_provider.dart';
import 'package:erp_pdv_app/app/core/session/session_reset.dart';
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
    'logout com pendencias preserva fila e permite relogin no mesmo tenant',
    () async {
      final suffix = DateTime.now().microsecondsSinceEpoch;
      final session = _remoteSession(companyId: 'cmp_logout_$suffix');
      final isolationKey = SessionIsolation.keyFor(session);
      await AppDatabase.deleteDatabaseForIsolationKeyForTesting(isolationKey);

      final container = ProviderContainer();
      container.read(sessionContextResetProvider);
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
      expect(
        (await container.read(appStartupProvider.future)).isSuccess,
        isTrue,
      );

      await _insertPendingSyncItems(container, 33);
      final before = await container
          .read(syncQueueRepositoryProvider)
          .listFeatureSummaries();
      expect(
        before.fold<int>(0, (total, item) => total + item.pendingForDisplay),
        33,
      );

      final resetSnapshot = await container.read(sessionSignOutResetProvider)(
        session,
      );
      expect(resetSnapshot.pendingSyncCount, 33);
      expect(resetSnapshot.databaseClosed, isFalse);

      container.read(appSessionProvider.notifier).signOutToLocalMode();
      expect(
        (await container.read(appStartupProvider.future)).isSuccess,
        isTrue,
      );
      final closedSnapshot = await closeSessionDatabaseForReset(resetSnapshot);
      expect(closedSnapshot.databaseClosed, isTrue);

      container
          .read(appSessionProvider.notifier)
          .setAuthenticatedSession(
            scope: session.scope,
            user: session.user,
            company: session.company,
            isOfflineFallback: session.isOfflineFallback,
          );
      expect(
        (await container.read(appStartupProvider.future)).isSuccess,
        isTrue,
      );

      final after = await container
          .read(syncQueueRepositoryProvider)
          .listFeatureSummaries();
      expect(
        after.fold<int>(0, (total, item) => total + item.pendingForDisplay),
        33,
      );
    },
  );
}

Future<void> _insertPendingSyncItems(
  ProviderContainer container,
  int count,
) async {
  final database = await container.read(appDatabaseProvider).database;
  final now = DateTime.now();
  await database.transaction((txn) async {
    for (var index = 0; index < count; index++) {
      await txn.insert(TableNames.syncQueue, {
        'feature_key': 'sales',
        'entity_type': 'sale',
        'local_entity_id': index + 1,
        'local_uuid': 'sale-$index',
        'remote_id': null,
        'operation_type': SyncQueueOperation.create.storageValue,
        'status': SyncQueueStatus.pendingUpload.storageValue,
        'attempt_count': 0,
        'next_retry_at': null,
        'last_error': null,
        'last_error_type': null,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
        'locked_at': null,
        'last_processed_at': null,
        'correlation_key': 'sales:sale:${index + 1}',
        'local_updated_at': now.toIso8601String(),
        'remote_updated_at': null,
        'conflict_reason': null,
      });
    }
  });
}

AppSession _remoteSession({required String companyId}) {
  return AppSession(
    scope: SessionScope.authenticatedRemote,
    user: AppUser(
      localId: null,
      remoteId: 'usr_$companyId',
      displayName: 'Operador',
      email: 'operador_$companyId@tatuzin.test',
      roleLabel: 'Operador',
      kind: AppUserKind.remoteAuthenticated,
    ),
    company: CompanyContext(
      localId: null,
      remoteId: companyId,
      displayName: 'Empresa Logout',
      legalName: 'Empresa Logout LTDA',
      documentNumber: null,
      licensePlan: 'pro',
      licenseStatus: 'active',
      syncEnabled: true,
    ),
    startedAt: DateTime.now(),
    isOfflineFallback: false,
  );
}
