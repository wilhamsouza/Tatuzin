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
import 'financial_event_sync_processor.dart';
import 'financial_events_remote_datasource.dart';
import 'real_financial_events_remote_datasource.dart';
import 'auto_sync_coordinator.dart';
import 'sqlite_sync_queue_repository.dart';
import 'sync_dependency_resolver.dart';
import 'sync_feature_processor.dart';
import 'sync_batch_result.dart';
import 'sync_queue_engine.dart';
import 'sync_queue_repository.dart';
import 'sync_retry_policy.dart';

final syncQueueRepositoryProvider = Provider<SyncQueueRepository>((ref) {
  return SqliteSyncQueueRepository(ref.watch(appDatabaseProvider));
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

final syncFeatureProcessorsProvider = Provider<List<SyncFeatureProcessor>>((
  ref,
) {
  return <SyncFeatureProcessor>[
    ref.watch(categoryHybridRepositoryProvider),
    ref.watch(supplyHybridRepositoryProvider),
    ref.watch(productHybridRepositoryProvider),
    ref.watch(productRecipeSyncProcessorProvider),
    ref.watch(clientHybridRepositoryProvider),
    ref.watch(supplierHybridRepositoryProvider),
    ref.watch(purchaseHybridRepositoryProvider),
    ref.watch(salesHybridRepositoryProvider),
    ref.watch(financialEventSyncProcessorProvider),
    ref.watch(cashEventSyncProcessorProvider),
  ];
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
      return environment.remoteSyncEnabled &&
          environment.endpointConfig.isConfigured &&
          session.isRemoteAuthenticated &&
          company.allowsCloudSync;
    },
    isRunning: () => ref.read(syncBatchActivityProvider),
    runSync: () => ref.read(syncBatchRunnerProvider).run(retryOnly: false),
    loadQueueSummaries: () {
      return ref.read(syncQueueRepositoryProvider).listFeatureSummaries();
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

  Future<SyncBatchResult> run({
    required bool retryOnly,
    Iterable<String>? featureKeys,
  }) {
    final running = _inFlight;
    if (running != null) {
      return running;
    }

    late final Future<SyncBatchResult> future;
    future = _execute(retryOnly: retryOnly, featureKeys: featureKeys);
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
    Iterable<String>? featureKeys,
  }) async {
    if (!_isCurrentSession()) {
      return _cancelledResult(retryOnly: retryOnly);
    }

    _ref.read(syncBatchActivityProvider.notifier).state = true;
    try {
      final result = await _ref
          .read(syncQueueEngineProvider)
          .process(featureKeys: featureKeys, retryOnly: retryOnly);
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
