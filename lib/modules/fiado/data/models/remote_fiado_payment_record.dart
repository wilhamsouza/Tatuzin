import '../../../vendas/domain/entities/sale_enums.dart';
import 'fiado_payment_sync_payload.dart';

class RemoteFiadoPaymentRecord {
  const RemoteFiadoPaymentRecord({
    required this.remoteId,
    required this.remoteSaleId,
    required this.localUuid,
    required this.amountCents,
    required this.paymentMethod,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory RemoteFiadoPaymentRecord.fromJson(Map<String, dynamic> json) {
    return RemoteFiadoPaymentRecord(
      remoteId: json['id'] as String,
      remoteSaleId: json['saleId'] as String,
      localUuid: json['localUuid'] as String,
      amountCents: json['amountCents'] as int? ?? 0,
      paymentMethod: PaymentMethodX.fromDb(
        json['paymentMethod'] as String? ?? 'dinheiro',
      ),
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  factory RemoteFiadoPaymentRecord.fromSyncPayload(
    FiadoPaymentSyncPayload payment,
  ) {
    return RemoteFiadoPaymentRecord(
      remoteId: payment.remoteId ?? '',
      remoteSaleId: payment.saleRemoteId ?? '',
      localUuid: payment.entryUuid,
      amountCents: payment.amountCents,
      paymentMethod: payment.paymentMethod,
      notes: payment.notes,
      createdAt: payment.createdAt,
      updatedAt: payment.updatedAt,
    );
  }

  final String remoteId;
  final String remoteSaleId;
  final String localUuid;
  final int amountCents;
  final PaymentMethod paymentMethod;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, dynamic> toCreateBody() {
    return <String, dynamic>{
      'saleId': remoteSaleId,
      'localUuid': localUuid,
      'amountCents': amountCents,
      'paymentMethod': paymentMethod.dbValue,
      'createdAt': createdAt.toIso8601String(),
      'notes': notes,
    };
  }
}
