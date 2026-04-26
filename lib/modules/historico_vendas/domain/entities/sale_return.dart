import '../../../carrinho/domain/entities/cart_item.dart';
import '../../../vendas/domain/entities/sale_enums.dart';

enum SaleReturnMode { returnOnly, exchangeWithNewSale }

extension SaleReturnModeX on SaleReturnMode {
  String get storageValue {
    return switch (this) {
      SaleReturnMode.returnOnly => 'return_only',
      SaleReturnMode.exchangeWithNewSale => 'exchange_with_new_sale',
    };
  }

  String get label {
    return switch (this) {
      SaleReturnMode.returnOnly => 'Devolucao',
      SaleReturnMode.exchangeWithNewSale => 'Troca com nova venda',
    };
  }
}

SaleReturnMode saleReturnModeFromStorage(String value) {
  return switch (value) {
    'exchange_with_new_sale' => SaleReturnMode.exchangeWithNewSale,
    _ => SaleReturnMode.returnOnly,
  };
}

class SaleReturnRecord {
  const SaleReturnRecord({
    required this.id,
    required this.uuid,
    required this.saleId,
    required this.clientId,
    required this.mode,
    required this.reason,
    required this.refundAmountCents,
    required this.creditedAmountCents,
    required this.appliedDiscountCents,
    required this.replacementSaleId,
    required this.replacementSaleReceiptNumber,
    required this.createdAt,
    required this.items,
  });

  final int id;
  final String uuid;
  final int saleId;
  final int? clientId;
  final SaleReturnMode mode;
  final String? reason;
  final int refundAmountCents;
  final int creditedAmountCents;
  final int appliedDiscountCents;
  final int? replacementSaleId;
  final String? replacementSaleReceiptNumber;
  final DateTime createdAt;
  final List<SaleReturnItemRecord> items;

  int get totalReturnedCents =>
      items.fold<int>(0, (total, item) => total + item.subtotalCents);
}

class SaleReturnItemRecord {
  const SaleReturnItemRecord({
    required this.id,
    required this.saleReturnId,
    required this.saleItemId,
    required this.productId,
    required this.productVariantId,
    required this.productName,
    required this.variantSkuSnapshot,
    required this.variantColorSnapshot,
    required this.variantSizeSnapshot,
    required this.quantityMil,
    required this.unitPriceCents,
    required this.subtotalCents,
    required this.reason,
  });

  final int id;
  final int saleReturnId;
  final int saleItemId;
  final int productId;
  final int? productVariantId;
  final String productName;
  final String? variantSkuSnapshot;
  final String? variantColorSnapshot;
  final String? variantSizeSnapshot;
  final int quantityMil;
  final int unitPriceCents;
  final int subtotalCents;
  final String? reason;

  int get quantityUnits => quantityMil ~/ 1000;

  String? get variantSummary {
    final labels = <String>[
      if ((variantColorSnapshot ?? '').trim().isNotEmpty)
        variantColorSnapshot!.trim(),
      if ((variantSizeSnapshot ?? '').trim().isNotEmpty)
        variantSizeSnapshot!.trim(),
    ];
    if (labels.isEmpty) {
      return null;
    }
    return labels.join(' / ');
  }
}

class SaleReturnInput {
  const SaleReturnInput({
    required this.saleId,
    required this.mode,
    required this.reason,
    required this.returnedItems,
    this.replacementItems = const <CartItem>[],
    this.replacementPaymentMethod = PaymentMethod.cash,
  });

  final int saleId;
  final SaleReturnMode mode;
  final String? reason;
  final List<SaleReturnItemInput> returnedItems;
  final List<CartItem> replacementItems;
  final PaymentMethod replacementPaymentMethod;
}

class SaleReturnItemInput {
  const SaleReturnItemInput({
    required this.saleItemId,
    required this.quantityMil,
    this.reason,
  });

  final int saleItemId;
  final int quantityMil;
  final String? reason;
}

class SaleReturnResult {
  const SaleReturnResult({
    required this.saleReturnId,
    required this.mode,
    required this.refundAmountCents,
    required this.creditedAmountCents,
    required this.appliedDiscountCents,
    this.replacementSaleId,
    this.replacementReceiptNumber,
  });

  final int saleReturnId;
  final SaleReturnMode mode;
  final int refundAmountCents;
  final int creditedAmountCents;
  final int appliedDiscountCents;
  final int? replacementSaleId;
  final String? replacementReceiptNumber;
}
