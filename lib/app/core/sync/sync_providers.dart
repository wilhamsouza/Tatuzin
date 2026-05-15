import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_context/app_operational_context.dart';
import '../app_context/data_access_policy.dart';
import '../config/app_environment.dart';
import '../providers/app_data_refresh_provider.dart';
import '../session/session_provider.dart';
import '../../../modules/categorias/presentation/providers/category_providers.dart';
import '../../../modules/caixa/presentation/providers/cash_providers.dart';
import '../../../modules/clientes/presentation/providers/client_providers.dart';
import '../../../modules/compras/presentation/providers/purchase_providers.dart';
import '../../../modules/fiado/presentation/providers/fiado_providers.dart';
import '../../../modules/fornecedores/presentation/providers/supplier_providers.dart';
import '../../../modules/insumos/presentation/providers/supply_providers.dart';
import '../../../modules/produtos/presentation/providers/product_providers.dart';
import '../../../modules/vendas/presentation/providers/sales_providers.dart';
import '../database/app_database.dart';
import '../network/network_providers.dart';
import '../session/auth_token_storage.dart';
import '../utils/app_logger.dart';
import 'app_snapshot_hydrator.dart';
import 'app_snapshot_remote_datasource.dart';
import 'financial_event_sync_processor.dart';
import 'financial_events_remote_datasource.dart';
import 'operational_sync_queue_repository.dart';
import 'operational_sync_projection_applier.dart';
import 'operational_sync_remote_datasource.dart';
import 'operational_sync_runner.dart';
import 'real_app_snapshot_remote_datasource.dart';
import 'real_financial_events_remote_datasource.dart';
import 'real_operational_sync_remote_datasource.dart';
import 'auto_sync_coordinator.dart';
import 'sqlite_operational_sync_queue_repository.dart';
import 'sqlite_sync_queue_repository.dart';
import 'sync_dependency_resolver.dart';
import 'sync_feature_processor.dart';
import 'sync_batch_result.dart';
import 'sync_queue_engine.dart';
import 'sync_queue_feature_summary.dart';
import 'sync_queue_repository.dart';
import 'sync_retry_policy.dart';

final syncQueueRepositoryProvider = Provider<SyncQueueRepository>((ref) {
  return SqliteSyncQueueRepository(ref.watch(appDatabaseProvider));
});

final operationalSyncQueueRepositoryProvider =
    Provider<OperationalSyncQueueRepository>((ref) {
      return SqliteOperationalSyncQueueRepository(
        ref.watch(appDatabaseProvider),
      );
    });

final operationalSyncRemoteDataSourceProvider =
    Provider<OperationalSyncRemoteDataSource>((ref) {
      return RealOperationalSyncRemoteDataSource(
        apiClient: ref.watch(realApiClientProvider),
        tokenStorage: ref.watch(authTokenStorageProvider),
      );
    });

final operationalSyncProjectionApplierProvider =
    Provider<OperationalSyncProjectionApplier>((ref) {
      final session = ref.watch(appSessionProvider);
      return SqliteOperationalSyncProjectionApplier(
        appDatabase: ref.watch(appDatabaseProvider),
        companyRemoteId: session.company.remoteId,
      );
    });

final appSnapshotRemoteDataSourceProvider =
    Provider<AppSnapshotRemoteDataSource>((ref) {
      return RealAppSnapshotRemoteDataSource(
        apiClient: ref.watch(realApiClientProvider),
        tokenStorage: ref.watch(authTokenStorageProvider),
      );
    });

final appSnapshotHydratorProvider = Provider<AppSnapshotHydrator>((ref) {
  return SqliteAppSnapshotHydrator(
    categoryRepository: ref.watch(localCategoryRepositoryProvider),
    supplierRepository: ref.watch(localSupplierRepositoryProvider),
    clientRepository: ref.watch(localClientRepositoryProvider),
    productRepository: ref.watch(localProductRepositoryProvider),
    cashRepository: ref.watch(localCashRepositoryProvider),
  );
});

final syncRetryPolicyProvider = Provider<SyncRetryPolicy>((ref) {
  return const SyncRetryPolicy();
});

final financialEventsRemoteDatasourceProvider =
    Provider<FinancialEventsRemoteDatasource>((ref) {
      return RealFinancialEventsRemoteDatasource(
        apiClient: ref.read(realApiClientProvider),
        tokenStorage: ref.read(authTokenStorageProvider),
        environment: ref.watch(appEnvironmentProvider),
        operationalContext: ref.watch(appOperationalContextProvider),
      );
    });

final financialEventSyncProcessorProvider =
    Provider<FinancialEventSyncProcessor>((ref) {
      return FinancialEventSyncProcessor(
        saleRepository: ref.watch(localSaleRepositoryProvider),
        fiadoRepository: ref.watch(localFiadoRepositoryProvider),
        salesRemoteDatasource: ref.watch(salesRemoteDatasourceProvider),
        financialEventsRemoteDatasource: ref.watch(
          financialEventsRemoteDatasourceProvider,
        ),
        operationalContext: ref.watch(appOperationalContextProvider),
        dataAccessPolicy: ref.watch(appDataAccessPolicyProvider),
      );
    });

final syncDependencyResolverProvider = Provider<SyncDependencyResolver>((ref) {
  return SyncDependencyResolver(
    categoryRepository: ref.watch(localCategoryRepositoryProvider),
    productRepository: ref.watch(localProductRepositoryProvider),
    supplierRepository: ref.watch(localSupplierRepositoryProvider),
    supplyRepository: ref.watch(localSupplyRepositoryProvider),
    purchaseRepository: ref.watch(localPurchaseRepositoryProvider),
    saleRepository: ref.watch(localSaleRepositoryProvider),
    fiadoRepository: ref.watch(localFiadoRepositoryProvider),
    cashRepository: ref.watch(localCashRepositoryProvider),
  );
});

final syncFeatureProcessorsProvider = Provider<List<SyncFeatureProcessor>>((_) {
  return const <SyncFeatureProcessor>[];
});

final syncQueueEngineProvider = Provider<SyncQueueEngine>((ref) {
  final sessionRuntimeKey = ref.watch(sessionRuntimeKeyProvider);
  var isDisposed = false;
  ref.onDispose(() {
    isDisposed = true;
  });

  return SyncQueueEngine(
    queueRepository: ref.watch(syncQueueRepositoryProvider),
    processors: ref.watch(syncFeatureProcessorsProvider),
    retryPolicy: ref.watch(syncRetryPolicyProvider),
    dependencyResolver: ref.watch(syncDependencyResolverProvider),
    shouldContinue: () {
      return !isDisposed &&
          ref.read(sessionRuntimeKeyProvider) == sessionRuntimeKey;
    },
  );
});

final syncBatchActivityProvider = StateProvider<bool>((ref) => false);

final operationalSyncRunnerProvider = Provider<OperationalSyncRunner>((ref) {
  final sessionRuntimeKey = ref.watch(sessionRuntimeKeyProvider);
  var isDisposed = false;
  ref.onDispose(() {
    isDisposed = true;
  });

  return OperationalSyncRunner(
    queueRepository: ref.watch(operationalSyncQueueRepositoryProvider),
    remoteDataSource: ref.watch(operationalSyncRemoteDataSourceProvider),
    projectionApplier: ref.watch(operationalSyncProjectionApplierProvider),
    snapshotHydrator: ref.watch(appSnapshotHydratorProvider),
    snapshotRemoteDataSource: ref.watch(appSnapshotRemoteDataSourceProvider),
    shouldContinue: () {
      return !isDisposed &&
          ref.read(sessionRuntimeKeyProvider) == sessionRuntimeKey;
    },
    onCacheSnapshotChanged: () {
      ref.read(appDataRefreshProvider.notifier).state++;
    },
  );
});

final syncBatchRunnerProvider = Provider<SyncBatchRunner>((ref) {
  final runner = SyncBatchRunner(
    ref,
    sessionRuntimeKey: ref.watch(sessionRuntimeKeyProvider),
  );
  ref.onDispose(runner.dispose);
  return runner;
});

final autoSyncSnapshotProvider = StateProvider<AutoSyncCoordinatorSnapshot>((
  ref,
) {
  ref.watch(sessionRuntimeKeyProvider);
  return const AutoSyncCoordinatorSnapshot.idle();
});

final autoSyncCoordinatorProvider = Provider<AutoSyncCoordinator>((ref) {
  final coordinator = AutoSyncCoordinator(
    isEligible: () {
      final environment = ref.read(appEnvironmentProvider);
      final session = ref.read(appSessionProvider);
      final company = ref.read(currentCompanyContextProvider);
      final startupState = ref.read(appStartupProvider).valueOrNull;
      return environment.remoteSyncEnabled &&
          environment.endpointConfig.isConfigured &&
          session.canStartSync &&
          company.allowsCloudSync &&
          startupState?.isSuccess == true;
    },
    isRunning: () => ref.read(syncBatchActivityProvider),
    runSync: () => ref
        .read(syncBatchRunnerProvider)
        .run(retryOnly: false, ignoreRetryBackoff: false),
    loadQueueSummaries: () async {
      final startupState = await ref.read(appStartupProvider.future);
      if (!startupState.isSuccess) {
        AppLogger.info(
          '[Sync] auto_sync_skipped reason=tenant_bootstrap_not_ready:queue_summary',
        );
        return const <SyncQueueFeatureSummary>[];
      }
      return ref
          .read(operationalSyncQueueRepositoryProvider)
          .listFeatureSummaries();
    },
    onSnapshot: (snapshot) {
      ref.read(autoSyncSnapshotProvider.notifier).state = snapshot;
    },
  );
  ref.onDispose(() {
    coordinator.dispose();
  });
  return coordinator;
});

class SyncBatchRunner {
  SyncBatchRunner(this._ref, {required String sessionRuntimeKey})
    : _sessionRuntimeKey = sessionRuntimeKey;

  final Ref _ref;
  final String _sessionRuntimeKey;
  Future<SyncBatchResult>? _inFlight;
  bool _disposed = false;

  bool get isRunning => _inFlight != null;

  void dispose() {
    _disposed = true;
  }

  Future<void> stopForSessionReset({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    _disposed = true;
    final running = _inFlight;
    if (running != null) {
      try {
        await running.timeout(timeout);
      } catch (_) {
        // A long network call may still settle later, but shouldContinue()
        // already returns false and prevents the batch from advancing.
      }
    }
  }

  Future<SyncBatchResult> run({
    required bool retryOnly,
    bool ignoreRetryBackoff = false,
    Iterable<String>? featureKeys,
  }) {
    final running = _inFlight;
    if (running != null) {
      return running;
    }

    late final Future<SyncBatchResult> future;
    future = _execute(
      retryOnly: retryOnly,
      ignoreRetryBackoff: ignoreRetryBackoff,
      featureKeys: featureKeys,
    );
    _inFlight = future;

    return future.whenComplete(() {
      if (!_disposed && identical(_inFlight, future)) {
        _inFlight = null;
        _ref.read(syncBatchActivityProvider.notifier).state = false;
      }
    });
  }

  Future<SyncBatchResult> _execute({
    required bool retryOnly,
    required bool ignoreRetryBackoff,
    Iterable<String>? featureKeys,
  }) async {
    if (!_isCurrentSession()) {
      return _cancelledResult(retryOnly: retryOnly);
    }

    final startupState = await _ref.read(appStartupProvider.future);
    if (!startupState.isSuccess) {
      AppLogger.info(
        '[Sync] batch_runner_skipped reason=tenant_bootstrap_not_ready | '
        'status=${startupState.status.name}',
      );
      return _cancelledResult(retryOnly: retryOnly);
    }

    final session = _ref.read(appSessionProvider);
    if (!session.canStartSync) {
      AppLogger.info(
        '[Sync] batch_runner_skipped reason=missing_sync_identity | '
        'companyId=${session.company.remoteId ?? 'n/a'} | '
        'userId=${session.user.remoteId ?? 'n/a'} | '
        'clientInstanceId=${session.clientInstanceId ?? 'n/a'} | '
        'tenantReady=${session.hasOperationalIdentity}',
      );
      return _cancelledResult(retryOnly: retryOnly);
    }

    _ref.read(syncBatchActivityProvider.notifier).state = true;
    try {
      AppLogger.info(
        retryOnly
            ? '[Sync] batch_runner_started scope=retry_pending'
            : '[Sync] batch_runner_started scope=all',
      );
      if (featureKeys != null && featureKeys.isNotEmpty) {
        AppLogger.info(
          '[Sync] feature_filter_ignored_for_operational_runner '
          'features=${featureKeys.join(',')}',
        );
      }
      final result = await _ref
          .read(operationalSyncRunnerProvider)
          .run(retryOnly: retryOnly, ignoreRetryBackoff: ignoreRetryBackoff);
      if (!_isCurrentSession()) {
        return _cancelledResult(retryOnly: retryOnly);
      }
      return result;
    } finally {
      if (_isCurrentSession()) {
        _ref.read(appDataRefreshProvider.notifier).state++;
      }
    }
  }

  bool _isCurrentSession() {
    return !_disposed &&
        _ref.read(sessionRuntimeKeyProvider) == _sessionRuntimeKey;
  }

  SyncBatchResult _cancelledResult({required bool retryOnly}) {
    final now = DateTime.now();
    return SyncBatchResult(
      processedCount: 0,
      syncedCount: 0,
      failedCount: 0,
      blockedCount: 0,
      conflictCount: 0,
      reprocessedOnly: retryOnly,
      startedAt: now,
      finishedAt: now,
    );
  }
}
