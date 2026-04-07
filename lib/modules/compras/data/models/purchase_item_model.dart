import '../../domain/entities/purchase_item.dart';

class PurchaseItemModel extends PurchaseItem {
  const PurchaseItemModel({
    required super.id,
    required super.uuid,
    required super.purchaseId,
    required super.productId,
    required super.productNameSnapshot,
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
      productId: map['produto_id'] as int,
      productNameSnapshot: map['nome_produto_snapshot'] as String,
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
      'produto_id': productId,
      'nome_produto_snapshot': productNameSnapshot,
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
    int? productId,
    String? productNameSnapshot,
    String? unitMeasureSnapshot,
    int? quantityMil,
    int? unitCostCents,
    int? subtotalCents,
  }) {
    return PurchaseItemModel(
      id: id ?? this.id,
      uuid: uuid ?? this.uuid,
      purchaseId: purchaseId ?? this.purchaseId,
      productId: productId ?? this.productId,
      productNameSnapshot: productNameSnapshot ?? this.productNameSnapshot,
      unitMeasureSnapshot: unitMeasureSnapshot ?? this.unitMeasureSnapshot,
      quantityMil: quantityMil ?? this.quantityMil,
      unitCostCents: unitCostCents ?? this.unitCostCents,
      subtotalCents: subtotalCents ?? this.subtotalCents,
    );
  }
}
