import 'package:erp_pdv_app/app/core/app_context/app_operational_context.dart';
import 'package:erp_pdv_app/app/core/app_context/data_access_policy.dart';
import 'package:erp_pdv_app/app/core/config/app_data_mode.dart';
import 'package:erp_pdv_app/app/core/config/app_environment.dart';
import 'package:erp_pdv_app/app/core/database/app_database.dart';
import 'package:erp_pdv_app/app/core/network/endpoint_config.dart';
import 'package:erp_pdv_app/app/core/network/remote_feature_diagnostic.dart';
import 'package:erp_pdv_app/app/core/session/app_session.dart';
import 'package:erp_pdv_app/app/core/session/app_user.dart';
import 'package:erp_pdv_app/app/core/session/company_context.dart';
import 'package:erp_pdv_app/modules/categorias/data/sqlite_category_repository.dart';
import 'package:erp_pdv_app/modules/produtos/data/datasources/products_remote_datasource.dart';
import 'package:erp_pdv_app/modules/produtos/data/models/remote_product_record.dart';
import 'package:erp_pdv_app/modules/produtos/data/products_repository_impl.dart';
import 'package:erp_pdv_app/modules/produtos/data/sqlite_product_repository.dart';
import 'package:erp_pdv_app/modules/produtos/domain/entities/product.dart';
import 'package:erp_pdv_app/modules/vendas/presentation/providers/sales_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'test_tenant_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('server-first cria produto simples sem grade sem regredir', () async {
    final fixture = await _openFixture();
    addTearDown(fixture.dispose);
    final remoteDatasource = _FakeProductsRemoteDatasource();
    final repository = fixture.createServerFirstRepository(remoteDatasource);

    final productId = await repository.create(
      _simpleProductInput(name: 'Cafe coado'),
    );

    final savedProduct = await fixture.localRepository.findById(productId);

    expect(savedProduct, isNotNull);
    expect(savedProduct!.name, 'Cafe coado');
    expect(savedProduct.catalogType, ProductCatalogTypes.simple);
    expect(savedProduct.variants, isEmpty);
    expect(savedProduct.primaryPhotoPath, isNull);
    expect(remoteDatasource.createdRecords, hasLength(1));
    expect(remoteDatasource.createdRecords.single.name, 'Cafe coado');
    expect(
      remoteDatasource.createdRecords.single.catalogType,
      ProductCatalogTypes.simple,
    );
    expect(remoteDatasource.createdRecords.single.variants, isEmpty);
  });

  test(
    'server-first cria produto pai com grade e preserva nome e foto local',
    () async {
      final fixture = await _openFixture();
      addTearDown(fixture.dispose);
      final remoteDatasource = _FakeProductsRemoteDatasource();
      final repository = fixture.createServerFirstRepository(remoteDatasource);
      const photoPath = 'C:/tmp/tatuzin-thumb-create.jpg';

      final productId = await repository.create(
        _fashionProductInput(
          name: 'Camiseta Basic',
          photoPaths: const [photoPath],
        ),
      );

      final savedProduct = await fixture.localRepository.findById(productId);
      final savedPhotos = await fixture.localRepository.listProductPhotos(
        productId,
      );

      expect(savedProduct, isNotNull);
      expect(savedProduct!.name, 'Camiseta Basic');
      expect(savedProduct.primaryPhotoPath, photoPath);
      expect(savedProduct.hasPhoto, isTrue);
      expect(savedProduct.variants, hasLength(4));
      expect(
        savedProduct.variants.map((variant) => variant.sku),
        containsAll(const [
          'CAM-BASIC-M-PRETO',
          'CAM-BASIC-M-AZUL',
          'CAM-BASIC-G-PRETO',
          'CAM-BASIC-G-AZUL',
        ]),
      );
      expect(
        _variantDisplayNameFor(savedProduct, size: 'M', color: 'preto'),
        'M preto promocao',
      );
      expect(savedPhotos, hasLength(1));
      expect(savedPhotos.single.localPath, photoPath);
      expect(remoteDatasource.createdRecords, hasLength(1));
      expect(remoteDatasource.createdRecords.single.name, 'Camiseta Basic');
      expect(
        remoteDatasource.createdRecords.single.modelName,
        'Camiseta Basic',
      );
      expect(
        remoteDatasource.createdRecords.single.variantLabel,
        'Tamanho/Cor',
      );
      final remotePayload = remoteDatasource.createdRecords.single
          .toUpsertBody();
      final remoteVariants = remotePayload['variants'] as List<dynamic>;
      expect(
        remoteVariants.cast<Map<String, dynamic>>(),
        everyElement(isNot(contains('displayName'))),
      );
    },
  );

  test(
    'server-first atualiza produto com grade, mantem nome pai e persiste remocao da foto',
    () async {
      final fixture = await _openFixture();
      addTearDown(fixture.dispose);
      final remoteDatasource = _FakeProductsRemoteDatasource();
      final repository = fixture.createServerFirstRepository(remoteDatasource);

      final productId = await repository.create(
        _fashionProductInput(
          name: 'Camiseta Basic',
          photoPaths: const ['C:/tmp/tatuzin-thumb-old.jpg'],
        ),
      );

      await repository.update(
        productId,
        _fashionProductInput(
          name: 'Camiseta Basic Premium',
          photoPaths: const <String>[],
        ),
      );

      final updatedProduct = await fixture.localRepository.findById(productId);
      final updatedPhotos = await fixture.localRepository.listProductPhotos(
        productId,
      );

      expect(remoteDatasource.createCalls, 1);
      expect(remoteDatasource.updateCalls, 1);
      expect(updatedProduct, isNotNull);
      expect(updatedProduct!.name, 'Camiseta Basic Premium');
      expect(updatedProduct.primaryPhotoPath, isNull);
      expect(updatedProduct.hasPhoto, isFalse);
      expect(updatedProduct.variants, hasLength(4));
      expect(
        _variantDisplayNameFor(updatedProduct, size: 'M', color: 'preto'),
        'M preto promocao',
      );
      expect(updatedPhotos, isEmpty);
    },
  );

  test('snapshot remoto sem midia nao apaga foto local ja salva', () async {
    final fixture = await _openFixture();
    addTearDown(fixture.dispose);
    final remoteDatasource = _FakeProductsRemoteDatasource();
    final repository = fixture.createServerFirstRepository(remoteDatasource);
    const photoPath = 'C:/tmp/tatuzin-thumb-sync.jpg';

    final productId = await repository.create(
      _fashionProductInput(
        name: 'Camiseta Basic',
        photoPaths: const [photoPath],
      ),
    );

    final createdRemote = remoteDatasource.createdRecords.single;
    final pulledRemote = _remoteRecordFrom(
      createdRemote,
      remoteId: 'remote-product-1',
      name: 'Camiseta Basic Atualizada',
      updatedAt: DateTime(2030, 1, 1, 12),
    );

    await fixture.localRepository.upsertFromRemote(pulledRemote);

    final savedProduct = await fixture.localRepository.findById(productId);
    final savedPhotos = await fixture.localRepository.listProductPhotos(
      productId,
    );

    expect(savedProduct, isNotNull);
    expect(savedProduct!.name, 'Camiseta Basic Atualizada');
    expect(savedProduct.primaryPhotoPath, photoPath);
    expect(savedProduct.hasPhoto, isTrue);
    expect(savedPhotos, hasLength(1));
    expect(savedPhotos.single.localPath, photoPath);
  });

  test(
    'catalogo de vendas carrega a miniatura local apos salvar produto com grade',
    () async {
      final fixture = await _openFixture();
      addTearDown(fixture.dispose);
      final remoteDatasource = _FakeProductsRemoteDatasource();
      final repository = fixture.createServerFirstRepository(remoteDatasource);
      const photoPath = 'C:/tmp/tatuzin-thumb-sales.jpg';

      await repository.create(
        _fashionProductInput(
          name: 'Camiseta Basic',
          photoPaths: const [photoPath],
        ),
      );

      final container = fixture.createContainer();
      addTearDown(container.dispose);

      final entries = await container.read(salesCatalogProvider.future);

      expect(entries, hasLength(1));
      expect(entries.single.product.name, 'Camiseta Basic');
      expect(entries.single.product.primaryPhotoPath, photoPath);
      expect(entries.single.product.hasPhoto, isTrue);
      expect(entries.single.availableVariants, hasLength(4));
    },
  );
}

Future<_ProductVariantMediaFixture> _openFixture() async {
  final isolationKey =
      'product-variant-media-${DateTime.now().microsecondsSinceEpoch}';
  final appDatabase = AppDatabase.forIsolationKey(isolationKey);
  await appDatabase.database;
  return _ProductVariantMediaFixture(
    isolationKey: isolationKey,
    appDatabase: appDatabase,
    localRepository: SqliteProductRepository(appDatabase),
  );
}

class _ProductVariantMediaFixture {
  const _ProductVariantMediaFixture({
    required this.isolationKey,
    required this.appDatabase,
    required this.localRepository,
  });

  final String isolationKey;
  final AppDatabase appDatabase;
  final SqliteProductRepository localRepository;

  ProductsRepositoryImpl createServerFirstRepository(
    ProductsRemoteDatasource remoteDatasource,
  ) {
    return ProductsRepositoryImpl(
      localRepository: localRepository,
      localCategoryRepository: SqliteCategoryRepository(appDatabase),
      remoteDatasource: remoteDatasource,
      operationalContext: _remoteOperationalContext(
        companyRemoteId: isolationKey,
      ),
      dataAccessPolicy: DataAccessPolicy.fromMode(
        AppDataMode.futureRemoteReady,
      ),
    );
  }

  ProviderContainer createContainer() {
    final container = ProviderContainer(
      overrides: [
        ...testTenantBootstrapOverrides(),
        appDatabaseProvider.overrideWithValue(appDatabase),
      ],
    );
    setTestTenantSession(container, companyId: isolationKey);
    return container;
  }

  Future<void> dispose() async {
    await appDatabase.close();
    await AppDatabase.deleteDatabaseForIsolationKeyForTesting(isolationKey);
  }
}

ProductInput _fashionProductInput({
  required String name,
  required List<String> photoPaths,
}) {
  return ProductInput(
    name: name,
    photos: photoPaths
        .map(
          (photoPath) =>
              ProductPhotoInput(localPath: photoPath, isPrimary: true),
        )
        .toList(growable: false),
    variants: const [
      ProductVariantInput(
        sku: 'CAM-BASIC-M-PRETO',
        displayName: 'M preto promocao',
        colorLabel: 'preto',
        sizeLabel: 'M',
        stockMil: 3000,
      ),
      ProductVariantInput(
        sku: 'CAM-BASIC-M-AZUL',
        displayName: 'M / azul',
        colorLabel: 'azul',
        sizeLabel: 'M',
        stockMil: 3000,
      ),
      ProductVariantInput(
        sku: 'CAM-BASIC-G-PRETO',
        displayName: 'G / preto',
        colorLabel: 'preto',
        sizeLabel: 'G',
        stockMil: 3000,
      ),
      ProductVariantInput(
        sku: 'CAM-BASIC-G-AZUL',
        displayName: 'G / azul',
        colorLabel: 'azul',
        sizeLabel: 'G',
        stockMil: 3000,
      ),
    ],
    niche: ProductNiches.fashion,
    catalogType: ProductCatalogTypes.variant,
    unitMeasure: 'un',
    costCents: 4500,
    salePriceCents: 9900,
    stockMil: 0,
  );
}

ProductInput _simpleProductInput({required String name}) {
  return ProductInput(
    name: name,
    niche: ProductNiches.food,
    catalogType: ProductCatalogTypes.simple,
    unitMeasure: 'un',
    costCents: 250,
    salePriceCents: 990,
    stockMil: 1000,
  );
}

String? _variantDisplayNameFor(
  Product product, {
  required String size,
  required String color,
}) {
  final key =
      'fashion_variant_display_name:${_normalizeAttributeToken(size)}:${_normalizeAttributeToken(color)}';
  for (final attribute in product.variantAttributes) {
    if (attribute.key == key) {
      return attribute.value;
    }
  }
  return null;
}

String _normalizeAttributeToken(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
}

AppOperationalContext _remoteOperationalContext({
  required String companyRemoteId,
}) {
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
      company: CompanyContext(
        localId: 1,
        remoteId: companyRemoteId,
        displayName: 'Empresa',
        legalName: 'Empresa',
        documentNumber: null,
        licensePlan: 'pro',
        licenseStatus: 'active',
        syncEnabled: true,
      ),
      startedAt: DateTime(2026, 5, 15, 10),
      isOfflineFallback: false,
      clientInstanceId: 'device-1',
    ),
  );
}

class _FakeProductsRemoteDatasource implements ProductsRemoteDatasource {
  final createdRecords = <RemoteProductRecord>[];
  final updatedRecords = <RemoteProductRecord>[];

  int get createCalls => createdRecords.length;
  int get updateCalls => updatedRecords.length;

  @override
  EndpointConfig get endpointConfig => const EndpointConfig.localDevelopment();

  @override
  String get featureKey => 'products';

  @override
  bool get requiresAuthentication => true;

  @override
  Future<bool> canReachRemote() async => true;

  @override
  Future<RemoteProductRecord> create(RemoteProductRecord record) async {
    createdRecords.add(record);
    return _materializeRemoteRecord(
      remoteId: 'remote-product-${createdRecords.length}',
      record: record,
      updatedAt: DateTime(2026, 5, 15, 11, createdRecords.length),
    );
  }

  @override
  Future<void> delete(String remoteId) async {}

  @override
  Future<RemoteProductRecord> fetchById(String remoteId) async {
    final allRecords = [...createdRecords, ...updatedRecords];
    final matched = allRecords.where((record) => record.remoteId == remoteId);
    if (matched.isEmpty) {
      throw StateError('Produto remoto fake nao encontrado: $remoteId');
    }
    return matched.last;
  }

  @override
  Future<RemoteFeatureDiagnostic> fetchDiagnostic() async {
    return RemoteFeatureDiagnostic(
      featureKey: featureKey,
      displayName: 'Produtos',
      reachable: true,
      requiresAuthentication: true,
      isAuthenticated: true,
      endpointLabel: 'fake',
      summary: 'fake',
      lastCheckedAt: DateTime(2026, 5, 15, 10),
      capabilities: const ['create', 'update'],
    );
  }

  @override
  Future<List<RemoteProductRecord>> listAll() async => createdRecords;

  @override
  Future<RemoteProductRecord> update(
    String remoteId,
    RemoteProductRecord record,
  ) async {
    final updated = _materializeRemoteRecord(
      remoteId: remoteId,
      record: record,
      updatedAt: DateTime(2026, 5, 15, 12, updatedRecords.length + 1),
    );
    updatedRecords.add(updated);
    return updated;
  }

  RemoteProductRecord _materializeRemoteRecord({
    required String remoteId,
    required RemoteProductRecord record,
    required DateTime updatedAt,
  }) {
    return _remoteRecordFrom(record, remoteId: remoteId, updatedAt: updatedAt);
  }
}

RemoteProductRecord _remoteRecordFrom(
  RemoteProductRecord record, {
  required String remoteId,
  required DateTime updatedAt,
  String? name,
}) {
  return RemoteProductRecord(
    remoteId: remoteId,
    localUuid: record.localUuid,
    remoteCategoryId: record.remoteCategoryId,
    name: name ?? record.name,
    description: record.description,
    barcode: record.barcode,
    productType: record.productType,
    niche: record.niche,
    catalogType: record.catalogType,
    modelName: record.modelName,
    variantLabel: record.variantLabel,
    unitMeasure: record.unitMeasure,
    costCents: record.costCents,
    manualCostCents: record.manualCostCents,
    costSource: record.costSource,
    variableCostSnapshotCents: record.variableCostSnapshotCents,
    estimatedGrossMarginCents: record.estimatedGrossMarginCents,
    estimatedGrossMarginPercentBasisPoints:
        record.estimatedGrossMarginPercentBasisPoints,
    lastCostUpdatedAt: record.lastCostUpdatedAt,
    salePriceCents: record.salePriceCents,
    stockMil: record.stockMil,
    variants: record.variants,
    modifierGroups: record.modifierGroups,
    isActive: record.isActive,
    createdAt: record.createdAt,
    updatedAt: updatedAt,
    deletedAt: record.deletedAt,
  );
}
