import 'package:erp_pdv_app/app/core/app_context/app_operational_context.dart';
import 'package:erp_pdv_app/app/core/app_context/data_access_policy.dart';
import 'package:erp_pdv_app/app/core/config/app_data_mode.dart';
import 'package:erp_pdv_app/app/core/config/app_environment.dart';
import 'package:erp_pdv_app/app/core/database/app_database.dart';
import 'package:erp_pdv_app/app/core/errors/app_exceptions.dart';
import 'package:erp_pdv_app/app/core/network/endpoint_config.dart';
import 'package:erp_pdv_app/app/core/network/remote_feature_diagnostic.dart';
import 'package:erp_pdv_app/app/core/session/app_session.dart';
import 'package:erp_pdv_app/app/core/session/app_user.dart';
import 'package:erp_pdv_app/app/core/session/company_context.dart';
import 'package:erp_pdv_app/modules/compras/data/datasources/purchases_remote_datasource.dart';
import 'package:erp_pdv_app/modules/compras/data/models/purchase_sync_payload.dart';
import 'package:erp_pdv_app/modules/compras/data/models/remote_purchase_record.dart';
import 'package:erp_pdv_app/modules/compras/data/purchases_repository_impl.dart';
import 'package:erp_pdv_app/modules/compras/data/sqlite_purchase_repository.dart';
import 'package:erp_pdv_app/modules/compras/domain/entities/purchase.dart';
import 'package:erp_pdv_app/modules/compras/domain/entities/purchase_detail.dart';
import 'package:erp_pdv_app/modules/compras/domain/entities/purchase_payment.dart';
import 'package:erp_pdv_app/modules/compras/domain/entities/purchase_status.dart';
import 'package:erp_pdv_app/modules/compras/domain/repositories/purchase_repository.dart';
import 'package:erp_pdv_app/modules/compras/presentation/providers/purchase_providers.dart';
import 'package:erp_pdv_app/modules/custos/data/cost_repository_impl.dart';
import 'package:erp_pdv_app/modules/estoque/data/inventory_repository_impl.dart';
import 'package:erp_pdv_app/modules/estoque/data/sqlite_inventory_repository.dart';
import 'package:erp_pdv_app/modules/estoque/domain/entities/inventory_adjustment_input.dart';
import 'package:erp_pdv_app/modules/estoque/domain/entities/inventory_item.dart';
import 'package:erp_pdv_app/modules/estoque/domain/entities/inventory_movement.dart';
import 'package:erp_pdv_app/modules/produtos/data/datasources/products_remote_datasource.dart';
import 'package:erp_pdv_app/modules/produtos/data/models/remote_product_record.dart';
import 'package:erp_pdv_app/modules/produtos/data/sqlite_product_repository.dart';
import 'package:erp_pdv_app/modules/produtos/domain/entities/product.dart';
import 'package:erp_pdv_app/modules/vendas/domain/entities/sale_enums.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Compras leitura usa API primeiro', () async {
    final local = _FakeLocalPurchaseRepository();
    final remote = _FakePurchasesRemoteDatasource(
      records: [_remotePurchase('purchase-remote', 'Compra remota')],
    );
    final repository = _purchaseRepository(local: local, remote: remote);

    final purchases = await repository.search();

    expect(purchases.map((purchase) => purchase.remoteId), ['purchase-remote']);
    expect(remote.listCalls, 1);
    expect(local.searchCalls, 0);
    expect(local.cachedRemoteIds, ['purchase-remote']);
  });

  test('Compras usa cache local somente quando API falha', () async {
    final local = _FakeLocalPurchaseRepository([
      _purchase(id: 1, remoteId: 'purchase-cache', supplierName: 'Cache'),
    ]);
    final repository = _purchaseRepository(
      local: local,
      remote: const _FakePurchasesRemoteDatasource(throwOnList: true),
    );

    final purchases = await repository.search();

    expect(purchases.map((purchase) => purchase.remoteId), ['purchase-cache']);
    expect(local.searchCalls, 1);
  });

  test(
    'Compras falha remota de escrita nao vira sucesso local falso',
    () async {
      final local = _FakeLocalPurchaseRepository();
      final repository = _purchaseRepository(
        local: local,
        remote: const _FakePurchasesRemoteDatasource(throwOnCreate: true),
      );

      await expectLater(
        repository.create(_purchaseInput()),
        throwsA(isA<NetworkRequestException>()),
      );
      expect(local.createCalls, 0);
    },
  );

  test('Estoque usa snapshot remoto de produtos quando disponivel', () async {
    final localInventory = _FakeLocalInventoryRepository([
      _inventoryItem(productName: 'Produto cache'),
    ]);
    final localProducts = _FakeLocalProductRepository();
    final remoteProducts = _FakeProductsRemoteDatasource(
      records: [_remoteProduct('product-1', 'Produto remoto')],
    );
    final repository = InventoryRepositoryImpl(
      localRepository: localInventory,
      localProductRepository: localProducts,
      productsRemoteDatasource: remoteProducts,
      operationalContext: _remoteOperationalContext(),
      dataAccessPolicy: DataAccessPolicy.fromMode(
        AppDataMode.futureRemoteReady,
      ),
    );

    final items = await repository.listItems();

    expect(items.single.productName, 'Produto cache');
    expect(remoteProducts.listCalls, 1);
    expect(localProducts.upsertedRemoteIds, ['product-1']);
  });

  test(
    'Estoque sem endpoint dedicado permanece local com timeout seguro',
    () async {
      final repository = InventoryRepositoryImpl(
        localRepository: _FakeLocalInventoryRepository([
          _inventoryItem(productName: 'Produto local'),
        ]),
      );

      final items = await repository.listItems();

      expect(items.single.productName, 'Produto local');
    },
  );

  test('Custos nao usam financial-events como contrato falso de ERP', () {
    expect(CostRepositoryImpl.hasCompatibleRemoteCostContract, isFalse);
  });

  test('Provider de compras propaga erro e nao fica carregando', () async {
    final container = ProviderContainer(
      overrides: [
        purchaseRepositoryProvider.overrideWithValue(
          _FailingPurchaseRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);

    await expectLater(
      container.read(purchaseListProvider.future),
      throwsA(isA<StateError>()),
    );
    expect(container.read(purchaseListProvider).hasError, isTrue);
  });
}

PurchasesRepositoryImpl _purchaseRepository({
  required _FakeLocalPurchaseRepository local,
  required PurchasesRemoteDatasource remote,
}) {
  return PurchasesRepositoryImpl(
    localRepository: local,
    remoteDatasource: remote,
    operationalContext: _remoteOperationalContext(),
    dataAccessPolicy: DataAccessPolicy.fromMode(AppDataMode.futureRemoteReady),
  );
}

AppOperationalContext _remoteOperationalContext() {
  return AppOperationalContext(
    environment: const AppEnvironment.localDefault().copyWith(
      dataMode: AppDataMode.futureRemoteReady,
      remoteSyncEnabled: true,
    ),
    session: AppSession(
      scope: SessionScope.authenticatedRemote,
      user: const AppUser(
        localId: 1,
        remoteId: 'user-1',
        displayName: 'Operador',
        email: null,
        roleLabel: 'Operador',
        kind: AppUserKind.remoteAuthenticated,
      ),
      company: const CompanyContext(
        localId: 1,
        remoteId: 'company-1',
        displayName: 'Empresa',
        legalName: 'Empresa',
        documentNumber: null,
        licensePlan: 'pro',
        licenseStatus: 'active',
        syncEnabled: true,
      ),
      startedAt: DateTime(2026, 4, 26, 10),
      isOfflineFallback: false,
    ),
  );
}

Purchase _purchase({
  required int id,
  required String remoteId,
  required String supplierName,
}) {
  final now = DateTime(2026, 4, 26, 10);
  return Purchase(
    id: id,
    uuid: 'purchase-$id',
    supplierId: 1,
    supplierName: supplierName,
    documentNumber: null,
    notes: null,
    purchasedAt: now,
    dueDate: null,
    paymentMethod: PaymentMethod.cash,
    status: PurchaseStatus.recebida,
    subtotalCents: 1000,
    discountCents: 0,
    surchargeCents: 0,
    freightCents: 0,
    finalAmountCents: 1000,
    paidAmountCents: 0,
    pendingAmountCents: 1000,
    createdAt: now,
    updatedAt: now,
    cancelledAt: null,
    itemsCount: 1,
    remoteId: remoteId,
  );
}

RemotePurchaseRecord _remotePurchase(String remoteId, String supplierName) {
  final now = DateTime(2026, 4, 26, 10);
  return RemotePurchaseRecord(
    remoteId: remoteId,
    localUuid: 'local-$remoteId',
    remoteSupplierId: 'supplier-remote',
    supplierLocalUuid: null,
    supplierName: supplierName,
    documentNumber: null,
    notes: null,
    purchasedAt: now,
    dueDate: null,
    paymentMethod: PaymentMethod.cash,
    status: PurchaseStatus.recebida,
    subtotalCents: 1000,
    discountCents: 0,
    surchargeCents: 0,
    freightCents: 0,
    finalAmountCents: 1000,
    paidAmountCents: 0,
    pendingAmountCents: 1000,
    canceledAt: null,
    createdAt: now,
    updatedAt: now,
    items: const [],
    payments: const [],
  );
}

PurchaseUpsertInput _purchaseInput() {
  return PurchaseUpsertInput(
    supplierId: 1,
    purchasedAt: DateTime(2026, 4, 26, 10),
    items: const [],
    discountCents: 0,
    surchargeCents: 0,
    freightCents: 0,
    initialPaidAmountCents: 0,
  );
}

InventoryItem _inventoryItem({required String productName}) {
  return InventoryItem(
    productId: 1,
    productVariantId: null,
    productName: productName,
    sku: null,
    variantColorLabel: null,
    variantSizeLabel: null,
    unitMeasure: 'un',
    currentStockMil: 1000,
    minimumStockMil: 0,
    reorderPointMil: null,
    allowNegativeStock: false,
    costCents: 100,
    salePriceCents: 200,
    isActive: true,
    updatedAt: DateTime(2026, 4, 26, 10),
  );
}

RemoteProductRecord _remoteProduct(String remoteId, String name) {
  final now = DateTime(2026, 4, 26, 10);
  return RemoteProductRecord(
    remoteId: remoteId,
    localUuid: 'local-$remoteId',
    remoteCategoryId: null,
    name: name,
    description: null,
    barcode: null,
    productType: 'unidade',
    niche: ProductNiches.food,
    catalogType: ProductCatalogTypes.simple,
    modelName: null,
    variantLabel: null,
    unitMeasure: 'un',
    costCents: 100,
    manualCostCents: 100,
    costSource: ProductCostSource.manual,
    variableCostSnapshotCents: null,
    estimatedGrossMarginCents: null,
    estimatedGrossMarginPercentBasisPoints: null,
    lastCostUpdatedAt: now,
    salePriceCents: 200,
    stockMil: 1000,
    isActive: true,
    createdAt: now,
    updatedAt: now,
    deletedAt: null,
  );
}

class _FakeLocalPurchaseRepository extends SqlitePurchaseRepository {
  _FakeLocalPurchaseRepository([List<Purchase> initial = const <Purchase>[]])
    : _purchases = {for (final purchase in initial) purchase.id: purchase},
      super(AppDatabase.instance, _remoteOperationalContext());

  final Map<int, Purchase> _purchases;
  final cachedRemoteIds = <String>[];
  int searchCalls = 0;
  int createCalls = 0;

  @override
  Future<List<Purchase>> search({
    String query = '',
    PurchaseStatus? status,
    int? supplierId,
  }) async {
    searchCalls++;
    return _purchases.values.toList(growable: false);
  }

  @override
  Future<Purchase?> cacheRemoteSnapshot(RemotePurchaseRecord remote) async {
    cachedRemoteIds.add(remote.remoteId);
    final purchase = _purchase(
      id: _purchases.length + 1,
      remoteId: remote.remoteId,
      supplierName: remote.supplierName,
    );
    _purchases[purchase.id] = purchase;
    return purchase;
  }

  @override
  Future<RemotePurchaseRecord> buildRemoteRecordFromInput(
    PurchaseUpsertInput input, {
    String remoteId = '',
    String? localUuid,
    DateTime? createdAt,
  }) async {
    return _remotePurchase(remoteId.isEmpty ? 'draft' : remoteId, 'Fornecedor');
  }

  @override
  Future<int> create(PurchaseUpsertInput input) async {
    createCalls++;
    final id = _purchases.length + 1;
    _purchases[id] = _purchase(
      id: id,
      remoteId: 'local-created',
      supplierName: 'Local',
    );
    return id;
  }

  @override
  Future<PurchaseSyncPayload?> findPurchaseForSync(int purchaseId) async {
    return null;
  }

  @override
  Future<PurchaseDetail> fetchDetail(int purchaseId) async {
    final purchase = _purchases[purchaseId];
    if (purchase == null) {
      throw const ValidationException('Compra nao encontrada.');
    }
    return PurchaseDetail(
      purchase: purchase,
      items: const [],
      payments: const [],
    );
  }
}

class _FakePurchasesRemoteDatasource implements PurchasesRemoteDatasource {
  const _FakePurchasesRemoteDatasource({
    this.records = const <RemotePurchaseRecord>[],
    this.throwOnList = false,
    this.throwOnCreate = false,
  });

  final List<RemotePurchaseRecord> records;
  final bool throwOnList;
  final bool throwOnCreate;

  static int _listCalls = 0;
  int get listCalls => _listCalls;

  @override
  EndpointConfig get endpointConfig => const EndpointConfig.localDevelopment();

  @override
  String get featureKey => 'purchases';

  @override
  bool get requiresAuthentication => true;

  @override
  Future<bool> canReachRemote() async => true;

  @override
  Future<RemotePurchaseRecord> create(RemotePurchaseRecord record) async {
    if (throwOnCreate) {
      throw const NetworkRequestException('Falha remota');
    }
    return _remotePurchase('created-remote', 'Fornecedor remoto');
  }

  @override
  Future<RemoteFeatureDiagnostic> fetchDiagnostic() {
    throw UnimplementedError();
  }

  @override
  Future<RemotePurchaseRecord> fetchById(String remoteId) async {
    return records.firstWhere((record) => record.remoteId == remoteId);
  }

  @override
  Future<List<RemotePurchaseRecord>> listAll() async {
    _listCalls++;
    if (throwOnList) {
      throw const NetworkRequestException('Falha remota');
    }
    return records;
  }

  @override
  Future<RemotePurchaseRecord> update(
    String remoteId,
    RemotePurchaseRecord record,
  ) async {
    return record;
  }
}

class _FakeLocalInventoryRepository extends SqliteInventoryRepository {
  _FakeLocalInventoryRepository(this.items)
    : super.forDatabase(databaseLoader: () => AppDatabase.instance.database);

  final List<InventoryItem> items;

  @override
  Future<List<InventoryItem>> listItems({
    String query = '',
    InventoryListFilter filter = InventoryListFilter.all,
  }) async {
    return items;
  }

  @override
  Future<void> adjustStock(InventoryAdjustmentInput input) async {}

  @override
  Future<InventoryItem?> findItem({
    required int productId,
    int? productVariantId,
  }) async {
    return items.firstOrNull;
  }

  @override
  Future<List<InventoryMovement>> listMovements({
    int? productId,
    int? productVariantId,
    bool includeVariantsForProduct = false,
    InventoryMovementType? movementType,
    DateTime? createdFrom,
    DateTime? createdTo,
    int limit = 300,
  }) async {
    return const [];
  }
}

class _FakeLocalProductRepository extends SqliteProductRepository {
  _FakeLocalProductRepository()
    : super(AppDatabase.instance, categoryRepository: null);

  final upsertedRemoteIds = <String>[];

  @override
  Future<void> upsertFromRemote(RemoteProductRecord remote) async {
    upsertedRemoteIds.add(remote.remoteId);
  }
}

class _FakeProductsRemoteDatasource implements ProductsRemoteDatasource {
  const _FakeProductsRemoteDatasource({this.records = const []});

  final List<RemoteProductRecord> records;
  static int _listCalls = 0;
  int get listCalls => _listCalls;

  @override
  EndpointConfig get endpointConfig => const EndpointConfig.localDevelopment();

  @override
  String get featureKey => 'products';

  @override
  bool get requiresAuthentication => true;

  @override
  Future<bool> canReachRemote() async => true;

  @override
  Future<RemoteProductRecord> create(RemoteProductRecord record) async =>
      record;

  @override
  Future<void> delete(String remoteId) async {}

  @override
  Future<RemoteFeatureDiagnostic> fetchDiagnostic() {
    throw UnimplementedError();
  }

  @override
  Future<RemoteProductRecord> fetchById(String remoteId) async {
    return records.firstWhere((record) => record.remoteId == remoteId);
  }

  @override
  Future<List<RemoteProductRecord>> listAll() async {
    _listCalls++;
    return records;
  }

  @override
  Future<RemoteProductRecord> update(
    String remoteId,
    RemoteProductRecord record,
  ) async {
    return record;
  }
}

class _FailingPurchaseRepository implements PurchaseRepository {
  @override
  Future<void> cancel(int purchaseId, {String? reason}) async {}

  @override
  Future<int> create(PurchaseUpsertInput input) async => 1;

  @override
  Future<PurchaseDetail> fetchDetail(int purchaseId) {
    throw UnimplementedError();
  }

  @override
  Future<PurchaseDetail> registerPayment(PurchasePaymentInput input) {
    throw UnimplementedError();
  }

  @override
  Future<List<Purchase>> search({
    String query = '',
    PurchaseStatus? status,
    int? supplierId,
  }) async {
    throw StateError('falha compra');
  }

  @override
  Future<void> update(int id, PurchaseUpsertInput input) async {}
}
