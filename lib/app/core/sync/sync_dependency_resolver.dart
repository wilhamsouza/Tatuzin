import '../../../modules/categorias/data/sqlite_category_repository.dart';
import '../../../modules/caixa/data/sqlite_cash_repository.dart';
import '../../../modules/fiado/data/sqlite_fiado_repository.dart';
import '../../../modules/fornecedores/data/sqlite_supplier_repository.dart';
import '../../../modules/vendas/data/sqlite_sale_repository.dart';
import '../../../modules/compras/data/sqlite_purchase_repository.dart';
import '../../../modules/produtos/data/sqlite_product_repository.dart';
import 'sync_feature_keys.dart';
import 'sync_queue_item.dart';
import 'sync_queue_operation.dart';

class DependencyResolution {
  const DependencyResolution({required this.isBlocked, this.reason});

  final bool isBlocked;
  final String? reason;
}

class SyncDependencyResolver {
  const SyncDependencyResolver({
    required SqliteCategoryRepository categoryRepository,
    required SqliteProductRepository productRepository,
    required SqliteSupplierRepository supplierRepository,
    required SqlitePurchaseRepository purchaseRepository,
    required SqliteSaleRepository saleRepository,
    required SqliteFiadoRepository fiadoRepository,
    required SqliteCashRepository cashRepository,
  }) : _categoryRepository = categoryRepository,
       _productRepository = productRepository,
       _supplierRepository = supplierRepository,
       _purchaseRepository = purchaseRepository,
       _saleRepository = saleRepository,
       _fiadoRepository = fiadoRepository,
       _cashRepository = cashRepository;

  final SqliteCategoryRepository _categoryRepository;
  final SqliteProductRepository _productRepository;
  final SqliteSupplierRepository _supplierRepository;
  final SqlitePurchaseRepository _purchaseRepository;
  final SqliteSaleRepository _saleRepository;
  final SqliteFiadoRepository _fiadoRepository;
  final SqliteCashRepository _cashRepository;

  Future<DependencyResolution> check(SyncQueueItem item) async {
    if (item.featureKey == SyncFeatureKeys.sales) {
      return _checkSale(item);
    }

    if (item.featureKey == SyncFeatureKeys.purchases) {
      return _checkPurchase(item);
    }

    if (item.featureKey == SyncFeatureKeys.financialEvents) {
      return _checkFinancialEvent(item);
    }

    if (item.featureKey == SyncFeatureKeys.cashEvents) {
      return _checkCashEvent(item);
    }

    if (item.featureKey != SyncFeatureKeys.products) {
      return const DependencyResolution(isBlocked: false);
    }

    if (item.operation == SyncQueueOperation.delete) {
      return const DependencyResolution(isBlocked: false);
    }

    final product = await _productRepository.findById(item.localEntityId);
    if (product == null || product.categoryId == null) {
      return const DependencyResolution(isBlocked: false);
    }

    final category = await _categoryRepository.findById(product.categoryId!);
    if (category == null) {
      return const DependencyResolution(
        isBlocked: true,
        reason:
            'Dependencia remota ausente: a categoria local do produto nao esta mais disponivel.',
      );
    }

    if (category.remoteId == null) {
      return const DependencyResolution(
        isBlocked: true,
        reason:
            'Dependencia remota ausente: aguardando a categoria ser recriada no backend.',
      );
    }

    return const DependencyResolution(isBlocked: false);
  }

  Future<DependencyResolution> _checkPurchase(SyncQueueItem item) async {
    final purchase = await _purchaseRepository.findPurchaseForSync(
      item.localEntityId,
    );
    if (purchase == null) {
      return const DependencyResolution(isBlocked: false);
    }

    final supplier = await _supplierRepository.findById(
      purchase.supplierLocalId,
    );
    if (supplier == null) {
      return const DependencyResolution(
        isBlocked: true,
        reason:
            'Compra ainda nao pode subir porque o fornecedor local vinculado nao esta mais disponivel.',
      );
    }
    if (supplier.remoteId == null) {
      return const DependencyResolution(
        isBlocked: true,
        reason:
            'Compra ainda nao pode subir porque o fornecedor remoto ainda nao foi recriado.',
      );
    }

    for (final purchaseItem in purchase.items) {
      final product = await _productRepository.findById(
        purchaseItem.productLocalId,
        includeDeleted: true,
      );
      if (product == null) {
        return DependencyResolution(
          isBlocked: true,
          reason:
              'Compra ainda nao pode subir porque o produto "${purchaseItem.productNameSnapshot}" nao existe mais localmente.',
        );
      }
      if (product.remoteId == null) {
        return DependencyResolution(
          isBlocked: true,
          reason:
              'Compra ainda nao pode subir porque o produto "${purchaseItem.productNameSnapshot}" ainda nao foi recriado no backend.',
        );
      }
    }

    return const DependencyResolution(isBlocked: false);
  }

  Future<DependencyResolution> _checkSale(SyncQueueItem item) async {
    final sale = await _saleRepository.findSaleForSync(item.localEntityId);
    if (sale == null) {
      return const DependencyResolution(isBlocked: false);
    }

    if (sale.clientLocalId != null && sale.clientRemoteId == null) {
      return const DependencyResolution(
        isBlocked: true,
        reason:
            'Dependencia remota ausente: aguardando o cliente ser recriado no backend.',
      );
    }

    for (final saleItem in sale.items) {
      if (saleItem.productLocalId != null && saleItem.productRemoteId == null) {
        return DependencyResolution(
          isBlocked: true,
          reason:
              'Dependencia remota ausente: aguardando o produto "${saleItem.productNameSnapshot}" ser recriado no backend.',
        );
      }
    }

    return const DependencyResolution(isBlocked: false);
  }

  Future<DependencyResolution> _checkFinancialEvent(SyncQueueItem item) async {
    switch (item.entityType) {
      case 'sale_canceled_event':
        final sale = await _saleRepository.findSaleCancellationForSync(
          item.localEntityId,
        );
        if (sale == null) {
          return const DependencyResolution(isBlocked: false);
        }

        if (sale.saleRemoteId == null || sale.saleRemoteId!.isEmpty) {
          return const DependencyResolution(
            isBlocked: true,
            reason:
                'Cancelamento aguardando a venda correspondente receber remoteId.',
          );
        }

        return const DependencyResolution(isBlocked: false);
      case 'fiado_payment_event':
        final payment = await _fiadoRepository.findPaymentForSync(
          item.localEntityId,
        );
        if (payment == null) {
          return const DependencyResolution(isBlocked: false);
        }

        if (payment.saleRemoteId == null || payment.saleRemoteId!.isEmpty) {
          return const DependencyResolution(
            isBlocked: true,
            reason:
                'Pagamento aguardando a venda correspondente receber remoteId.',
          );
        }

        return const DependencyResolution(isBlocked: false);
      default:
        return const DependencyResolution(isBlocked: false);
    }
  }

  Future<DependencyResolution> _checkCashEvent(SyncQueueItem item) async {
    final event = await _cashRepository.findCashEventForSync(
      item.localEntityId,
    );
    if (event == null) {
      return const DependencyResolution(isBlocked: false);
    }

    final requiresReference =
        event.referenceType == 'venda' || event.referenceType == 'fiado';
    if (requiresReference && event.referenceRemoteId == null) {
      return const DependencyResolution(
        isBlocked: true,
        reason: 'Evento de caixa aguardando a operacao remota de origem.',
      );
    }

    return const DependencyResolution(isBlocked: false);
  }
}
