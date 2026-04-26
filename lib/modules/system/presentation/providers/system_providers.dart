import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/config/app_data_mode.dart';
import '../../../../app/core/config/app_environment.dart';
import '../../../../app/core/database/app_database.dart';
import '../../../../app/core/errors/app_exceptions.dart';
import '../../../../app/core/network/contracts/api_client_contract.dart';
import '../../../../app/core/network/network_providers.dart';
import '../../../../app/core/network/remote_feature_diagnostic.dart';
import '../../../../app/core/providers/app_data_refresh_provider.dart';
import '../../../../app/core/providers/provider_guard.dart';
import '../../../../app/core/session/auth_token_storage.dart';
import '../../../../app/core/sync/local_remote_reconciliation_repository.dart';
import '../../../../app/core/sync/sqlite_sync_audit_repository.dart';
import '../../../../app/core/sync/sync_batch_result.dart';
import '../../../../app/core/sync/sync_audit_log.dart';
import '../../../../app/core/sync/sync_providers.dart';
import '../../../../app/core/sync/sync_display_state.dart';
import '../../../../app/core/sync/sync_repair_action.dart';
import '../../../../app/core/sync/sync_repair_decision.dart';
import '../../../../app/core/sync/sync_repair_repository.dart';
import '../../../../app/core/sync/sync_repair_result.dart';
import '../../../../app/core/sync/sync_repair_summary.dart';
import '../../../../app/core/sync/sync_reconciliation_repository.dart';
import '../../../../app/core/sync/sync_reconciliation_result.dart';
import '../../../../app/core/sync/sqlite_sync_readiness_repository.dart';
import '../../../../app/core/sync/sync_feature_summary.dart';
import '../../../../app/core/sync/sync_queue_feature_summary.dart';
import '../../../../app/core/sync/sync_readiness_repository.dart';
import '../../../categorias/presentation/providers/category_providers.dart';
import '../../../caixa/presentation/providers/cash_providers.dart';
import '../../../clientes/presentation/providers/client_providers.dart';
import '../../../compras/presentation/providers/purchase_providers.dart';
import '../../../estoque/presentation/providers/inventory_providers.dart';
import '../../../fiado/presentation/providers/fiado_providers.dart';
import '../../../fornecedores/presentation/providers/supplier_providers.dart';
import '../../../insumos/presentation/providers/supply_providers.dart';
import '../../../produtos/presentation/providers/product_providers.dart';
import '../../../vendas/presentation/providers/sales_providers.dart';

final syncReadinessRepositoryProvider = Provider<SyncReadinessRepository>((
  ref,
) {
  return SqliteSyncReadinessRepository(ref.watch(appDatabaseProvider));
});

final syncReadinessSummaryProvider = FutureProvider<List<SyncFeatureSummary>>((
  ref,
) async {
  ref.watch(appDataRefreshProvider);
  return runProviderGuarded(
    'syncReadinessSummaryProvider',
    () => ref.watch(syncReadinessRepositoryProvider).listFeatureSummaries(),
    timeout: localProviderTimeout,
  );
});

final syncQueueFeatureSummariesProvider =
    FutureProvider<List<SyncQueueFeatureSummary>>((ref) async {
      ref.watch(appDataRefreshProvider);
      return runProviderGuarded(
        'syncQueueFeatureSummariesProvider',
        () => ref.watch(syncQueueRepositoryProvider).listFeatureSummaries(),
        timeout: localProviderTimeout,
      );
    });

final syncAuditRepositoryProvider = Provider<SqliteSyncAuditRepository>((ref) {
  return SqliteSyncAuditRepository(ref.watch(appDatabaseProvider));
});

final syncAuditLogsProvider = FutureProvider<List<SyncAuditLog>>((ref) async {
  ref.watch(appDataRefreshProvider);
  return runProviderGuarded(
    'syncAuditLogsProvider',
    () => ref.watch(syncAuditRepositoryProvider).listRecent(limit: 40),
    timeout: localProviderTimeout,
  );
});

final localRemoteReconciliationRepositoryProvider =
    Provider<LocalRemoteReconciliationRepository>((ref) {
      return LocalRemoteReconciliationRepository(
        appDatabase: ref.watch(appDatabaseProvider),
        suppliersRemoteDatasource: ref.read(suppliersRemoteDatasourceProvider),
        categoriesRemoteDatasource: ref.read(
          categoriesRemoteDatasourceProvider,
        ),
        productsRemoteDatasource: ref.read(productsRemoteDatasourceProvider),
        customersRemoteDatasource: ref.read(customersRemoteDatasourceProvider),
        purchasesRemoteDatasource: ref.read(purchasesRemoteDatasourceProvider),
        salesRemoteDatasource: ref.read(salesRemoteDatasourceProvider),
        financialEventsRemoteDatasource: ref.read(
          financialEventsRemoteDatasourceProvider,
        ),
        purchaseRepository: ref.read(localPurchaseRepositoryProvider),
        saleRepository: ref.read(localSaleRepositoryProvider),
        fiadoRepository: ref.read(localFiadoRepositoryProvider),
      );
    });

final syncReconciliationRepositoryProvider =
    Provider<SyncReconciliationRepository>((ref) {
      return ref.watch(localRemoteReconciliationRepositoryProvider);
    });

final syncRepairRepositoryProvider = Provider<SyncRepairRepository>((ref) {
  return ref.watch(localRemoteReconciliationRepositoryProvider);
});

final syncReconciliationControllerProvider =
    AsyncNotifierProvider<
      SyncReconciliationController,
      List<SyncReconciliationResult>
    >(SyncReconciliationController.new);

final syncRepairDecisionsProvider = Provider<List<SyncRepairDecision>>((ref) {
  final results =
      ref.watch(syncReconciliationControllerProvider).valueOrNull ??
      const <SyncReconciliationResult>[];
  return ref.watch(syncRepairRepositoryProvider).buildDecisions(results);
});

final syncRepairSummaryProvider = Provider<SyncRepairSummary>((ref) {
  final decisions = ref.watch(syncRepairDecisionsProvider);
  return ref.watch(syncRepairRepositoryProvider).buildSummary(decisions);
});

final syncRepairDecisionsByFeatureProvider =
    Provider<Map<String, List<SyncRepairDecision>>>((ref) {
      final grouped = <String, List<SyncRepairDecision>>{};
      for (final decision in ref.watch(syncRepairDecisionsProvider)) {
        grouped
            .putIfAbsent(
              decision.target.featureKey,
              () => <SyncRepairDecision>[],
            )
            .add(decision);
      }
      return grouped;
    });

final syncRepairControllerProvider =
    AsyncNotifierProvider<SyncRepairController, void>(SyncRepairController.new);

final remoteDiagnosticsProvider = FutureProvider<List<RemoteFeatureDiagnostic>>(
  (ref) async {
    return runProviderGuarded(
      'remoteDiagnosticsProvider',
      () async => <RemoteFeatureDiagnostic>[
        await ref.watch(suppliersRemoteDatasourceProvider).fetchDiagnostic(),
        await ref.watch(suppliesRemoteDatasourceProvider).fetchDiagnostic(),
        await ref.watch(categoriesRemoteDatasourceProvider).fetchDiagnostic(),
        await ref.watch(productsRemoteDatasourceProvider).fetchDiagnostic(),
        await ref
            .watch(productRecipesRemoteDatasourceProvider)
            .fetchDiagnostic(),
        await ref.watch(customersRemoteDatasourceProvider).fetchDiagnostic(),
        await ref.watch(purchasesRemoteDatasourceProvider).fetchDiagnostic(),
        await ref.watch(salesRemoteDatasourceProvider).fetchDiagnostic(),
        await ref
            .watch(financialEventsRemoteDatasourceProvider)
            .fetchDiagnostic(),
        await ref.watch(cashRemoteDatasourceProvider).fetchDiagnostic(),
      ],
      timeout: defaultProviderTimeout,
    );
  },
);

final syncHealthOverviewProvider = Provider<SyncHealthOverview>((ref) {
  final summaries =
      ref.watch(syncQueueFeatureSummariesProvider).valueOrNull ??
      const <SyncQueueFeatureSummary>[];

  var totalPending = 0;
  var totalProcessing = 0;
  var totalActiveProcessing = 0;
  var totalStaleProcessing = 0;
  var totalSynced = 0;
  var totalErrors = 0;
  var totalBlocked = 0;
  var totalConflicts = 0;
  var totalAttempts = 0;
  DateTime? lastProcessedAt;
  DateTime? lastErrorAt;
  DateTime? nextRetryAt;

  for (final summary in summaries) {
    totalPending += summary.pendingCount;
    totalProcessing += summary.processingCount;
    totalActiveProcessing += summary.activeProcessingCount;
    totalStaleProcessing += summary.staleProcessingCount;
    totalSynced += summary.syncedCount;
    totalErrors += summary.errorCount;
    totalBlocked += summary.blockedCount;
    totalConflicts += summary.conflictCount;
    totalAttempts += summary.totalAttemptCount;

    if (summary.lastProcessedAt != null &&
        (lastProcessedAt == null ||
            summary.lastProcessedAt!.isAfter(lastProcessedAt))) {
      lastProcessedAt = summary.lastProcessedAt;
    }

    if (summary.lastErrorAt != null &&
        (lastErrorAt == null || summary.lastErrorAt!.isAfter(lastErrorAt))) {
      lastErrorAt = summary.lastErrorAt;
    }

    if (summary.nextRetryAt != null &&
        (nextRetryAt == null || summary.nextRetryAt!.isBefore(nextRetryAt))) {
      nextRetryAt = summary.nextRetryAt;
    }
  }

  return SyncHealthOverview(
    totalPending: totalPending,
    totalProcessing: totalProcessing,
    totalActiveProcessing: totalActiveProcessing,
    totalStaleProcessing: totalStaleProcessing,
    totalSynced: totalSynced,
    totalErrors: totalErrors,
    totalBlocked: totalBlocked,
    totalConflicts: totalConflicts,
    totalAttempts: totalAttempts,
    lastProcessedAt: lastProcessedAt,
    lastErrorAt: lastErrorAt,
    nextRetryAt: _clampRetryAfterLastProcessed(
      nextRetryAt: nextRetryAt,
      lastProcessedAt: lastProcessedAt,
    ),
  );
});

DateTime? _clampRetryAfterLastProcessed({
  required DateTime? nextRetryAt,
  required DateTime? lastProcessedAt,
}) {
  if (nextRetryAt == null || lastProcessedAt == null) {
    return nextRetryAt;
  }
  if (!nextRetryAt.isBefore(lastProcessedAt)) {
    return nextRetryAt;
  }
  return lastProcessedAt.add(const Duration(minutes: 1));
}

final hybridOperationalTruthSnapshotProvider =
    Provider<HybridOperationalTruthSnapshot>((ref) {
      final categories =
          ref.watch(categoryOptionsProvider).valueOrNull ?? const [];
      final products =
          ref.watch(productCatalogProvider).valueOrNull ?? const [];
      final customers = ref.watch(clientListProvider).valueOrNull ?? const [];
      final inventoryItems =
          ref.watch(inventoryItemsProvider).valueOrNull ?? const [];
      final syncHealth = ref.watch(syncHealthOverviewProvider);

      return HybridOperationalTruthSnapshot(
        activeCategories: categories
            .where((category) => category.isActive)
            .length,
        activeProducts: products.where((product) => product.isActive).length,
        localOnlyProducts: products
            .where((product) => product.remoteId == null)
            .length,
        productsWithLocalPhoto: products
            .where((product) => product.hasPhoto)
            .length,
        activeCustomers: customers
            .where((customer) => customer.isActive)
            .length,
        localOnlyCustomers: customers
            .where((customer) => customer.remoteId == null)
            .length,
        inventoryTrackedItems: inventoryItems.length,
        hasPendingCloudAttention:
            syncHealth.totalPending > 0 ||
            syncHealth.totalErrors > 0 ||
            syncHealth.totalBlocked > 0 ||
            syncHealth.totalConflicts > 0,
      );
    });

final catalogSyncControllerProvider =
    AsyncNotifierProvider<CatalogSyncController, void>(
      CatalogSyncController.new,
    );

final backendConnectionStatusProvider = FutureProvider<BackendConnectionStatus>(
  (ref) async {
    return runProviderGuarded(
      'backendConnectionStatusProvider',
      () => _resolveBackendConnectionStatus(ref),
      timeout: defaultProviderTimeout,
    );
  },
);

Future<BackendConnectionStatus> _resolveBackendConnectionStatus(Ref ref) async {
  final environment = ref.watch(appEnvironmentProvider);
  if (!environment.endpointConfig.isConfigured) {
    return BackendConnectionStatus(
      isConfigured: false,
      isReachable: false,
      companyLookupSucceeded: false,
      endpointLabel: environment.endpointConfig.summaryLabel,
      message: environment.dataMode == AppDataMode.localOnly
          ? 'Modo local ativo. A API oficial fica disponivel quando o app voltar a um modo remoto.'
          : 'Endpoint remoto indisponivel para este modo.',
      checkedAt: DateTime.now(),
    );
  }

  final apiClient = ref.watch(realApiClientProvider);

  try {
    await apiClient.getJson('/health');

    String? remoteCompanyName;
    var companyLookupSucceeded = false;
    final accessToken = await ref
        .read(authTokenStorageProvider)
        .readAccessToken();

    if (accessToken != null) {
      try {
        final companyResponse = await apiClient.getJson(
          '/companies/current',
          options: ApiRequestOptions(
            headers: <String, String>{'Authorization': 'Bearer $accessToken'},
          ),
        );
        final company =
            companyResponse.data['company'] as Map<String, dynamic>?;
        final companyName = company?['name'];
        if (companyName is String && companyName.trim().isNotEmpty) {
          remoteCompanyName = companyName.trim();
          companyLookupSucceeded = true;
        }
      } on AppException {
        companyLookupSucceeded = false;
      }
    }

    return BackendConnectionStatus(
      isConfigured: true,
      isReachable: true,
      companyLookupSucceeded: companyLookupSucceeded,
      endpointLabel: environment.endpointConfig.summaryLabel,
      message: companyLookupSucceeded
          ? 'API online e tenant remoto validado com a sessao atual.'
          : 'API online. O tenant remoto sera validado apos autenticacao real.',
      checkedAt: DateTime.now(),
      remoteCompanyName: remoteCompanyName,
    );
  } on AppException catch (error) {
    return BackendConnectionStatus(
      isConfigured: true,
      isReachable: false,
      companyLookupSucceeded: false,
      endpointLabel: environment.endpointConfig.summaryLabel,
      message: error.message,
      checkedAt: DateTime.now(),
    );
  } catch (error) {
    return BackendConnectionStatus(
      isConfigured: true,
      isReachable: false,
      companyLookupSucceeded: false,
      endpointLabel: environment.endpointConfig.summaryLabel,
      message: 'Falha inesperada ao testar a API remota: $error',
      checkedAt: DateTime.now(),
    );
  }
}

class BackendConnectionStatus {
  const BackendConnectionStatus({
    required this.isConfigured,
    required this.isReachable,
    required this.companyLookupSucceeded,
    required this.endpointLabel,
    required this.message,
    required this.checkedAt,
    this.remoteCompanyName,
  });

  final bool isConfigured;
  final bool isReachable;
  final bool companyLookupSucceeded;
  final String endpointLabel;
  final String message;
  final DateTime checkedAt;
  final String? remoteCompanyName;
}

class HybridOperationalTruthSnapshot {
  const HybridOperationalTruthSnapshot({
    required this.activeCategories,
    required this.activeProducts,
    required this.localOnlyProducts,
    required this.productsWithLocalPhoto,
    required this.activeCustomers,
    required this.localOnlyCustomers,
    required this.inventoryTrackedItems,
    required this.hasPendingCloudAttention,
  });

  final int activeCategories;
  final int activeProducts;
  final int localOnlyProducts;
  final int productsWithLocalPhoto;
  final int activeCustomers;
  final int localOnlyCustomers;
  final int inventoryTrackedItems;
  final bool hasPendingCloudAttention;
}

class SyncHealthOverview {
  const SyncHealthOverview({
    required this.totalPending,
    required this.totalProcessing,
    required this.totalActiveProcessing,
    required this.totalStaleProcessing,
    required this.totalSynced,
    required this.totalErrors,
    required this.totalBlocked,
    required this.totalConflicts,
    required this.totalAttempts,
    required this.lastProcessedAt,
    required this.lastErrorAt,
    required this.nextRetryAt,
  });

  final int totalPending;
  final int totalProcessing;
  final int totalActiveProcessing;
  final int totalStaleProcessing;
  final int totalSynced;
  final int totalErrors;
  final int totalBlocked;
  final int totalConflicts;
  final int totalAttempts;
  final DateTime? lastProcessedAt;
  final DateTime? lastErrorAt;
  final DateTime? nextRetryAt;

  int get totalPendingForDisplay => totalPending + totalStaleProcessing;

  bool get hasActiveProcessing => totalActiveProcessing > 0;

  bool get hasAttention =>
      totalErrors > 0 || totalBlocked > 0 || totalConflicts > 0;

  SyncDisplayState get displayState {
    if (hasAttention) {
      return SyncDisplayState.attention;
    }
    if (hasActiveProcessing) {
      return SyncDisplayState.syncing;
    }
    if (totalPendingForDisplay > 0) {
      return SyncDisplayState.pending;
    }
    return SyncDisplayState.synced;
  }
}

class CatalogSyncController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<SyncBatchResult> syncAll() {
    return _run(reprocessedOnly: false);
  }

  Future<SyncBatchResult> retryPending() {
    return _run(reprocessedOnly: true);
  }

  Future<SyncBatchResult> syncFeature(String featureKey) {
    return _run(reprocessedOnly: false, featureKeys: <String>[featureKey]);
  }

  Future<SyncBatchResult> syncFeatures(Iterable<String> featureKeys) {
    return _run(reprocessedOnly: false, featureKeys: featureKeys);
  }

  Future<SyncBatchResult> retryFeatures(Iterable<String> featureKeys) {
    return _run(reprocessedOnly: true, featureKeys: featureKeys);
  }

  Future<SyncBatchResult> _run({
    required bool reprocessedOnly,
    Iterable<String>? featureKeys,
  }) async {
    state = const AsyncLoading();
    try {
      final result = await ref
          .read(syncBatchRunnerProvider)
          .run(retryOnly: reprocessedOnly, featureKeys: featureKeys);
      state = const AsyncData(null);
      return result;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }
}

class SyncReconciliationController
    extends AsyncNotifier<List<SyncReconciliationResult>> {
  @override
  Future<List<SyncReconciliationResult>> build() async {
    return const <SyncReconciliationResult>[];
  }

  Future<List<SyncReconciliationResult>> run() async {
    state = const AsyncLoading();
    try {
      final results = await ref
          .read(syncReconciliationRepositoryProvider)
          .reconcileAll();
      ref.read(appDataRefreshProvider.notifier).state++;
      ref.invalidate(syncAuditLogsProvider);
      state = AsyncData(results);
      return results;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<int> repairFeature(String featureKey) async {
    state = const AsyncLoading();
    try {
      final repairedCount = await ref
          .read(syncReconciliationRepositoryProvider)
          .markFeatureForResync(featureKey);
      ref.read(appDataRefreshProvider.notifier).state++;
      ref.invalidate(syncQueueFeatureSummariesProvider);
      ref.invalidate(syncReadinessSummaryProvider);
      ref.invalidate(syncAuditLogsProvider);
      final refreshed = await ref
          .read(syncReconciliationRepositoryProvider)
          .reconcileAll();
      state = AsyncData(refreshed);
      return repairedCount;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }
}

class SyncRepairController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<SyncRepairResult> applyAction(SyncRepairAction action) async {
    state = const AsyncLoading();
    try {
      final result = await ref
          .read(syncRepairRepositoryProvider)
          .applyAction(action);
      await _refreshTechnicalState();
      state = const AsyncData(null);
      return result;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<SyncRepairResult> applySafeRepairs({
    Iterable<String>? featureKeys,
  }) async {
    state = const AsyncLoading();
    try {
      final result = await ref
          .read(syncRepairRepositoryProvider)
          .applySafeRepairs(featureKeys: featureKeys);
      await _refreshTechnicalState();
      state = const AsyncData(null);
      return result;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<void> _refreshTechnicalState() async {
    ref.read(appDataRefreshProvider.notifier).state++;
    ref.invalidate(syncQueueFeatureSummariesProvider);
    ref.invalidate(syncReadinessSummaryProvider);
    ref.invalidate(syncAuditLogsProvider);
    await ref.read(syncReconciliationControllerProvider.notifier).run();
  }
}
