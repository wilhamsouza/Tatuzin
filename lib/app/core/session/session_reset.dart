import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/app_logger.dart';
import '../../../modules/account/presentation/providers/account_cloud_providers.dart';
import '../../../modules/backup/presentation/providers/backup_providers.dart';
import '../../../modules/caixa/presentation/providers/cash_providers.dart';
import '../../../modules/carrinho/presentation/providers/cart_provider.dart';
import '../../../modules/categorias/presentation/providers/category_providers.dart';
import '../../../modules/clientes/presentation/providers/client_providers.dart';
import '../../../modules/compras/presentation/providers/purchase_providers.dart';
import '../../../modules/comprovantes/presentation/providers/receipt_providers.dart';
import '../../../modules/custos/presentation/providers/cost_providers.dart';
import '../../../modules/dashboard/presentation/providers/dashboard_providers.dart';
import '../../../modules/estoque/presentation/providers/inventory_providers.dart';
import '../../../modules/fiado/presentation/providers/fiado_providers.dart';
import '../../../modules/fornecedores/presentation/providers/supplier_providers.dart';
import '../../../modules/historico_vendas/presentation/providers/sale_history_providers.dart';
import '../../../modules/insumos/presentation/providers/supply_providers.dart';
import '../../../modules/pedidos/presentation/providers/order_print_providers.dart';
import '../../../modules/pedidos/presentation/providers/order_providers.dart';
import '../../../modules/produtos/presentation/providers/product_providers.dart';
import '../../../modules/relatorios/presentation/providers/report_providers.dart';
import '../../../modules/system/presentation/providers/system_providers.dart';
import '../../../modules/vendas/presentation/providers/sales_providers.dart';
import '../database/app_database.dart';
import '../providers/app_data_refresh_provider.dart';
import '../sync/sync_providers.dart';
import '../sync/sync_queue_feature_summary.dart';
import 'app_session.dart';
import 'session_provider.dart';

typedef SessionSignOutReset =
    Future<SessionSignOutResetSnapshot> Function(AppSession session);

final sessionSignOutResetProvider = Provider<SessionSignOutReset>((ref) {
  return (session) => prepareSessionSignOutReset(ref, session);
});

class SessionSignOutResetSnapshot {
  const SessionSignOutResetSnapshot({
    required this.pendingSyncCount,
    required this.hadActiveSync,
    required this.tenantIsolationKey,
    required this.databaseClosed,
  });

  final int pendingSyncCount;
  final bool hadActiveSync;
  final String? tenantIsolationKey;
  final bool databaseClosed;
}

final sessionContextResetProvider = Provider<void>((ref) {
  ref.listen<AppSession>(appSessionProvider, (previous, next) {
    if (previous == null) {
      return;
    }

    final previousRuntimeKey = _safeRuntimeKeyFor(previous);
    final nextRuntimeKey = _safeRuntimeKeyFor(next);
    if (previousRuntimeKey == nextRuntimeKey) {
      return;
    }

    final previousIsolationKey = _safeIsolationKeyFor(previous);
    final autoSyncCoordinator = ref.read(autoSyncCoordinatorProvider);
    final syncBatchRunner = ref.read(syncBatchRunnerProvider);
    autoSyncCoordinator.cancelPending();
    resetSessionScopedProviders(ref);
    unawaited(
      _disposePreviousRuntime(
        autoSyncCoordinator: autoSyncCoordinator,
        syncBatchRunner: syncBatchRunner,
        isolationKey: previousIsolationKey,
        previousRuntimeKey: previousRuntimeKey,
        nextRuntimeKey: nextRuntimeKey,
      ),
    );
  });
});

Future<void> _disposePreviousRuntime({
  required dynamic autoSyncCoordinator,
  required dynamic syncBatchRunner,
  required String? isolationKey,
  required String previousRuntimeKey,
  required String nextRuntimeKey,
}) async {
  try {
    await autoSyncCoordinator.stopForSessionReset(
      timeout: const Duration(seconds: 5),
    );
    await syncBatchRunner.stopForSessionReset(
      timeout: const Duration(seconds: 5),
    );
    AppLogger.info(
      '[SessionReset] runtime_sync_stopped | '
      'previous_runtime_key=$previousRuntimeKey | '
      'next_runtime_key=$nextRuntimeKey',
    );
  } catch (error, stackTrace) {
    AppLogger.error(
      '[SessionReset] runtime_sync_stop_failed | '
      'previous_runtime_key=$previousRuntimeKey | '
      'next_runtime_key=$nextRuntimeKey',
      error: error,
      stackTrace: stackTrace,
    );
  }

  if (isolationKey == null) {
    return;
  }

  await closeSessionDatabaseForReset(
    SessionSignOutResetSnapshot(
      pendingSyncCount: 0,
      hadActiveSync: false,
      tenantIsolationKey: isolationKey,
      databaseClosed: false,
    ),
  );
}

Future<SessionSignOutResetSnapshot> prepareSessionSignOutReset(
  Ref ref,
  AppSession session, {
  Duration syncStopTimeout = const Duration(seconds: 5),
}) async {
  final isolationKey = _safeIsolationKeyFor(session);
  final pendingSyncCount = await _safePendingSyncCount(ref);
  final hadActiveSync = ref.read(syncBatchActivityProvider);
  AppLogger.info(
    '[SessionReset] logout_started pending_sync_count=$pendingSyncCount | '
    'active_sync=$hadActiveSync | '
    'tenant_key=${isolationKey ?? 'n/a'}',
  );

  try {
    await ref
        .read(autoSyncCoordinatorProvider)
        .stopForSessionReset(timeout: syncStopTimeout);
    await ref
        .read(syncBatchRunnerProvider)
        .stopForSessionReset(timeout: syncStopTimeout);
    ref.read(syncBatchActivityProvider.notifier).state = false;
    AppLogger.info('[SessionReset] auto_sync_stopped');
  } catch (error, stackTrace) {
    AppLogger.error(
      '[SessionReset] auto_sync_stop_failed',
      error: error,
      stackTrace: stackTrace,
    );
  }

  return SessionSignOutResetSnapshot(
    pendingSyncCount: pendingSyncCount,
    hadActiveSync: hadActiveSync,
    tenantIsolationKey: isolationKey,
    databaseClosed: false,
  );
}

Future<SessionSignOutResetSnapshot> closeSessionDatabaseForReset(
  SessionSignOutResetSnapshot snapshot, {
  Duration databaseCloseTimeout = const Duration(seconds: 8),
}) async {
  final isolationKey = snapshot.tenantIsolationKey;
  if (isolationKey == null) {
    return snapshot;
  }

  AppLogger.info(
    '[SessionReset] database_close_started | tenant_key=$isolationKey | '
    'database_name=${AppDatabase.databaseNameForIsolationKey(isolationKey)}',
  );
  try {
    await AppDatabase.closeForIsolationKey(
      isolationKey,
    ).timeout(databaseCloseTimeout);
    AppLogger.info(
      '[SessionReset] database_close_finished | tenant_key=$isolationKey',
    );
    return SessionSignOutResetSnapshot(
      pendingSyncCount: snapshot.pendingSyncCount,
      hadActiveSync: snapshot.hadActiveSync,
      tenantIsolationKey: snapshot.tenantIsolationKey,
      databaseClosed: true,
    );
  } catch (error, stackTrace) {
    AppLogger.error(
      '[SessionReset] database_close_failed | tenant_key=$isolationKey',
      error: error,
      stackTrace: stackTrace,
    );
    return snapshot;
  }
}

void resetSessionScopedProviders(Ref ref) {
  ref.read(syncBatchActivityProvider.notifier).state = false;

  ref.invalidate(sessionIsolationKeyProvider);
  ref.invalidate(sessionRuntimeKeyProvider);
  ref.invalidate(appDatabaseProvider);
  ref.invalidate(appStartupProvider);
  ref.invalidate(appDataRefreshProvider);

  ref.invalidate(operationalDashboardRepositoryProvider);
  ref.invalidate(operationalDashboardSnapshotProvider);

  ref.invalidate(cartProvider);

  ref.invalidate(localCategoryRepositoryProvider);
  ref.invalidate(categoriesRemoteDatasourceProvider);
  ref.invalidate(categoryHybridRepositoryProvider);
  ref.invalidate(categoryRepositoryProvider);
  ref.invalidate(categorySearchQueryProvider);
  ref.invalidate(categoryAllProvider);
  ref.invalidate(categoryListProvider);
  ref.invalidate(categoryOptionsProvider);
  ref.invalidate(categorySyncControllerProvider);

  ref.invalidate(localProductRepositoryProvider);
  ref.invalidate(productsRemoteDatasourceProvider);
  ref.invalidate(productRecipesRemoteDatasourceProvider);
  ref.invalidate(localCatalogRepositoryProvider);
  ref.invalidate(productMediaStorageProvider);
  ref.invalidate(baseProductOptionsProvider);
  ref.invalidate(productHybridRepositoryProvider);
  ref.invalidate(productRecipeSyncProcessorProvider);
  ref.invalidate(productRepositoryProvider);
  ref.invalidate(productSearchQueryProvider);
  ref.invalidate(productListProvider);
  ref.invalidate(productCatalogProvider);
  ref.invalidate(productProfitabilitySearchQueryProvider);
  ref.invalidate(productProfitabilityFilterProvider);
  ref.invalidate(productProfitabilitySortProvider);
  ref.invalidate(productProfitabilityRowsProvider);
  ref.invalidate(productSyncControllerProvider);

  ref.invalidate(localClientRepositoryProvider);
  ref.invalidate(localCustomerCreditRepositoryProvider);
  ref.invalidate(customersRemoteDatasourceProvider);
  ref.invalidate(clientHybridRepositoryProvider);
  ref.invalidate(clientRepositoryProvider);
  ref.invalidate(customerCreditRepositoryProvider);
  ref.invalidate(clientSearchQueryProvider);
  ref.invalidate(clientListProvider);
  ref.invalidate(clientLookupProvider);
  ref.invalidate(customerCreditBalanceProvider);
  ref.invalidate(customerCreditTransactionsProvider);
  ref.invalidate(customerCreditTransactionProvider);
  ref.invalidate(customerCreditControllerProvider);
  ref.invalidate(clientSyncControllerProvider);

  ref.invalidate(localSaleRepositoryProvider);
  ref.invalidate(salesRemoteDatasourceProvider);
  ref.invalidate(salesHybridRepositoryProvider);
  ref.invalidate(saleCancellationSyncProcessorProvider);
  ref.invalidate(saleRepositoryProvider);
  ref.invalidate(salesSearchQueryProvider);
  ref.invalidate(salesCatalogProvider);
  ref.invalidate(salesQuickAddProvider);
  ref.invalidate(finalizeCashSaleUseCaseProvider);
  ref.invalidate(finalizeCreditSaleUseCaseProvider);
  ref.invalidate(cancelSaleUseCaseProvider);
  ref.invalidate(checkoutControllerProvider);
  ref.invalidate(cancelSaleControllerProvider);

  ref.invalidate(localCashRepositoryProvider);
  ref.invalidate(cashRemoteDatasourceProvider);
  ref.invalidate(cashRepositoryProvider);
  ref.invalidate(cashEventSyncProcessorProvider);
  ref.invalidate(currentCashOperatorNameProvider);
  ref.invalidate(currentCashSessionProvider);
  ref.invalidate(currentCashMovementsProvider);
  ref.invalidate(cashSessionHistoryProvider);
  ref.invalidate(cashSessionDetailProvider);
  ref.invalidate(openCashSessionUseCaseProvider);
  ref.invalidate(closeCashSessionUseCaseProvider);
  ref.invalidate(cashMovementFilterProvider);
  ref.invalidate(cashMovementVisibleCountProvider);
  ref.invalidate(cashLastUpdatedAtProvider);
  ref.invalidate(filteredCashMovementsProvider);
  ref.invalidate(visibleCashMovementsProvider);
  ref.invalidate(cashMovementCountsProvider);
  ref.invalidate(cashActionControllerProvider);

  ref.invalidate(localFiadoRepositoryProvider);
  ref.invalidate(fiadoRemoteDatasourceProvider);
  ref.invalidate(fiadoRepositoryProvider);
  ref.invalidate(fiadoPaymentSyncProcessorProvider);
  ref.invalidate(fiadoSearchQueryProvider);
  ref.invalidate(fiadoStatusFilterProvider);
  ref.invalidate(fiadoOverdueOnlyProvider);
  ref.invalidate(fiadoListProvider);
  ref.invalidate(fiadoDetailProvider);
  ref.invalidate(registerFiadoPaymentUseCaseProvider);
  ref.invalidate(fiadoPaymentControllerProvider);

  ref.invalidate(localSupplierRepositoryProvider);
  ref.invalidate(suppliersRemoteDatasourceProvider);
  ref.invalidate(supplierHybridRepositoryProvider);
  ref.invalidate(supplierRepositoryProvider);
  ref.invalidate(supplierSearchQueryProvider);
  ref.invalidate(supplierAllProvider);
  ref.invalidate(supplierListProvider);
  ref.invalidate(supplierOptionsProvider);
  ref.invalidate(supplierLookupProvider);
  ref.invalidate(supplierDetailProvider);
  ref.invalidate(supplierSyncControllerProvider);

  ref.invalidate(localSupplyRepositoryProvider);
  ref.invalidate(suppliesRemoteDatasourceProvider);
  ref.invalidate(supplyHybridRepositoryProvider);
  ref.invalidate(supplyRepositoryProvider);
  ref.invalidate(supplySearchQueryProvider);
  ref.invalidate(supplyListProvider);
  ref.invalidate(activeSupplyOptionsProvider);
  ref.invalidate(supplyDetailProvider);
  ref.invalidate(supplyInventoryOverviewProvider);
  ref.invalidate(reorderSuggestionsSearchQueryProvider);
  ref.invalidate(reorderSuggestionsFilterProvider);
  ref.invalidate(supplyReorderSuggestionsProvider);
  ref.invalidate(supplyInventoryMovementsProvider);
  ref.invalidate(supplyCostHistoryProvider);
  ref.invalidate(supplyActionControllerProvider);
  ref.invalidate(supplySyncControllerProvider);

  ref.invalidate(localPurchaseRepositoryProvider);
  ref.invalidate(purchasesRemoteDatasourceProvider);
  ref.invalidate(purchaseHybridRepositoryProvider);
  ref.invalidate(purchaseRepositoryProvider);
  ref.invalidate(purchaseSearchQueryProvider);
  ref.invalidate(purchaseStatusFilterProvider);
  ref.invalidate(purchaseSupplierFilterProvider);
  ref.invalidate(purchaseListProvider);
  ref.invalidate(purchaseDetailProvider);
  ref.invalidate(purchasesBySupplierProvider);
  ref.invalidate(purchaseSyncControllerProvider);

  ref.invalidate(localInventoryRepositoryProvider);
  ref.invalidate(inventoryRemoteDatasourceProvider);
  ref.invalidate(inventoryRepositoryProvider);
  ref.invalidate(localInventoryCountRepositoryProvider);
  ref.invalidate(stockAvailabilityRepositoryProvider);
  ref.invalidate(stockReservationRepositoryProvider);
  ref.invalidate(inventoryCountRepositoryProvider);
  ref.invalidate(inventorySearchQueryProvider);
  ref.invalidate(inventoryFilterProvider);
  ref.invalidate(inventoryItemsProvider);
  ref.invalidate(inventoryItemOptionsProvider);
  ref.invalidate(inventoryActiveItemOptionsProvider);
  ref.invalidate(inventoryMovementsProvider);
  ref.invalidate(inventoryCountSessionsProvider);
  ref.invalidate(inventoryCountSessionDetailProvider);
  ref.invalidate(inventoryActionControllerProvider);
  ref.invalidate(inventoryCountActionControllerProvider);

  ref.invalidate(localCostRepositoryProvider);
  ref.invalidate(costsRemoteDatasourceProvider);
  ref.invalidate(costRepositoryProvider);
  ref.invalidate(costOverviewProvider);
  ref.invalidate(costSearchQueryProvider);
  ref.invalidate(costStatusFilterProvider);
  ref.invalidate(costDateFromFilterProvider);
  ref.invalidate(costDateToFilterProvider);
  ref.invalidate(costOverdueOnlyFilterProvider);
  ref.invalidate(costsProvider);
  ref.invalidate(costDetailProvider);
  ref.invalidate(costActionControllerProvider);

  ref.invalidate(saleHistoryRepositoryProvider);
  ref.invalidate(saleHistorySearchQueryProvider);
  ref.invalidate(saleHistoryStatusFilterProvider);
  ref.invalidate(saleHistoryTypeFilterProvider);
  ref.invalidate(saleHistoryFromProvider);
  ref.invalidate(saleHistoryToProvider);
  ref.invalidate(saleHistoryListProvider);
  ref.invalidate(saleDetailProvider);
  ref.invalidate(saleReturnRepositoryProvider);
  ref.invalidate(saleReturnsProvider);
  ref.invalidate(saleExchangeProductLookupProvider);
  ref.invalidate(saleExchangeControllerProvider);
  ref.invalidate(commercialReceiptRepositoryProvider);
  ref.invalidate(commercialReceiptProvider);
  ref.invalidate(receiptActionControllerProvider);

  ref.invalidate(operationalOrderRepositoryProvider);
  ref.invalidate(operationalOrderSearchQueryProvider);
  ref.invalidate(operationalOrderStatusFilterProvider);
  ref.invalidate(operationalOrderBoardProvider);
  ref.invalidate(operationalOrderDetailProvider);
  ref.invalidate(orderCatalogProvider);
  ref.invalidate(orderSellableProductAvailabilityProvider);
  ref.invalidate(orderCatalogOptionsProvider);
  ref.invalidate(orderCatalogGroupsProvider);
  ref.invalidate(orderCatalogOptionGroupsProvider);
  ref.invalidate(createOperationalOrderControllerProvider);
  ref.invalidate(operationalOrderDraftControllerProvider);
  ref.invalidate(operationalOrderItemControllerProvider);
  ref.invalidate(operationalOrderStatusControllerProvider);
  ref.invalidate(operationalOrderBillingControllerProvider);
  ref.invalidate(orderTicketDocumentProvider);
  ref.invalidate(orderKitchenDispatchControllerProvider);
  ref.invalidate(orderTicketReprintControllerProvider);

  ref.invalidate(pdvOperationalReportRepositoryProvider);
  ref.invalidate(reportRemoteDatasourceProvider);
  ref.invalidate(erpManagementReportRepositoryProvider);
  ref.invalidate(reportRepositoryProvider);
  ref.invalidate(reportFilterProvider);
  ref.invalidate(reportPageSessionProvider);
  ref.invalidate(reportPeriodProvider);
  ref.invalidate(reportPreviousFilterProvider);
  ref.invalidate(reportOverviewResultProvider);
  ref.invalidate(reportOverviewProvider);
  ref.invalidate(reportPreviousOverviewResultProvider);
  ref.invalidate(reportPreviousOverviewProvider);
  ref.invalidate(salesTrendResultProvider);
  ref.invalidate(salesTrendProvider);
  ref.invalidate(topProductsReportResultProvider);
  ref.invalidate(topProductsReportProvider);
  ref.invalidate(topVariantsReportResultProvider);
  ref.invalidate(topVariantsReportProvider);
  ref.invalidate(profitabilityReportResultProvider);
  ref.invalidate(profitabilityReportProvider);
  ref.invalidate(profitabilityCategoryReportResultProvider);
  ref.invalidate(profitabilityCategoryReportProvider);
  ref.invalidate(cashflowReportResultProvider);
  ref.invalidate(cashflowReportProvider);
  ref.invalidate(inventoryHealthReportResultProvider);
  ref.invalidate(inventoryHealthReportProvider);
  ref.invalidate(customerRankingReportResultProvider);
  ref.invalidate(customerRankingReportProvider);
  ref.invalidate(purchaseSummaryReportResultProvider);
  ref.invalidate(purchaseSummaryReportProvider);
  ref.invalidate(reportSummaryProvider);
  ref.invalidate(reportClientOptionsProvider);
  ref.invalidate(reportCategoryOptionsProvider);
  ref.invalidate(reportProductOptionsProvider);
  ref.invalidate(reportSupplierOptionsProvider);
  ref.invalidate(reportVariantOptionsProvider);
  ref.invalidate(reportFilterOptionLabelsProvider);

  ref.invalidate(accountCloudAttentionItemsProvider);
  ref.invalidate(accountCloudStatusProvider);

  ref.invalidate(databaseBackupServiceProvider);
  ref.invalidate(databaseRestoreServiceProvider);
  ref.invalidate(lastGeneratedBackupProvider);
  ref.invalidate(selectedRestoreCandidateProvider);
  ref.invalidate(backupActionControllerProvider);

  ref.invalidate(syncQueueRepositoryProvider);
  ref.invalidate(operationalSyncQueueRepositoryProvider);
  ref.invalidate(operationalSyncRemoteDataSourceProvider);
  ref.invalidate(appSnapshotRemoteDataSourceProvider);
  ref.invalidate(syncRetryPolicyProvider);
  ref.invalidate(financialEventsRemoteDatasourceProvider);
  ref.invalidate(financialEventSyncProcessorProvider);
  ref.invalidate(syncDependencyResolverProvider);
  ref.invalidate(syncFeatureProcessorsProvider);
  ref.invalidate(syncQueueEngineProvider);
  ref.invalidate(operationalSyncRunnerProvider);
  ref.invalidate(syncBatchRunnerProvider);
  ref.invalidate(autoSyncCoordinatorProvider);
  ref.invalidate(syncReadinessRepositoryProvider);
  ref.invalidate(syncReadinessSummaryProvider);
  ref.invalidate(syncQueueFeatureSummariesProvider);
  ref.invalidate(syncAuditRepositoryProvider);
  ref.invalidate(syncAuditLogsProvider);
  ref.invalidate(localRemoteReconciliationRepositoryProvider);
  ref.invalidate(syncReconciliationRepositoryProvider);
  ref.invalidate(syncRepairRepositoryProvider);
  ref.invalidate(syncReconciliationControllerProvider);
  ref.invalidate(syncRepairDecisionsProvider);
  ref.invalidate(syncRepairSummaryProvider);
  ref.invalidate(syncRepairDecisionsByFeatureProvider);
  ref.invalidate(syncRepairControllerProvider);
  ref.invalidate(syncHealthOverviewProvider);
  ref.invalidate(catalogSyncControllerProvider);
  AppLogger.info('[SessionReset] providers_invalidated');
}

String? _safeIsolationKeyFor(AppSession session) {
  try {
    return SessionIsolation.keyFor(session);
  } catch (_) {
    return null;
  }
}

String _safeRuntimeKeyFor(AppSession session) {
  try {
    return SessionIsolation.runtimeKeyFor(session);
  } catch (_) {
    return 'invalid_session_runtime_key';
  }
}

Future<int> _safePendingSyncCount(Ref ref) async {
  var pendingSyncCount = 0;
  try {
    final summaries = await ref
        .read(syncQueueRepositoryProvider)
        .listFeatureSummaries()
        .timeout(const Duration(seconds: 3));
    pendingSyncCount += _countPendingSummaries(summaries);
  } catch (error, stackTrace) {
    AppLogger.error(
      '[SessionReset] pending_sync_count_failed',
      error: error,
      stackTrace: stackTrace,
    );
  }

  try {
    final operationalSummaries = await ref
        .read(operationalSyncQueueRepositoryProvider)
        .listFeatureSummaries()
        .timeout(const Duration(seconds: 3));
    pendingSyncCount += _countPendingSummaries(operationalSummaries);
  } catch (error, stackTrace) {
    AppLogger.error(
      '[SessionReset] operational_pending_sync_count_failed',
      error: error,
      stackTrace: stackTrace,
    );
  }

  return pendingSyncCount;
}

int _countPendingSummaries(Iterable<SyncQueueFeatureSummary> summaries) {
  return summaries.fold<int>(
    0,
    (total, summary) =>
        total +
        summary.pendingForDisplay +
        summary.errorCount +
        summary.blockedCount +
        summary.conflictCount +
        summary.activeProcessingCount,
  );
}
