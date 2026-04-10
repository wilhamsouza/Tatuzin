import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/app_context/app_operational_context.dart';
import '../../../../app/core/app_context/data_access_policy.dart';
import '../../../../app/core/config/app_environment.dart';
import '../../../../app/core/database/app_database.dart';
import '../../../../app/core/network/network_providers.dart';
import '../../../../app/core/providers/app_data_refresh_provider.dart';
import '../../../../app/core/session/auth_token_storage.dart';
import '../../../carrinho/presentation/providers/cart_provider.dart';
import '../../../produtos/domain/entities/product.dart';
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

final salesCatalogProvider = FutureProvider<List<Product>>((ref) async {
  ref.watch(appDataRefreshProvider);
  final query = ref.watch(salesSearchQueryProvider);
  return ref.watch(productRepositoryProvider).searchAvailable(query: query);
});

final salesQuickAddProvider = Provider<SalesQuickAddController>((ref) {
  return SalesQuickAddController(ref);
});

final localSaleRepositoryProvider = Provider<SqliteSaleRepository>((ref) {
  return SqliteSaleRepository(
    ref.read(appDatabaseProvider),
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

    final catalog = await _ref
        .read(productRepositoryProvider)
        .searchAvailable(query: rawValue.trim());

    Product? matchedProduct;
    for (final product in catalog) {
      if (_normalizeBarcode(product.barcode) == normalizedBarcode) {
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
}
