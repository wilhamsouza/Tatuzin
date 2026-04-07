import '../../../vendas/domain/entities/sale_enums.dart';
import '../../../../app/core/sync/sync_status.dart';
import '../../domain/entities/purchase.dart';
import '../../domain/entities/purchase_status.dart';

class PurchaseModel extends Purchase {
  const PurchaseModel({
    required super.id,
    required super.uuid,
    required super.supplierId,
    required super.supplierName,
    required super.documentNumber,
    required super.notes,
    required super.purchasedAt,
    required super.dueDate,
    required super.paymentMethod,
    required super.status,
    required super.subtotalCents,
    required super.discountCents,
    required super.surchargeCents,
    required super.freightCents,
    required super.finalAmountCents,
    required super.paidAmountCents,
    required super.pendingAmountCents,
    required super.createdAt,
    required super.updatedAt,
    required super.cancelledAt,
    required super.itemsCount,
    super.remoteId,
    super.syncStatus,
    super.lastSyncedAt,
  });

  factory PurchaseModel.fromMap(Map<String, Object?> map) {
    return PurchaseModel(
      id: map['id'] as int,
      uuid: map['uuid'] as String,
      supplierId: map['fornecedor_id'] as int,
      supplierName:
          map['fornecedor_nome'] as String? ??
          map['supplier_name'] as String? ??
          '',
      documentNumber: map['numero_documento'] as String?,
      notes: map['observacao'] as String?,
      purchasedAt: DateTime.parse(map['data_compra'] as String),
      dueDate: map['data_vencimento'] == null
          ? null
          : DateTime.parse(map['data_vencimento'] as String),
      paymentMethod: map['forma_pagamento'] == null
          ? null
          : PaymentMethodX.fromDb(map['forma_pagamento'] as String),
      status: PurchaseStatusX.fromDb(map['status'] as String),
      subtotalCents: map['subtotal_centavos'] as int,
      discountCents: map['desconto_centavos'] as int? ?? 0,
      surchargeCents: map['acrescimo_centavos'] as int? ?? 0,
      freightCents: map['frete_centavos'] as int? ?? 0,
      finalAmountCents: map['valor_final_centavos'] as int,
      paidAmountCents: map['valor_pago_centavos'] as int? ?? 0,
      pendingAmountCents: map['valor_pendente_centavos'] as int? ?? 0,
      createdAt: DateTime.parse(map['criado_em'] as String),
      updatedAt: DateTime.parse(map['atualizado_em'] as String),
      cancelledAt: map['cancelada_em'] == null
          ? null
          : DateTime.parse(map['cancelada_em'] as String),
      itemsCount: map['itens_quantidade'] as int? ?? 0,
      remoteId: map['sync_remote_id'] as String?,
      syncStatus: syncStatusFromStorage(map['sync_status'] as String?),
      lastSyncedAt: map['sync_last_synced_at'] == null
          ? null
          : DateTime.parse(map['sync_last_synced_at'] as String),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'uuid': uuid,
      'fornecedor_id': supplierId,
      'numero_documento': documentNumber,
      'observacao': notes,
      'data_compra': purchasedAt.toIso8601String(),
      'data_vencimento': dueDate?.toIso8601String(),
      'forma_pagamento': paymentMethod?.dbValue,
      'status': status.dbValue,
      'subtotal_centavos': subtotalCents,
      'desconto_centavos': discountCents,
      'acrescimo_centavos': surchargeCents,
      'frete_centavos': freightCents,
      'valor_final_centavos': finalAmountCents,
      'valor_pago_centavos': paidAmountCents,
      'valor_pendente_centavos': pendingAmountCents,
      'cancelada_em': cancelledAt?.toIso8601String(),
      'criado_em': createdAt.toIso8601String(),
      'atualizado_em': updatedAt.toIso8601String(),
      'sync_remote_id': remoteId,
      'sync_status': syncStatus?.storageValue,
      'sync_last_synced_at': lastSyncedAt?.toIso8601String(),
    };
  }

  PurchaseModel copyWith({
    int? id,
    String? uuid,
    int? supplierId,
    String? supplierName,
    String? documentNumber,
    String? notes,
    DateTime? purchasedAt,
    DateTime? dueDate,
    PaymentMethod? paymentMethod,
    PurchaseStatus? status,
    int? subtotalCents,
    int? discountCents,
    int? surchargeCents,
    int? freightCents,
    int? finalAmountCents,
    int? paidAmountCents,
    int? pendingAmountCents,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? cancelledAt,
    int? itemsCount,
    String? remoteId,
    SyncStatus? syncStatus,
    DateTime? lastSyncedAt,
  }) {
    return PurchaseModel(
      id: id ?? this.id,
      uuid: uuid ?? this.uuid,
      supplierId: supplierId ?? this.supplierId,
      supplierName: supplierName ?? this.supplierName,
      documentNumber: documentNumber ?? this.documentNumber,
      notes: notes ?? this.notes,
      purchasedAt: purchasedAt ?? this.purchasedAt,
      dueDate: dueDate ?? this.dueDate,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      status: status ?? this.status,
      subtotalCents: subtotalCents ?? this.subtotalCents,
      discountCents: discountCents ?? this.discountCents,
      surchargeCents: surchargeCents ?? this.surchargeCents,
      freightCents: freightCents ?? this.freightCents,
      finalAmountCents: finalAmountCents ?? this.finalAmountCents,
      paidAmountCents: paidAmountCents ?? this.paidAmountCents,
      pendingAmountCents: pendingAmountCents ?? this.pendingAmountCents,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      cancelledAt: cancelledAt ?? this.cancelledAt,
      itemsCount: itemsCount ?? this.itemsCount,
      remoteId: remoteId ?? this.remoteId,
      syncStatus: syncStatus ?? this.syncStatus,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    );
  }
}
