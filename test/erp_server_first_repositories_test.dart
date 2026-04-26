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
import 'package:erp_pdv_app/modules/categorias/data/categories_repository_impl.dart';
import 'package:erp_pdv_app/modules/categorias/data/datasources/categories_remote_datasource.dart';
import 'package:erp_pdv_app/modules/categorias/data/models/remote_category_record.dart';
import 'package:erp_pdv_app/modules/categorias/data/sqlite_category_repository.dart';
import 'package:erp_pdv_app/modules/categorias/domain/entities/category.dart';
import 'package:erp_pdv_app/modules/fornecedores/data/datasources/suppliers_remote_datasource.dart';
import 'package:erp_pdv_app/modules/fornecedores/data/models/remote_supplier_record.dart';
import 'package:erp_pdv_app/modules/fornecedores/data/sqlite_supplier_repository.dart';
import 'package:erp_pdv_app/modules/fornecedores/data/suppliers_repository_impl.dart';
import 'package:erp_pdv_app/modules/fornecedores/domain/entities/supplier.dart';
import 'package:erp_pdv_app/modules/insumos/data/datasources/supplies_remote_datasource.dart';
import 'package:erp_pdv_app/modules/insumos/data/models/remote_supply_record.dart';
import 'package:erp_pdv_app/modules/insumos/data/sqlite_supply_repository.dart';
import 'package:erp_pdv_app/modules/insumos/data/supplies_repository_impl.dart';
import 'package:erp_pdv_app/modules/insumos/domain/entities/supply.dart';
import 'package:erp_pdv_app/modules/produtos/data/datasources/products_remote_datasource.dart';
import 'package:erp_pdv_app/modules/produtos/data/models/remote_product_record.dart';
import 'package:erp_pdv_app/modules/produtos/data/products_repository_impl.dart';
import 'package:erp_pdv_app/modules/produtos/data/sqlite_product_repository.dart';
import 'package:erp_pdv_app/modules/produtos/domain/entities/product.dart';
import 'package:erp_pdv_app/modules/produtos/domain/repositories/product_repository.dart';
import 'package:erp_pdv_app/modules/produtos/presentation/providers/product_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Produtos lista retorna remoto quando API responde', () async {
    final localProducts = _FakeLocalProductRepository([
      _product(id: 1, name: 'Produto cache antigo', remoteId: 'product-old'),
    ]);
    final repository = ProductsRepositoryImpl(
      localRepository: localProducts,
      localCategoryRepository: _FakeLocalCategoryRepository(),
      remoteDatasource: _FakeProductsRemoteDatasource(
        records: [_remoteProduct('product-remote', 'Produto remoto')],
      ),
      operationalContext: _remoteOperationalContext(),
      dataAccessPolicy: DataAccessPolicy.fromMode(
        AppDataMode.futureRemoteReady,
      ),
    );

    final products = await repository.search();

    expect(products.map((product) => product.name), ['Produto remoto']);
    expect(localProducts.searchCount, 0);
    expect(localProducts.upsertedRemoteIds, ['product-remote']);
  });

  test('Produtos usa cache local somente quando API falha', () async {
    final localProducts = _FakeLocalProductRepository([
      _product(id: 1, name: 'Produto em cache', remoteId: 'product-cache'),
    ]);
    final repository = ProductsRepositoryImpl(
      localRepository: localProducts,
      localCategoryRepository: _FakeLocalCategoryRepository(),
      remoteDatasource: const _FakeProductsRemoteDatasource(throwOnList: true),
      operationalContext: _remoteOperationalContext(),
      dataAccessPolicy: DataAccessPolicy.fromMode(
        AppDataMode.futureRemoteReady,
      ),
    );

    final products = await repository.search();

    expect(products.map((product) => product.name), ['Produto em cache']);
    expect(localProducts.searchCount, 1);
  });

  test('Categorias leitura e escrita usam API primeiro', () async {
    final localCategories = _FakeLocalCategoryRepository();
    final remoteCategories = _FakeCategoriesRemoteDatasource(
      records: [_remoteCategory('category-remote', 'Categoria remota')],
    );
    final repository = CategoriesRepositoryImpl(
      localRepository: localCategories,
      remoteDatasource: remoteCategories,
      operationalContext: _remoteOperationalContext(),
      dataAccessPolicy: DataAccessPolicy.fromMode(
        AppDataMode.futureRemoteReady,
      ),
    );

    final categories = await repository.search();
    final createdId = await repository.create(
      const CategoryInput(name: 'Nova categoria'),
    );

    expect(categories.map((category) => category.name), ['Categoria remota']);
    expect(createdId, greaterThan(0));
    expect(remoteCategories.listCalls, 1);
    expect(remoteCategories.createCalls, 1);
    expect(localCategories.createCount, 0);
  });

  test('Falha de API em escrita ERP nao vira sucesso local falso', () async {
    final localCategories = _FakeLocalCategoryRepository();
    final repository = CategoriesRepositoryImpl(
      localRepository: localCategories,
      remoteDatasource: const _FakeCategoriesRemoteDatasource(
        throwOnCreate: true,
      ),
      operationalContext: _remoteOperationalContext(),
      dataAccessPolicy: DataAccessPolicy.fromMode(
        AppDataMode.futureRemoteReady,
      ),
    );

    await expectLater(
      repository.create(const CategoryInput(name: 'Falha remota')),
      throwsA(isA<NetworkRequestException>()),
    );
    expect(localCategories.createCount, 0);
    expect(localCategories.upsertedRemoteIds, isEmpty);
  });

  test('Fornecedores leitura usa API primeiro', () async {
    final localSuppliers = _FakeLocalSupplierRepository();
    final repository = SuppliersRepositoryImpl(
      localRepository: localSuppliers,
      remoteDatasource: _FakeSuppliersRemoteDatasource(
        records: [_remoteSupplier('supplier-remote', 'Fornecedor remoto')],
      ),
      operationalContext: _remoteOperationalContext(),
      dataAccessPolicy: DataAccessPolicy.fromMode(
        AppDataMode.futureRemoteReady,
      ),
    );

    final suppliers = await repository.search();

    expect(suppliers.map((supplier) => supplier.name), ['Fornecedor remoto']);
    expect(localSuppliers.searchCount, 0);
  });

  test('Insumos leitura usa API primeiro', () async {
    final localSupplies = _FakeLocalSupplyRepository();
    final repository = SuppliesRepositoryImpl(
      localRepository: localSupplies,
      remoteDatasource: _FakeSuppliesRemoteDatasource(
        records: [_remoteSupply('supply-remote', 'Insumo remoto')],
      ),
      operationalContext: _remoteOperationalContext(),
      dataAccessPolicy: DataAccessPolicy.fromMode(
        AppDataMode.futureRemoteReady,
      ),
    );

    final supplies = await repository.search();

    expect(supplies.map((supply) => supply.name), ['Insumo remoto']);
    expect(localSupplies.searchCount, 0);
  });

  test('provider de produto propaga erro em vez de ficar carregando', () async {
    final container = ProviderContainer(
      overrides: [
        productRepositoryProvider.overrideWithValue(
          _FailingProductRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);

    await expectLater(
      container.read(productListProvider.future),
      throwsA(isA<StateError>()),
    );
    expect(container.read(productListProvider).hasError, isTrue);
  });
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

Product _product({
  required int id,
  required String name,
  required String remoteId,
}) {
  final now = DateTime(2026, 4, 26, 10);
  return Product(
    id: id,
    uuid: 'product-$id',
    name: name,
    description: null,
    categoryId: null,
    categoryName: null,
    barcode: null,
    primaryPhotoPath: null,
    productType: 'unidade',
    niche: ProductNiches.food,
    catalogType: ProductCatalogTypes.simple,
    modelName: null,
    variantLabel: null,
    baseProductId: null,
    baseProductName: null,
    unitMeasure: 'un',
    costCents: 100,
    manualCostCents: 100,
    costSource: ProductCostSource.manual,
    salePriceCents: 200,
    stockMil: 1000,
    isActive: true,
    createdAt: now,
    updatedAt: now,
    deletedAt: null,
    remoteId: remoteId,
  );
}

Category _category({
  required int id,
  required String name,
  required String remoteId,
}) {
  final now = DateTime(2026, 4, 26, 10);
  return Category(
    id: id,
    uuid: 'category-$id',
    name: name,
    description: null,
    isActive: true,
    createdAt: now,
    updatedAt: now,
    deletedAt: null,
    remoteId: remoteId,
  );
}

Supplier _supplier({
  required int id,
  required String name,
  required String remoteId,
}) {
  final now = DateTime(2026, 4, 26, 10);
  return Supplier(
    id: id,
    uuid: 'supplier-$id',
    name: name,
    tradeName: null,
    phone: null,
    email: null,
    address: null,
    document: null,
    contactPerson: null,
    notes: null,
    isActive: true,
    createdAt: now,
    updatedAt: now,
    deletedAt: null,
    remoteId: remoteId,
  );
}

Supply _supply({required int id, required String name}) {
  final now = DateTime(2026, 4, 26, 10);
  return Supply(
    id: id,
    uuid: 'supply-$id',
    name: name,
    sku: null,
    unitType: SupplyUnitTypes.unit,
    purchaseUnitType: SupplyUnitTypes.unit,
    conversionFactor: 1,
    lastPurchasePriceCents: 100,
    averagePurchasePriceCents: null,
    currentStockMil: 1000,
    minimumStockMil: null,
    defaultSupplierId: null,
    defaultSupplierName: null,
    isActive: true,
    createdAt: now,
    updatedAt: now,
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
    lastCostUpdatedAt: null,
    salePriceCents: 200,
    stockMil: 1000,
    isActive: true,
    createdAt: now,
    updatedAt: now,
    deletedAt: null,
  );
}

RemoteCategoryRecord _remoteCategory(String remoteId, String name) {
  final now = DateTime(2026, 4, 26, 10);
  return RemoteCategoryRecord(
    remoteId: remoteId,
    localUuid: 'local-$remoteId',
    name: name,
    description: null,
    isActive: true,
    createdAt: now,
    updatedAt: now,
    deletedAt: null,
  );
}

RemoteSupplierRecord _remoteSupplier(String remoteId, String name) {
  final now = DateTime(2026, 4, 26, 10);
  return RemoteSupplierRecord(
    remoteId: remoteId,
    localUuid: 'local-$remoteId',
    name: name,
    tradeName: null,
    phone: null,
    email: null,
    address: null,
    document: null,
    contactPerson: null,
    notes: null,
    isActive: true,
    createdAt: now,
    updatedAt: now,
    deletedAt: null,
  );
}

RemoteSupplyRecord _remoteSupply(String remoteId, String name) {
  final now = DateTime(2026, 4, 26, 10);
  return RemoteSupplyRecord(
    remoteId: remoteId,
    localUuid: 'local-$remoteId',
    remoteDefaultSupplierId: null,
    name: name,
    sku: null,
    unitType: SupplyUnitTypes.unit,
    purchaseUnitType: SupplyUnitTypes.unit,
    conversionFactor: 1,
    lastPurchasePriceCents: 100,
    averagePurchasePriceCents: null,
    currentStockMil: 1000,
    minimumStockMil: null,
    isActive: true,
    createdAt: now,
    updatedAt: now,
    deletedAt: null,
  );
}

class _FakeLocalProductRepository extends SqliteProductRepository {
  _FakeLocalProductRepository([List<Product> initial = const <Product>[]])
    : _productsByRemoteId = {
        for (final product in initial) product.remoteId!: product,
      },
      super(
        AppDatabase.instance,
        categoryRepository: _FakeLocalCategoryRepository(),
      );

  final Map<String, Product> _productsByRemoteId;
  final upsertedRemoteIds = <String>[];
  int searchCount = 0;

  @override
  Future<List<Product>> search({String query = ''}) async {
    searchCount++;
    return _productsByRemoteId.values.toList(growable: false);
  }

  @override
  Future<void> upsertFromRemote(RemoteProductRecord remote) async {
    upsertedRemoteIds.add(remote.remoteId);
    _productsByRemoteId[remote.remoteId] = _product(
      id: _productsByRemoteId.length + 1,
      name: remote.name,
      remoteId: remote.remoteId,
    );
  }

  @override
  Future<Product?> findByRemoteId(String remoteId) async {
    return _productsByRemoteId[remoteId];
  }
}

class _FakeLocalCategoryRepository extends SqliteCategoryRepository {
  _FakeLocalCategoryRepository([List<Category> initial = const <Category>[]])
    : _categoriesByRemoteId = {
        for (final category in initial) category.remoteId!: category,
      },
      super(AppDatabase.instance);

  final Map<String, Category> _categoriesByRemoteId;
  final upsertedRemoteIds = <String>[];
  int createCount = 0;

  @override
  Future<int> create(CategoryInput input) async {
    createCount++;
    return 999;
  }

  @override
  Future<List<Category>> search({String query = ''}) async {
    return _categoriesByRemoteId.values.toList(growable: false);
  }

  @override
  Future<void> upsertFromRemote(RemoteCategoryRecord remote) async {
    upsertedRemoteIds.add(remote.remoteId);
    _categoriesByRemoteId[remote.remoteId] = _category(
      id: _categoriesByRemoteId.length + 1,
      name: remote.name,
      remoteId: remote.remoteId,
    );
  }

  @override
  Future<Category?> findByRemoteId(String remoteId) async {
    return _categoriesByRemoteId[remoteId];
  }
}

class _FakeLocalSupplierRepository extends SqliteSupplierRepository {
  _FakeLocalSupplierRepository() : super(AppDatabase.instance);

  final _suppliersByRemoteId = <String, Supplier>{};
  int searchCount = 0;

  @override
  Future<List<Supplier>> search({String query = ''}) async {
    searchCount++;
    return _suppliersByRemoteId.values.toList(growable: false);
  }

  @override
  Future<void> upsertFromRemote(RemoteSupplierRecord remote) async {
    _suppliersByRemoteId[remote.remoteId] = _supplier(
      id: _suppliersByRemoteId.length + 1,
      name: remote.name,
      remoteId: remote.remoteId,
    );
  }

  @override
  Future<Supplier?> findByRemoteId(String remoteId) async {
    return _suppliersByRemoteId[remoteId];
  }
}

class _FakeLocalSupplyRepository extends SqliteSupplyRepository {
  _FakeLocalSupplyRepository() : super(AppDatabase.instance);

  final _remoteIdsByLocalId = <int, String>{};
  final _suppliesByRemoteId = <String, Supply>{};
  int searchCount = 0;

  @override
  Future<List<Supply>> search({
    String query = '',
    bool activeOnly = false,
  }) async {
    searchCount++;
    return _suppliesByRemoteId.values.toList(growable: false);
  }

  @override
  Future<void> upsertFromRemote(RemoteSupplyRecord remote) async {
    final id = _suppliesByRemoteId.length + 1;
    _remoteIdsByLocalId[id] = remote.remoteId;
    _suppliesByRemoteId[remote.remoteId] = _supply(id: id, name: remote.name);
  }

  @override
  Future<Supply?> findByRemoteId(String remoteId) async {
    return _suppliesByRemoteId[remoteId];
  }
}

class _FakeProductsRemoteDatasource implements ProductsRemoteDatasource {
  const _FakeProductsRemoteDatasource({
    this.records = const <RemoteProductRecord>[],
    this.throwOnList = false,
  });

  final List<RemoteProductRecord> records;
  final bool throwOnList;

  @override
  String get featureKey => 'products';

  @override
  EndpointConfig get endpointConfig => const EndpointConfig();

  @override
  bool get requiresAuthentication => true;

  @override
  Future<bool> canReachRemote() async => true;

  @override
  Future<List<RemoteProductRecord>> listAll() async {
    if (throwOnList) {
      throw const NetworkRequestException('products offline');
    }
    return records;
  }

  @override
  Future<RemoteProductRecord> fetchById(String remoteId) async =>
      records.firstWhere((record) => record.remoteId == remoteId);

  @override
  Future<RemoteProductRecord> create(RemoteProductRecord record) async =>
      record;

  @override
  Future<RemoteProductRecord> update(
    String remoteId,
    RemoteProductRecord record,
  ) async => record;

  @override
  Future<void> delete(String remoteId) async {}

  @override
  Future<RemoteFeatureDiagnostic> fetchDiagnostic() async =>
      _diagnostic(featureKey);
}

class _FakeCategoriesRemoteDatasource implements CategoriesRemoteDatasource {
  const _FakeCategoriesRemoteDatasource({
    this.records = const <RemoteCategoryRecord>[],
    this.throwOnCreate = false,
  });

  final List<RemoteCategoryRecord> records;
  final bool throwOnCreate;
  static int _createCounter = 0;

  int get listCalls => _CategoryRemoteCounters.listCalls;
  int get createCalls => _CategoryRemoteCounters.createCalls;

  @override
  String get featureKey => 'categories';

  @override
  EndpointConfig get endpointConfig => const EndpointConfig();

  @override
  bool get requiresAuthentication => true;

  @override
  Future<bool> canReachRemote() async => true;

  @override
  Future<List<RemoteCategoryRecord>> listAll() async {
    _CategoryRemoteCounters.listCalls++;
    return records;
  }

  @override
  Future<RemoteCategoryRecord> create(RemoteCategoryRecord record) async {
    _CategoryRemoteCounters.createCalls++;
    if (throwOnCreate) {
      throw const NetworkRequestException('category create failed');
    }
    _createCounter++;
    return RemoteCategoryRecord(
      remoteId: 'created-category-$_createCounter',
      localUuid: record.localUuid,
      name: record.name,
      description: record.description,
      isActive: record.isActive,
      createdAt: record.createdAt,
      updatedAt: record.updatedAt,
      deletedAt: record.deletedAt,
    );
  }

  @override
  Future<RemoteCategoryRecord> fetchById(String remoteId) async =>
      records.firstWhere((record) => record.remoteId == remoteId);

  @override
  Future<RemoteCategoryRecord> update(
    String remoteId,
    RemoteCategoryRecord record,
  ) async => record;

  @override
  Future<void> delete(String remoteId) async {}

  @override
  Future<RemoteFeatureDiagnostic> fetchDiagnostic() async =>
      _diagnostic(featureKey);
}

abstract final class _CategoryRemoteCounters {
  static int listCalls = 0;
  static int createCalls = 0;
}

class _FakeSuppliersRemoteDatasource implements SuppliersRemoteDatasource {
  const _FakeSuppliersRemoteDatasource({
    this.records = const <RemoteSupplierRecord>[],
  });

  final List<RemoteSupplierRecord> records;

  @override
  String get featureKey => 'suppliers';

  @override
  EndpointConfig get endpointConfig => const EndpointConfig();

  @override
  bool get requiresAuthentication => true;

  @override
  Future<bool> canReachRemote() async => true;

  @override
  Future<List<RemoteSupplierRecord>> listAll() async => records;

  @override
  Future<RemoteSupplierRecord> fetchById(String remoteId) async =>
      records.firstWhere((record) => record.remoteId == remoteId);

  @override
  Future<RemoteSupplierRecord> create(RemoteSupplierRecord record) async =>
      record;

  @override
  Future<RemoteSupplierRecord> update(
    String remoteId,
    RemoteSupplierRecord record,
  ) async => record;

  @override
  Future<void> delete(String remoteId) async {}

  @override
  Future<RemoteFeatureDiagnostic> fetchDiagnostic() async =>
      _diagnostic(featureKey);
}

class _FakeSuppliesRemoteDatasource implements SuppliesRemoteDatasource {
  const _FakeSuppliesRemoteDatasource({
    this.records = const <RemoteSupplyRecord>[],
  });

  final List<RemoteSupplyRecord> records;

  @override
  String get featureKey => 'supplies';

  @override
  EndpointConfig get endpointConfig => const EndpointConfig();

  @override
  bool get requiresAuthentication => true;

  @override
  Future<bool> canReachRemote() async => true;

  @override
  Future<List<RemoteSupplyRecord>> listAll() async => records;

  @override
  Future<RemoteSupplyRecord> fetchById(String remoteId) async =>
      records.firstWhere((record) => record.remoteId == remoteId);

  @override
  Future<RemoteSupplyRecord> create(RemoteSupplyRecord record) async => record;

  @override
  Future<RemoteSupplyRecord> update(
    String remoteId,
    RemoteSupplyRecord record,
  ) async => record;

  @override
  Future<void> delete(String remoteId) async {}

  @override
  Future<RemoteFeatureDiagnostic> fetchDiagnostic() async =>
      _diagnostic(featureKey);
}

class _FailingProductRepository implements ProductRepository {
  @override
  Future<List<Product>> search({String query = ''}) async {
    throw StateError('Falha controlada');
  }

  @override
  Future<List<Product>> searchAvailable({String query = ''}) async {
    throw StateError('Falha controlada');
  }

  @override
  Future<int> create(ProductInput input) async => throw UnimplementedError();

  @override
  Future<void> update(int id, ProductInput input) async =>
      throw UnimplementedError();

  @override
  Future<void> delete(int id) async => throw UnimplementedError();
}

RemoteFeatureDiagnostic _diagnostic(String featureKey) {
  return RemoteFeatureDiagnostic(
    featureKey: featureKey,
    displayName: featureKey,
    reachable: true,
    requiresAuthentication: true,
    isAuthenticated: true,
    endpointLabel: 'teste',
    summary: 'ok',
    lastCheckedAt: DateTime(2026, 4, 26, 10),
    capabilities: const <String>[],
  );
}
