enum InventoryMovementType {
  purchaseIn,
  purchaseReversalOut,
  adjustmentIn,
  adjustmentOut,
  saleOut,
  saleCancelIn,
  returnIn,
  exchangeOut,
  countAdjustmentIn,
  countAdjustmentOut,
}

extension InventoryMovementTypeX on InventoryMovementType {
  String get storageValue {
    return switch (this) {
      InventoryMovementType.purchaseIn => 'purchase_in',
      InventoryMovementType.purchaseReversalOut => 'purchase_reversal_out',
      InventoryMovementType.adjustmentIn => 'adjustment_in',
      InventoryMovementType.adjustmentOut => 'adjustment_out',
      InventoryMovementType.saleOut => 'sale_out',
      InventoryMovementType.saleCancelIn => 'sale_cancel_in',
      InventoryMovementType.returnIn => 'return_in',
      InventoryMovementType.exchangeOut => 'exchange_out',
      InventoryMovementType.countAdjustmentIn => 'count_adjustment_in',
      InventoryMovementType.countAdjustmentOut => 'count_adjustment_out',
    };
  }

  String get label {
    return switch (this) {
      InventoryMovementType.purchaseIn => 'Entrada por compra',
      InventoryMovementType.purchaseReversalOut => 'Reversao de compra',
      InventoryMovementType.adjustmentIn => 'Ajuste de entrada',
      InventoryMovementType.adjustmentOut => 'Ajuste de saida',
      InventoryMovementType.saleOut => 'Saida por venda',
      InventoryMovementType.saleCancelIn => 'Estorno de cancelamento',
      InventoryMovementType.returnIn => 'Devolucao',
      InventoryMovementType.exchangeOut => 'Saida por troca',
      InventoryMovementType.countAdjustmentIn =>
        'Ajuste por contagem (entrada)',
      InventoryMovementType.countAdjustmentOut => 'Ajuste por contagem (saida)',
    };
  }

  bool get isInbound {
    return switch (this) {
      InventoryMovementType.purchaseIn => true,
      InventoryMovementType.adjustmentIn => true,
      InventoryMovementType.saleCancelIn => true,
      InventoryMovementType.returnIn => true,
      InventoryMovementType.countAdjustmentIn => true,
      InventoryMovementType.purchaseReversalOut => false,
      InventoryMovementType.adjustmentOut => false,
      InventoryMovementType.saleOut => false,
      InventoryMovementType.exchangeOut => false,
      InventoryMovementType.countAdjustmentOut => false,
    };
  }
}

InventoryMovementType inventoryMovementTypeFromStorage(String? value) {
  return switch (value) {
    'purchase_in' => InventoryMovementType.purchaseIn,
    'purchase_reversal_out' => InventoryMovementType.purchaseReversalOut,
    'adjustment_in' => InventoryMovementType.adjustmentIn,
    'adjustment_out' => InventoryMovementType.adjustmentOut,
    'sale_out' => InventoryMovementType.saleOut,
    'sale_cancel_in' => InventoryMovementType.saleCancelIn,
    'return_in' => InventoryMovementType.returnIn,
    'exchange_out' => InventoryMovementType.exchangeOut,
    'count_adjustment_in' => InventoryMovementType.countAdjustmentIn,
    'count_adjustment_out' => InventoryMovementType.countAdjustmentOut,
    _ => InventoryMovementType.adjustmentIn,
  };
}

class InventoryMovement {
  const InventoryMovement({
    required this.id,
    required this.uuid,
    required this.productId,
    required this.productVariantId,
    required this.productName,
    required this.sku,
    required this.variantColorLabel,
    required this.variantSizeLabel,
    required this.movementType,
    required this.quantityDeltaMil,
    required this.stockBeforeMil,
    required this.stockAfterMil,
    required this.referenceType,
    required this.referenceId,
    required this.reason,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String uuid;
  final int productId;
  final int? productVariantId;
  final String productName;
  final String? sku;
  final String? variantColorLabel;
  final String? variantSizeLabel;
  final InventoryMovementType movementType;
  final int quantityDeltaMil;
  final int stockBeforeMil;
  final int stockAfterMil;
  final String referenceType;
  final int? referenceId;
  final String? reason;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get hasVariant => productVariantId != null;

  String? get variantSummary {
    final parts = <String>[
      if ((variantColorLabel ?? '').trim().isNotEmpty)
        variantColorLabel!.trim(),
      if ((variantSizeLabel ?? '').trim().isNotEmpty) variantSizeLabel!.trim(),
    ];
    if (parts.isEmpty) {
      return null;
    }
    return parts.join(' / ');
  }

  String get displayName {
    final summary = variantSummary;
    if (summary == null) {
      return productName;
    }
    return '$productName - $summary';
  }

  String get referenceLabel {
    switch (referenceType) {
      case 'purchase':
        return referenceId == null ? 'Compra' : 'Compra #$referenceId';
      case 'sale':
        return referenceId == null ? 'Venda' : 'Venda #$referenceId';
      case 'sale_return':
        return referenceId == null
            ? 'Devolucao/Troca'
            : 'Devolucao/Troca #$referenceId';
      case 'inventory_count_session':
        return referenceId == null
            ? 'Inventario fisico'
            : 'Inventario #$referenceId';
      case 'manual_adjustment':
        return 'Ajuste manual';
      default:
        return referenceId == null
            ? referenceType
            : '$referenceType #$referenceId';
    }
  }
}
