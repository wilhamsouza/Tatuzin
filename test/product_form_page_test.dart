import 'package:erp_pdv_app/app/core/database/app_database.dart';
import 'package:erp_pdv_app/app/core/errors/app_exceptions.dart';
import 'package:erp_pdv_app/app/theme/app_theme.dart';
import 'package:erp_pdv_app/modules/categorias/domain/entities/category.dart';
import 'package:erp_pdv_app/modules/categorias/presentation/providers/category_providers.dart';
import 'package:erp_pdv_app/modules/insumos/domain/entities/supply.dart';
import 'package:erp_pdv_app/modules/insumos/presentation/providers/supply_providers.dart';
import 'package:erp_pdv_app/modules/produtos/data/sqlite_product_repository.dart';
import 'package:erp_pdv_app/modules/produtos/domain/entities/base_product.dart';
import 'package:erp_pdv_app/modules/produtos/domain/entities/product.dart';
import 'package:erp_pdv_app/modules/produtos/domain/repositories/product_repository.dart';
import 'package:erp_pdv_app/modules/produtos/presentation/pages/product_form_page.dart';
import 'package:erp_pdv_app/modules/produtos/presentation/pages/products_page.dart';
import 'package:erp_pdv_app/modules/produtos/presentation/providers/product_providers.dart';
import 'package:erp_pdv_app/modules/produtos/presentation/widgets/product_form/fashion_grid_section.dart';
import 'package:erp_pdv_app/modules/produtos/presentation/widgets/product_form/product_form_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'test_tenant_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('grade de moda interpreta M/G e preto/azul como matriz 2x2', () {
    final draft = const FashionGridDraft()
        .addSize('M/G')
        .addColor('preto/azul');

    final variants = draft.toVariantInputs(skuSeed: 'Camiseta Basic');

    expect(draft.sizes, ['M', 'G']);
    expect(draft.colors, ['preto', 'azul']);
    expect(draft.combinationCount, 4);
    expect(draft.activeVariantCount, 4);
    expect(variants, hasLength(4));
    expect(
      variants.map((variant) => '${variant.sizeLabel}/${variant.colorLabel}'),
      containsAll(const ['M/preto', 'M/azul', 'G/preto', 'G/azul']),
    );
    expect(
      variants.map((variant) => variant.sku),
      containsAll(const [
        'CAMISETA-BASIC-M-PRETO',
        'CAMISETA-BASIC-M-AZUL',
        'CAMISETA-BASIC-G-PRETO',
        'CAMISETA-BASIC-G-AZUL',
      ]),
    );
    expect(
      variants.map((variant) => variant.displayName),
      containsAll(const ['M / preto', 'M / azul', 'G / preto', 'G / azul']),
    );
  });

  test('grade de moda reduz combinacoes ao remover uma cor', () {
    final draft = const FashionGridDraft()
        .addSize('M, G')
        .addColor('preto, azul')
        .removeColor('azul');

    expect(draft.sizes, ['M', 'G']);
    expect(draft.colors, ['preto']);
    expect(draft.combinationCount, 2);
    expect(draft.activeVariantCount, 2);
    expect(draft.toVariantInputs(skuSeed: 'Camiseta Basic'), hasLength(2));
  });

  test('apelido manual da variante nao altera nome do produto pai', () {
    final draft = const FashionGridDraft()
        .addSize('M, G')
        .addColor('preto, azul')
        .upsertVariant(
          const FashionGridVariantDraft(
            sizeLabel: 'M',
            colorLabel: 'preto',
            stockMil: 1000,
            sku: 'CAMISA-M-PRETO',
            displayName: 'M preto promocao',
          ),
        )
        .removeColor('azul');

    final variants = draft.toVariantInputs(skuSeed: 'Camisa xadrez');

    expect(variants, hasLength(2));
    expect(variants.first.displayName, 'M preto promocao');
    expect(variants.last.displayName, 'G / preto');
  });

  testWidgets('editar produto simples usa update e nao create', (tester) async {
    final repository = _RecordingProductRepository();
    final product = _buildInitialSimpleProduct();
    final container = _createContainer(
      repository: repository,
      localRepository: _FakeLocalProductRepository(const <ProductVariant>[]),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: ProductFormPage(initialProduct: product),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Salvar alteracoes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(repository.createCalls, 0);
    expect(repository.updateCalls, 1);
    expect(repository.updatedId, product.id);
    expect(repository.updatedInput, isNotNull);
    expect(repository.updatedInput!.name, 'Cafe coado');
    expect(repository.updatedInput!.variants, isEmpty);
  });

  testWidgets('editar produto com grade usa update e nao create', (
    tester,
  ) async {
    final repository = _RecordingProductRepository();
    final product = _buildInitialFashionProduct();
    final container = _createContainer(
      repository: repository,
      localRepository: _FakeLocalProductRepository(product.variants),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: ProductFormPage(initialProduct: product),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Salvar alteracoes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(repository.createCalls, 0);
    expect(repository.updateCalls, 1);
    expect(repository.updatedId, product.id);
    expect(repository.updatedInput, isNotNull);
    expect(repository.updatedInput!.name, 'Camiseta Basic');
    expect(repository.updatedInput!.modelName, 'Camiseta Basic');
    expect(repository.updatedInput!.variantLabel, 'Tamanho/Cor');
    expect(repository.updatedInput!.variants, hasLength(2));
  });

  testWidgets('editar produto com grade 2x2 salva quatro variantes', (
    tester,
  ) async {
    final repository = _RecordingProductRepository();
    final product = _buildInitialFashionProductWithMatrixHint();
    final container = _createContainer(
      repository: repository,
      localRepository: _FakeLocalProductRepository(product.variants),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: ProductFormPage(initialProduct: product),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Salvar alteracoes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(repository.createCalls, 0);
    expect(repository.updateCalls, 1);
    expect(repository.updatedInput, isNotNull);
    expect(repository.updatedInput!.name, 'Camiseta Basic');
    expect(repository.updatedInput!.modelName, 'Camiseta Basic');
    expect(repository.updatedInput!.variantLabel, 'Tamanho/Cor');
    expect(repository.updatedInput!.variants, hasLength(4));
    expect(
      repository.updatedInput!.variants.map((variant) => variant.sku).toSet(),
      hasLength(4),
    );
    expect(
      repository.updatedInput!.variants.map(
        (variant) => '${variant.sizeLabel}/${variant.colorLabel}',
      ),
      containsAll(const ['M/preto', 'M/azul', 'G/preto', 'G/azul']),
    );
  });

  testWidgets('subtela da grade edita apelido da variante', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var draft = const FashionGridDraft()
        .addSize('M, G')
        .addColor('preto, azul');

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 700,
              child: StatefulBuilder(
                builder: (context, setState) {
                  return FashionGridSection(
                    isLoading: false,
                    skuSeed: 'Camisa xadrez',
                    draft: draft,
                    onChanged: (nextDraft) => setState(() => draft = nextDraft),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final cellFinder = find.byKey(const ValueKey('fashion-grid-cell-M-preto'));
    await tester.tap(cellFinder);
    await tester.pumpAndSettle();

    expect(find.text('Nome/apelido da variante'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('fashion-variant-display-name-field')),
      'M preto promocao',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Salvar').last);
    await tester.pumpAndSettle();

    expect(
      draft
          .toVariantInputs(skuSeed: 'Camisa xadrez')
          .singleWhere(
            (variant) =>
                variant.sizeLabel == 'M' && variant.colorLabel == 'preto',
          )
          .displayName,
      'M preto promocao',
    );
  });

  testWidgets('tela Produtos mostra miniatura local e fallback sem foto', (
    tester,
  ) async {
    final repository = _RecordingProductRepository(
      searchResults: [
        _buildInitialSimpleProduct(
          id: 21,
          name: 'Produto com foto',
          primaryPhotoPath: 'C:/tmp/thumb-produto.jpg',
        ),
        _buildInitialSimpleProduct(id: 22, name: 'Produto sem foto'),
      ],
    );
    final container = _createContainer(
      repository: repository,
      localRepository: _FakeLocalProductRepository(const <ProductVariant>[]),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: AppTheme.light(), home: const ProductsPage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.byKey(const ValueKey('product-list-thumbnail-21')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('product-list-thumbnail-fallback-22')),
      findsOneWidget,
    );
  });

  testWidgets(
    'erro 422 de grade em edicao nao exibe falso erro de nome do produto',
    (tester) async {
      final repository = _RecordingProductRepository(
        updateError: const NetworkRequestException(
          'Model name is required for variant products.',
          cause: 422,
        ),
      );
      final container = _createContainer(
        repository: repository,
        localRepository: _FakeLocalProductRepository(
          _buildInitialFashionProduct().variants,
        ),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: ProductFormPage(
              initialProduct: _buildInitialFashionProduct(),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.text('Salvar alteracoes'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(repository.createCalls, 0);
      expect(repository.updateCalls, 1);
      expect(
        find.text(
          'Nao foi possivel salvar as alteracoes do produto. Verifique a configuracao da grade de moda.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Nao foi possivel salvar as alteracoes do produto. Informe o nome do produto.',
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'erro 422 de sku de variante em edicao mostra erro de grade correto',
    (tester) async {
      final repository = _RecordingProductRepository(
        updateError: const NetworkRequestException(
          'variants.0.sku: String must contain at least 1 character(s)',
          cause: 422,
        ),
      );
      final container = _createContainer(
        repository: repository,
        localRepository: _FakeLocalProductRepository(
          _buildInitialFashionProduct().variants,
        ),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: ProductFormPage(
              initialProduct: _buildInitialFashionProduct(),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.text('Salvar alteracoes'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        find.text(
          'Nao foi possivel salvar as alteracoes do produto. Verifique a configuracao da grade de moda.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Nao foi possivel salvar as alteracoes do produto. Ative pelo menos uma variante na grade.',
        ),
        findsNothing,
      );
    },
  );
}

ProviderContainer _createContainer({
  required ProductRepository repository,
  required SqliteProductRepository localRepository,
}) {
  final container = ProviderContainer(
    overrides: [
      ...testTenantBootstrapOverrides(),
      localProductRepositoryProvider.overrideWithValue(localRepository),
      productRepositoryProvider.overrideWithValue(repository),
      categoryOptionsProvider.overrideWith((ref) => [_category()]),
      baseProductOptionsProvider.overrideWith((ref) => const <BaseProduct>[]),
      activeSupplyOptionsProvider.overrideWith((ref) => const <Supply>[]),
    ],
  );
  setTestTenantSession(container);
  return container;
}

class _RecordingProductRepository implements ProductRepository {
  _RecordingProductRepository({
    this.updateError,
    this.searchResults = const <Product>[],
  });

  final Object? updateError;
  final List<Product> searchResults;

  int createCalls = 0;
  int updateCalls = 0;
  int? updatedId;
  ProductInput? createdInput;
  ProductInput? updatedInput;

  @override
  Future<int> create(ProductInput input) async {
    createCalls++;
    createdInput = input;
    return 1;
  }

  @override
  Future<void> delete(int id) async {}

  @override
  Future<List<Product>> search({String query = ''}) async {
    return searchResults;
  }

  @override
  Future<List<Product>> searchAvailable({String query = ''}) async {
    return searchResults;
  }

  @override
  Future<void> update(int id, ProductInput input) async {
    updateCalls++;
    updatedId = id;
    updatedInput = input;
    if (updateError != null) {
      throw updateError!;
    }
  }
}

class _FakeLocalProductRepository extends SqliteProductRepository {
  _FakeLocalProductRepository(this.variants) : super(AppDatabase.instance);

  final List<ProductVariant> variants;

  @override
  Future<List<ProductPhoto>> listProductPhotos(int productId) async {
    return const <ProductPhoto>[];
  }

  @override
  Future<List<ProductRecipeItem>> listProductRecipeItems(int productId) async {
    return const <ProductRecipeItem>[];
  }

  @override
  Future<List<ProductVariant>> listProductVariants(int productId) async {
    return variants;
  }
}

Category _category() {
  final now = DateTime(2026, 5, 15, 10);
  return Category(
    id: 1,
    uuid: 'category-1',
    name: 'Roupas',
    description: null,
    isActive: true,
    createdAt: now,
    updatedAt: now,
    deletedAt: null,
  );
}

Product _buildInitialFashionProduct() {
  final now = DateTime(2026, 5, 15, 10);
  return Product(
    id: 7,
    uuid: 'product-7',
    name: 'Camiseta Basic',
    description: null,
    categoryId: 1,
    categoryName: 'Roupas',
    barcode: 'CAM-001',
    primaryPhotoPath: null,
    productType: 'unidade',
    niche: ProductNiches.fashion,
    catalogType: ProductCatalogTypes.variant,
    modelName: null,
    variantLabel: null,
    baseProductId: null,
    baseProductName: null,
    variants: [
      ProductVariant(
        id: 70,
        uuid: 'variant-70',
        productId: 7,
        remoteId: 'remote-variant-70',
        sku: 'CAM-BASIC-PRE-P',
        colorLabel: 'Preta',
        sizeLabel: 'P',
        priceAdditionalCents: 0,
        stockMil: 2000,
        sortOrder: 0,
        isActive: true,
        createdAt: now,
        updatedAt: now,
      ),
      ProductVariant(
        id: 71,
        uuid: 'variant-71',
        productId: 7,
        remoteId: 'remote-variant-71',
        sku: 'CAM-BASIC-PRE-M',
        colorLabel: 'Preta',
        sizeLabel: 'M',
        priceAdditionalCents: 0,
        stockMil: 3000,
        sortOrder: 1,
        isActive: true,
        createdAt: now,
        updatedAt: now,
      ),
    ],
    unitMeasure: 'un',
    costCents: 4500,
    manualCostCents: 4500,
    costSource: ProductCostSource.manual,
    salePriceCents: 9900,
    stockMil: 5000,
    isActive: true,
    createdAt: now,
    updatedAt: now,
    deletedAt: null,
    remoteId: 'remote-product-7',
  );
}

Product _buildInitialFashionProductWithMatrixHint() {
  final now = DateTime(2026, 5, 15, 10);
  return Product(
    id: 9,
    uuid: 'product-9',
    name: 'Camiseta Basic',
    description: null,
    categoryId: 1,
    categoryName: 'Roupas',
    barcode: 'CAM-002',
    primaryPhotoPath: null,
    productType: 'unidade',
    niche: ProductNiches.fashion,
    catalogType: ProductCatalogTypes.variant,
    modelName: null,
    variantLabel: null,
    baseProductId: null,
    baseProductName: null,
    variantAttributes: const [
      ProductVariantAttribute(
        key: 'fashion_size_grid_hint',
        value: 'sizes=M|G;colors=preto|azul',
      ),
    ],
    variants: [
      ProductVariant(
        id: 90,
        uuid: 'variant-90',
        productId: 9,
        remoteId: 'remote-variant-90',
        sku: 'CAMISETA-BASIC-M-PRETO',
        colorLabel: 'preto',
        sizeLabel: 'M',
        priceAdditionalCents: 0,
        stockMil: 3000,
        sortOrder: 0,
        isActive: true,
        createdAt: now,
        updatedAt: now,
      ),
      ProductVariant(
        id: 91,
        uuid: 'variant-91',
        productId: 9,
        remoteId: 'remote-variant-91',
        sku: 'CAMISETA-BASIC-G-AZUL',
        colorLabel: 'azul',
        sizeLabel: 'G',
        priceAdditionalCents: 0,
        stockMil: 3000,
        sortOrder: 1,
        isActive: true,
        createdAt: now,
        updatedAt: now,
      ),
    ],
    unitMeasure: 'un',
    costCents: 4500,
    manualCostCents: 4500,
    costSource: ProductCostSource.manual,
    salePriceCents: 9900,
    stockMil: 6000,
    isActive: true,
    createdAt: now,
    updatedAt: now,
    deletedAt: null,
    remoteId: 'remote-product-9',
  );
}

Product _buildInitialSimpleProduct({
  int id = 8,
  String name = 'Cafe coado',
  String? primaryPhotoPath,
}) {
  final now = DateTime(2026, 5, 15, 10);
  return Product(
    id: id,
    uuid: 'product-$id',
    name: name,
    description: null,
    categoryId: 1,
    categoryName: 'Roupas',
    barcode: 'CAF-001',
    primaryPhotoPath: primaryPhotoPath,
    productType: 'unidade',
    niche: ProductNiches.food,
    catalogType: ProductCatalogTypes.simple,
    modelName: null,
    variantLabel: null,
    baseProductId: null,
    baseProductName: null,
    unitMeasure: 'un',
    costCents: 250,
    manualCostCents: 250,
    costSource: ProductCostSource.manual,
    salePriceCents: 990,
    stockMil: 1000,
    isActive: true,
    createdAt: now,
    updatedAt: now,
    deletedAt: null,
    remoteId: 'remote-product-8',
  );
}
