import '../../../vendas/domain/entities/sale_enums.dart';
import '../../domain/entities/purchase_payment.dart';

class PurchasePaymentModel extends PurchasePayment {
  const PurchasePaymentModel({
    required super.id,
    required super.uuid,
    required super.purchaseId,
    required super.amountCents,
    required super.paymentMethod,
    required super.createdAt,
    required super.notes,
    required super.cashMovementId,
  });

  factory PurchasePaymentModel.fromMap(Map<String, Object?> map) {
    return PurchasePaymentModel(
      id: map['id'] as int,
      uuid: map['uuid'] as String,
      purchaseId: map['compra_id'] as int,
      amountCents: map['valor_centavos'] as int,
      paymentMethod: PaymentMethodX.fromDb(map['forma_pagamento'] as String),
      createdAt: DateTime.parse(map['data_hora'] as String),
      notes: map['observacao'] as String?,
      cashMovementId: map['caixa_movimento_id'] as int?,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'uuid': uuid,
      'compra_id': purchaseId,
      'valor_centavos': amountCents,
      'forma_pagamento': paymentMethod.dbValue,
      'data_hora': createdAt.toIso8601String(),
      'observacao': notes,
      'caixa_movimento_id': cashMovementId,
    };
  }

  PurchasePaymentModel copyWith({
    int? id,
    String? uuid,
    int? purchaseId,
    int? amountCents,
    PaymentMethod? paymentMethod,
    DateTime? createdAt,
    String? notes,
    int? cashMovementId,
  }) {
    return PurchasePaymentModel(
      id: id ?? this.id,
      uuid: uuid ?? this.uuid,
      purchaseId: purchaseId ?? this.purchaseId,
      amountCents: amountCents ?? this.amountCents,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      createdAt: createdAt ?? this.createdAt,
      notes: notes ?? this.notes,
      cashMovementId: cashMovementId ?? this.cashMovementId,
    );
  }
}
