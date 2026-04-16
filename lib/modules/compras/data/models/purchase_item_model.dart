import '../../domain/entities/purchase_item.dart';

class PurchaseItemModel extends PurchaseItem {
  const PurchaseItemModel({
    required super.id,
    required super.uuid,
    required super.purchaseId,
    required super.itemType,
    required super.productId,
    required super.productVariantId,
    required super.supplyId,
    required super.itemNameSnapshot,
    required super.variantSkuSnapshot,
    required super.variantColorLabelSnapshot,
    required super.variantSizeLabelSnapshot,
    required super.unitMeasureSnapshot,
    required super.quantityMil,
    required super.unitCostCents,
    required super.subtotalCents,
  });

  factory PurchaseItemModel.fromMap(Map<String, Object?> map) {
    return PurchaseItemModel(
      id: map['id'] as int,
      uuid: map['uuid'] as String,
      purchaseId: map['compra_id'] as int,
      itemType: purchaseItemTypeFromStorage(map['item_type'] as String?),
      productId: map['produto_id'] as int?,
      productVariantId: map['produto_variante_id'] as int?,
      supplyId: map['supply_id'] as int?,
      itemNameSnapshot:
          map['nome_item_snapshot'] as String? ??
          map['nome_produto_snapshot'] as String? ??
          '',
      variantSkuSnapshot: map['sku_variante_snapshot'] as String?,
      variantColorLabelSnapshot: map['cor_variante_snapshot'] as String?,
      variantSizeLabelSnapshot: map['tamanho_variante_snapshot'] as String?,
      unitMeasureSnapshot: map['unidade_medida_snapshot'] as String,
      quantityMil: map['quantidade_mil'] as int,
      unitCostCents: map['custo_unitario_centavos'] as int,
      subtotalCents: map['subtotal_centavos'] as int,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'uuid': uuid,
      'compra_id': purchaseId,
      'item_type': itemType.storageValue,
      'produto_id': productId,
      'produto_variante_id': productVariantId,
      'supply_id': supplyId,
      'nome_item_snapshot': itemNameSnapshot,
      'sku_variante_snapshot': variantSkuSnapshot,
      'cor_variante_snapshot': variantColorLabelSnapshot,
      'tamanho_variante_snapshot': variantSizeLabelSnapshot,
      'unidade_medida_snapshot': unitMeasureSnapshot,
      'quantidade_mil': quantityMil,
      'custo_unitario_centavos': unitCostCents,
      'subtotal_centavos': subtotalCents,
    };
  }

  PurchaseItemModel copyWith({
    int? id,
    String? uuid,
    int? purchaseId,
    PurchaseItemType? itemType,
    int? productId,
    int? productVariantId,
    int? supplyId,
    String? itemNameSnapshot,
    String? variantSkuSnapshot,
    String? variantColorLabelSnapshot,
    String? variantSizeLabelSnapshot,
    String? unitMeasureSnapshot,
    int? quantityMil,
    int? unitCostCents,
    int? subtotalCents,
  }) {
    return PurchaseItemModel(
      id: id ?? this.id,
      uuid: uuid ?? this.uuid,
      purchaseId: purchaseId ?? this.purchaseId,
      itemType: itemType ?? this.itemType,
      productId: productId ?? this.productId,
      productVariantId: productVariantId ?? this.productVariantId,
      supplyId: supplyId ?? this.supplyId,
      itemNameSnapshot: itemNameSnapshot ?? this.itemNameSnapshot,
      variantSkuSnapshot: variantSkuSnapshot ?? this.variantSkuSnapshot,
      variantColorLabelSnapshot:
          variantColorLabelSnapshot ?? this.variantColorLabelSnapshot,
      variantSizeLabelSnapshot:
          variantSizeLabelSnapshot ?? this.variantSizeLabelSnapshot,
      unitMeasureSnapshot: unitMeasureSnapshot ?? this.unitMeasureSnapshot,
      quantityMil: quantityMil ?? this.quantityMil,
      unitCostCents: unitCostCents ?? this.unitCostCents,
      subtotalCents: subtotalCents ?? this.subtotalCents,
    );
  }
}
