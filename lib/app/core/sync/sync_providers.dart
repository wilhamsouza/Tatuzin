import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_context/app_operational_context.dart';
import '../app_context/data_access_policy.dart';
import '../config/app_environment.dart';
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
import 'sqlite_sync_queue_repository.dart';
import 'sync_dependency_resolver.dart';
import 'sync_feature_processor.dart';
import 'sync_queue_engine.dart';
import 'sync_queue_repository.dart';
import 'sync_retry_policy.dart';

final syncQueueRepositoryProvider = Provider<SyncQueueRepository>((ref) {
  return SqliteSyncQueueRepository(ref.read(appDatabaseProvider));
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
        saleRepository: ref.read(localSaleRepositoryProvider),
        fiadoRepository: ref.read(localFiadoRepositoryProvider),
        salesRemoteDatasource: ref.read(salesRemoteDatasourceProvider),
        financialEventsRemoteDatasource: ref.read(
          financialEventsRemoteDatasourceProvider,
        ),
        operationalContext: ref.watch(appOperationalContextProvider),
        dataAccessPolicy: ref.watch(appDataAccessPolicyProvider),
      );
    });

final syncDependencyResolverProvider = Provider<SyncDependencyResolver>((ref) {
  return SyncDependencyResolver(
    categoryRepository: ref.read(localCategoryRepositoryProvider),
    productRepository: ref.read(localProductRepositoryProvider),
    supplierRepository: ref.read(localSupplierRepositoryProvider),
    supplyRepository: ref.read(localSupplyRepositoryProvider),
    purchaseRepository: ref.read(localPurchaseRepositoryProvider),
    saleRepository: ref.read(localSaleRepositoryProvider),
    fiadoRepository: ref.read(localFiadoRepositoryProvider),
    cashRepository: ref.read(localCashRepositoryProvider),
  );
});

final syncFeatureProcessorsProvider = Provider<List<SyncFeatureProcessor>>((
  ref,
) {
  return <SyncFeatureProcessor>[
    ref.read(categoryHybridRepositoryProvider),
    ref.read(supplyHybridRepositoryProvider),
    ref.read(productHybridRepositoryProvider),
    ref.read(productRecipeSyncProcessorProvider),
    ref.read(clientHybridRepositoryProvider),
    ref.read(supplierHybridRepositoryProvider),
    ref.read(purchaseHybridRepositoryProvider),
    ref.read(salesHybridRepositoryProvider),
    ref.read(financialEventSyncProcessorProvider),
    ref.read(cashEventSyncProcessorProvider),
  ];
});

final syncQueueEngineProvider = Provider<SyncQueueEngine>((ref) {
  return SyncQueueEngine(
    queueRepository: ref.read(syncQueueRepositoryProvider),
    processors: ref.read(syncFeatureProcessorsProvider),
    retryPolicy: ref.read(syncRetryPolicyProvider),
    dependencyResolver: ref.read(syncDependencyResolverProvider),
  );
});
