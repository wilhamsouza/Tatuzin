import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/app_context/app_operational_context.dart';
import '../../../../app/core/app_context/data_access_policy.dart';
import '../../../../app/core/config/app_environment.dart';
import '../../../../app/core/database/app_database.dart';
import '../../../../app/core/network/network_providers.dart';
import '../../../../app/core/providers/app_data_refresh_provider.dart';
import '../../../../app/core/providers/provider_context_logger.dart';
import '../../../../app/core/providers/provider_guard.dart';
import '../../../../app/core/providers/tenant_bootstrap_gate.dart';
import '../../../../app/core/session/auth_token_storage.dart';
import '../../../../app/core/utils/app_logger.dart';
import '../../../carrinho/presentation/providers/cart_provider.dart';
import '../../../estoque/domain/entities/stock_availability.dart';
import '../../../estoque/domain/entities/stock_reservation.dart';
import '../../../estoque/presentation/providers/inventory_providers.dart';
import '../../../produtos/domain/entities/product.dart';
import '../../../produtos/domain/repositories/product_repository.dart';
import '../../../produtos/presentation/providers/product_providers.dart';
import '../../data/datasources/sales_remote_datasource.dart';
import '../../data/real/real_sales_remote_datasource.dart';
import '../../data/sale_cancellation_sync_processor.dart';
import '../../data/sales_repository_impl.dart';
import '../../data/sqlite_sale_repository.dart';
import '../../domain/entities/checkout_input.dart';
import '../../domain/entities/completed_sale.dart';
import '../../domain/entities/sale_enums.dart';
import '../../domain/repositories/sale_repository.dart';
import '../../domain/usecases/cancel_sale_use_case.dart';
import '../../domain/usecases/finalize_cash_sale_use_case.dart';
import '../../domain/usecases/finalize_credit_sale_use_case.dart';

final salesSearchQueryProvider = StateProvider<String>((ref) => '');

final salesCatalogRepositoryProvider = Provider<ProductRepository>((ref) {
  return ref.watch(localProductRepositoryProvider);
});

class SalesCatalogEntry {
  const SalesCatalogEntry({
    required this.product,
    required this.productAvailability,
    required this.availableVariants,
  });

  final Product product;
  final StockAvailability productAvailability;
  final List<SalesCatalogVariantOption> availableVariants;

  bool get hasVariants => availableVariants.isNotEmpty;

  String get displayName {
    final modelName = product.modelName?.trim();
    if ((modelName ?? '').isNotEmpty) {
      return modelName!;
    }
    return product.name;
  }

  int get startingPriceCents {
    if (!hasVariants) {
      return product.salePriceCents;
    }

    var lowest =
        product.salePriceCents +
        availableVariants.first.variant.priceAdditionalCents;
    for (final option in availableVariants.skip(1)) {
      final price =
          product.salePriceCents + option.variant.priceAdditionalCents;
      if (price < lowest) {
        lowest = price;
      }
    }
    return lowest;
  }

  bool get hasPriceRange {
    if (!hasVariants) {
      return false;
    }

    final firstPrice =
        product.salePriceCents +
        availableVariants.first.variant.priceAdditionalCents;
    for (final option in availableVariants.skip(1)) {
      if (product.salePriceCents + option.variant.priceAdditionalCents !=
          firstPrice) {
        return true;
      }
    }
    return false;
  }

  int get totalStockMil {
    if (!hasVariants) {
      return productAvailability.availableQuantityMil;
    }

    return availableVariants.fold<int>(
      0,
      (total, option) => total + option.availableQuantityMil,
    );
  }

  int get totalPhysicalStockMil {
    if (!hasVariants) {
      return productAvailability.physicalQuantityMil;
    }

    return availableVariants.fold<int>(
      0,
      (total, option) => total + option.physicalQuantityMil,
    );
  }

  int get totalReservedStockMil {
    if (!hasVariants) {
      return productAvailability.reservedQuantityMil;
    }

    return availableVariants.fold<int>(
      0,
      (total, option) => total + option.reservedQuantityMil,
    );
  }

  Product buildSellableProduct() {
    return _copyProduct(
      salePriceCents: product.salePriceCents,
      stockMil: productAvailability.availableQuantityMil,
    );
  }

  Product buildSellableVariantProduct(SalesCatalogVariantOption option) {
    final variant = option.variant;
    return _copyProduct(
      sellableVariantId: variant.id,
      sellableVariantSku: variant.sku,
      sellableVariantColorLabel: variant.colorLabel,
      sellableVariantSizeLabel: variant.sizeLabel,
      sellableVariantPriceAdditionalCents: variant.priceAdditionalCents,
      salePriceCents: product.salePriceCents + variant.priceAdditionalCents,
      stockMil: option.availableQuantityMil,
    );
  }

  Product _copyProduct({
    int? sellableVariantId,
    String? sellableVariantSku,
    String? sellableVariantColorLabel,
    String? sellableVariantSizeLabel,
    int? sellableVariantPriceAdditionalCents,
    required int salePriceCents,
    required int stockMil,
  }) {
    return Product(
      id: product.id,
      uuid: product.uuid,
      name: product.name,
      description: product.description,
      categoryId: product.categoryId,
      categoryName: product.categoryName,
      barcode: product.barcode,
      primaryPhotoPath: product.primaryPhotoPath,
      productType: product.productType,
      niche: product.niche,
      catalogType: product.catalogType,
      modelName: product.modelName,
      variantLabel: product.variantLabel,
      baseProductId: product.baseProductId,
      baseProductName: product.baseProductName,
      variantAttributes: product.variantAttributes,
      variants: product.variants,
      modifierGroups: product.modifierGroups,
      sellableVariantId: sellableVariantId,
      sellableVariantSku: sellableVariantSku,
      sellableVariantColorLabel: sellableVariantColorLabel,
      sellableVariantSizeLabel: sellableVariantSizeLabel,
      sellableVariantPriceAdditionalCents: sellableVariantPriceAdditionalCents,
      unitMeasure: product.unitMeasure,
      costCents: product.costCents,
      manualCostCents: product.manualCostCents,
      costSource: product.costSource,
      salePriceCents: salePriceCents,
      stockMil: stockMil,
      isActive: product.isActive,
      createdAt: product.createdAt,
      updatedAt: product.updatedAt,
      deletedAt: product.deletedAt,
      remoteId: product.remoteId,
      syncStatus: product.syncStatus,
      lastSyncedAt: product.lastSyncedAt,
    );
  }
}

class SalesCatalogVariantOption {
  const SalesCatalogVariantOption({
    required this.variant,
    required this.availability,
  });

  final ProductVariant variant;
  final StockAvailability availability;

  int get physicalQuantityMil => availability.physicalQuantityMil;
  int get reservedQuantityMil => availability.reservedQuantityMil;
  int get availableQuantityMil => availability.availableQuantityMil;
}

final salesCatalogProvider = FutureProvider<List<SalesCatalogEntry>>((
  ref,
) async {
  await requireTenantBootstrapReady(ref, 'salesCatalogProvider');
  ref.watch(appDataRefreshProvider);
  logProviderContext(ref, 'salesCatalogProvider');
  final query = ref.watch(salesSearchQueryProvider);
  final repository = ref.watch(salesCatalogRepositoryProvider);
  final availabilityRepository = ref.watch(stockAvailabilityRepositoryProvider);
  final products = await runProviderGuarded(
    '[Vendas] salesCatalogProvider',
    () async {
      AppLogger.info('[Vendas] local product search started');
      final result = await repository.search(query: query);
      AppLogger.info(
        '[Vendas] local product search finished: ${result.length} products',
      );
      return result;
    },
    timeout: localProviderTimeout,
  );

  final keys = <StockReservationProductKey>{};
  for (final product in products.where((product) => product.isActive)) {
    if (product.hasVariants) {
      for (final variant in product.variants.where(
        (variant) => variant.isActive,
      )) {
        keys.add(
          StockReservationProductKey(
            productId: product.id,
            productVariantId: variant.id,
          ),
        );
      }
    } else {
      keys.add(
        StockReservationProductKey(
          productId: product.id,
          productVariantId: null,
        ),
      );
    }
  }
  final availabilityByKey = await availabilityRepository
      .getAvailabilityByProductKeys(keys);

  final entries = <SalesCatalogEntry>[];
  for (final product in products) {
    if (!product.isActive) {
      continue;
    }

    if (product.hasVariants) {
      final variants = <SalesCatalogVariantOption>[];
      for (final variant in product.variants.where(
        (variant) => variant.isActive,
      )) {
        final key = StockReservationProductKey(
          productId: product.id,
          productVariantId: variant.id,
        );
        final availability = availabilityByKey[key];
        if (availability == null || availability.availableQuantityMil <= 0) {
          continue;
        }
        variants.add(
          SalesCatalogVariantOption(
            variant: variant,
            availability: availability,
          ),
        );
      }
      if (variants.isEmpty) {
        continue;
      }
      entries.add(
        SalesCatalogEntry(
          product: product,
          productAvailability: StockAvailability(
            productId: product.id,
            productVariantId: null,
            physicalQuantityMil: variants.fold<int>(
              0,
              (total, option) => total + option.physicalQuantityMil,
            ),
            reservedQuantityMil: variants.fold<int>(
              0,
              (total, option) => total + option.reservedQuantityMil,
            ),
          ),
          availableVariants: variants,
        ),
      );
      continue;
    }

    final key = StockReservationProductKey(
      productId: product.id,
      productVariantId: null,
    );
    final availability = availabilityByKey[key];
    if (availability == null || availability.availableQuantityMil <= 0) {
      continue;
    }
    entries.add(
      SalesCatalogEntry(
        product: product,
        productAvailability: availability,
        availableVariants: const <SalesCatalogVariantOption>[],
      ),
    );
  }

  return entries;
});

final salesQuickAddProvider = Provider<SalesQuickAddController>((ref) {
  return SalesQuickAddController(ref);
});

final localSaleRepositoryProvider = Provider<SqliteSaleRepository>((ref) {
  return SqliteSaleRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(appOperationalContextProvider),
  );
});

final salesRemoteDatasourceProvider = Provider<SalesRemoteDatasource>((ref) {
  return RealSalesRemoteDatasource(
    apiClient: ref.read(realApiClientProvider),
    tokenStorage: ref.read(authTokenStorageProvider),
    environment: ref.watch(appEnvironmentProvider),
    operationalContext: ref.watch(appOperationalContextProvider),
  );
});

final salesHybridRepositoryProvider = Provider<SalesRepositoryImpl>((ref) {
  return SalesRepositoryImpl(
    localRepository: ref.read(localSaleRepositoryProvider),
    remoteDatasource: ref.read(salesRemoteDatasourceProvider),
    operationalContext: ref.watch(appOperationalContextProvider),
    dataAccessPolicy: ref.watch(appDataAccessPolicyProvider),
  );
});

final saleCancellationSyncProcessorProvider =
    Provider<SaleCancellationSyncProcessor>((ref) {
      return SaleCancellationSyncProcessor(
        localRepository: ref.read(localSaleRepositoryProvider),
        remoteDatasource: ref.read(salesRemoteDatasourceProvider),
        operationalContext: ref.watch(appOperationalContextProvider),
        dataAccessPolicy: ref.watch(appDataAccessPolicyProvider),
      );
    });

final saleRepositoryProvider = Provider<SaleRepository>((ref) {
  return ref.watch(salesHybridRepositoryProvider);
});

final finalizeCashSaleUseCaseProvider = Provider<FinalizeCashSaleUseCase>((
  ref,
) {
  return FinalizeCashSaleUseCase(ref.read(saleRepositoryProvider));
});

final finalizeCreditSaleUseCaseProvider = Provider<FinalizeCreditSaleUseCase>((
  ref,
) {
  return FinalizeCreditSaleUseCase(ref.read(saleRepositoryProvider));
});

final cancelSaleUseCaseProvider = Provider<CancelSaleUseCase>((ref) {
  return CancelSaleUseCase(ref.read(saleRepositoryProvider));
});

final checkoutControllerProvider =
    AsyncNotifierProvider<CheckoutController, void>(CheckoutController.new);

final cancelSaleControllerProvider =
    AsyncNotifierProvider<CancelSaleController, void>(CancelSaleController.new);

class CheckoutController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<CompletedSale> finalize(CheckoutInput input) async {
    state = const AsyncLoading();
    try {
      await requireTenantBootstrapReady(ref, 'CheckoutController.finalize');
      final sale = input.saleType.isCredit
          ? await ref.read(finalizeCreditSaleUseCaseProvider).call(input)
          : await ref.read(finalizeCashSaleUseCaseProvider).call(input);
      ref.read(appDataRefreshProvider.notifier).state++;
      state = const AsyncData(null);
      return sale;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }
}

class CancelSaleController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<void> cancel({required int saleId, required String reason}) async {
    state = const AsyncLoading();
    try {
      await requireTenantBootstrapReady(ref, 'CancelSaleController.cancel');
      await ref
          .read(cancelSaleUseCaseProvider)
          .call(saleId: saleId, reason: reason);
      ref.read(appDataRefreshProvider.notifier).state++;
      state = const AsyncData(null);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }
}

enum SalesQuickAddResultType { added, notFound, outOfStock, invalid }

class SalesQuickAddResult {
  const SalesQuickAddResult({
    required this.type,
    required this.message,
    this.product,
  });

  final SalesQuickAddResultType type;
  final String message;
  final Product? product;

  bool get wasAdded => type == SalesQuickAddResultType.added;
}

class SalesQuickAddController {
  const SalesQuickAddController(this._ref);

  final Ref _ref;

  Future<SalesQuickAddResult> addByBarcode(String rawValue) async {
    final normalizedBarcode = _normalizeBarcode(rawValue);
    if (normalizedBarcode.isEmpty) {
      return const SalesQuickAddResult(
        type: SalesQuickAddResultType.invalid,
        message: 'Informe um código de barras válido para adicionar direto.',
      );
    }

    await requireTenantBootstrapReady(
      _ref,
      'SalesQuickAddController.addByBarcode',
    );
    final catalog = await _ref
        .read(localProductRepositoryProvider)
        .searchAvailable(query: rawValue.trim());

    Product? matchedProduct;
    for (final product in catalog) {
      if (_normalizeBarcode(product.barcode) == normalizedBarcode ||
          _normalizeBarcode(product.sellableVariantSku) == normalizedBarcode) {
        matchedProduct = product;
        break;
      }
    }

    if (matchedProduct == null) {
      return const SalesQuickAddResult(
        type: SalesQuickAddResultType.notFound,
        message: 'Nenhum produto encontrado para o código informado.',
      );
    }

    final availability = await _ref
        .read(stockAvailabilityRepositoryProvider)
        .getAvailability(
          productId: matchedProduct.id,
          productVariantId: matchedProduct.sellableVariantId,
        );
    matchedProduct = _copyProductWithStock(
      matchedProduct,
      stockMil: availability.availableQuantityMil,
    );
    if (matchedProduct.stockMil < 1000) {
      return SalesQuickAddResult(
        type: SalesQuickAddResultType.outOfStock,
        product: matchedProduct,
        message:
            'Não foi possível adicionar ${matchedProduct.name} por falta de estoque.',
      );
    }

    final added = _ref.read(cartProvider.notifier).addProduct(matchedProduct);
    if (!added) {
      return SalesQuickAddResult(
        type: SalesQuickAddResultType.outOfStock,
        product: matchedProduct,
        message:
            'Não foi possível adicionar ${matchedProduct.name} por falta de estoque.',
      );
    }

    return SalesQuickAddResult(
      type: SalesQuickAddResultType.added,
      product: matchedProduct,
      message: '${matchedProduct.name} adicionado ao carrinho.',
    );
  }

  String _normalizeBarcode(String? value) {
    if (value == null) {
      return '';
    }

    final normalized = value.replaceAll(RegExp(r'[^0-9A-Za-z]'), '');
    return normalized.trim().toUpperCase();
  }

  Product _copyProductWithStock(Product product, {required int stockMil}) {
    return Product(
      id: product.id,
      uuid: product.uuid,
      name: product.name,
      description: product.description,
      categoryId: product.categoryId,
      categoryName: product.categoryName,
      barcode: product.barcode,
      primaryPhotoPath: product.primaryPhotoPath,
      productType: product.productType,
      niche: product.niche,
      catalogType: product.catalogType,
      modelName: product.modelName,
      variantLabel: product.variantLabel,
      baseProductId: product.baseProductId,
      baseProductName: product.baseProductName,
      variantAttributes: product.variantAttributes,
      variants: product.variants,
      modifierGroups: product.modifierGroups,
      sellableVariantId: product.sellableVariantId,
      sellableVariantSku: product.sellableVariantSku,
      sellableVariantColorLabel: product.sellableVariantColorLabel,
      sellableVariantSizeLabel: product.sellableVariantSizeLabel,
      sellableVariantPriceAdditionalCents:
          product.sellableVariantPriceAdditionalCents,
      unitMeasure: product.unitMeasure,
      costCents: product.costCents,
      manualCostCents: product.manualCostCents,
      costSource: product.costSource,
      variableCostSnapshotCents: product.variableCostSnapshotCents,
      estimatedGrossMarginCents: product.estimatedGrossMarginCents,
      estimatedGrossMarginPercentBasisPoints:
          product.estimatedGrossMarginPercentBasisPoints,
      lastCostUpdatedAt: product.lastCostUpdatedAt,
      salePriceCents: product.salePriceCents,
      stockMil: stockMil,
      isActive: product.isActive,
      createdAt: product.createdAt,
      updatedAt: product.updatedAt,
      deletedAt: product.deletedAt,
      remoteId: product.remoteId,
      syncStatus: product.syncStatus,
      lastSyncedAt: product.lastSyncedAt,
    );
  }
}
