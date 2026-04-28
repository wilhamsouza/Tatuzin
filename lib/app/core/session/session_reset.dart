import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../modules/caixa/presentation/providers/cash_providers.dart';
import '../../../modules/carrinho/presentation/providers/cart_provider.dart';
import '../../../modules/categorias/presentation/providers/category_providers.dart';
import '../../../modules/clientes/presentation/providers/client_providers.dart';
import '../../../modules/compras/presentation/providers/purchase_providers.dart';
import '../../../modules/dashboard/presentation/providers/dashboard_providers.dart';
import '../../../modules/fiado/presentation/providers/fiado_providers.dart';
import '../../../modules/fornecedores/presentation/providers/supplier_providers.dart';
import '../../../modules/insumos/presentation/providers/supply_providers.dart';
import '../../../modules/produtos/presentation/providers/product_providers.dart';
import '../../../modules/vendas/presentation/providers/sales_providers.dart';
import '../database/app_database.dart';
import '../providers/app_data_refresh_provider.dart';
import '../sync/sync_providers.dart';
import 'app_session.dart';
import 'session_provider.dart';

final sessionContextResetProvider = Provider<void>((ref) {
  ref.listen<AppSession>(appSessionProvider, (previous, next) {
    if (previous == null) {
      return;
    }

    if (SessionIsolation.runtimeKeyFor(previous) ==
        SessionIsolation.runtimeKeyFor(next)) {
      return;
    }

    ref.read(autoSyncCoordinatorProvider).cancelPending();
    resetSessionScopedProviders(ref);
  });
});

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

  ref.invalidate(syncQueueRepositoryProvider);
  ref.invalidate(syncRetryPolicyProvider);
  ref.invalidate(financialEventsRemoteDatasourceProvider);
  ref.invalidate(financialEventSyncProcessorProvider);
  ref.invalidate(syncDependencyResolverProvider);
  ref.invalidate(syncFeatureProcessorsProvider);
  ref.invalidate(syncQueueEngineProvider);
  ref.invalidate(syncBatchRunnerProvider);
  ref.invalidate(autoSyncCoordinatorProvider);
}
