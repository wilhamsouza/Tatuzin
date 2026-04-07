import '../../../vendas/domain/entities/sale_enums.dart';
import '../../domain/entities/cash_enums.dart';
import 'cash_event_sync_payload.dart';

class RemoteCashEventRecord {
  const RemoteCashEventRecord({
    required this.remoteId,
    required this.localUuid,
    required this.eventType,
    required this.amountCents,
    required this.paymentMethod,
    required this.referenceType,
    required this.referenceId,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory RemoteCashEventRecord.fromJson(Map<String, dynamic> json) {
    return RemoteCashEventRecord(
      remoteId: json['id'] as String,
      localUuid: json['localUuid'] as String,
      eventType: json['eventType'] as String,
      amountCents: json['amountCents'] as int? ?? 0,
      paymentMethod: _paymentMethodFromDb(json['paymentMethod'] as String?),
      referenceType: json['referenceType'] as String?,
      referenceId: json['referenceId'] as String?,
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  factory RemoteCashEventRecord.fromSyncPayload(CashEventSyncPayload event) {
    return RemoteCashEventRecord(
      remoteId: event.remoteId ?? '',
      localUuid: event.movementUuid,
      eventType: _eventTypeFor(event),
      amountCents: event.amountCents.abs(),
      paymentMethod: event.paymentMethod,
      referenceType: event.referenceType,
      referenceId: event.referenceRemoteId,
      notes: event.description,
      createdAt: event.createdAt,
      updatedAt: event.updatedAt,
    );
  }

  final String remoteId;
  final String localUuid;
  final String eventType;
  final int amountCents;
  final PaymentMethod? paymentMethod;
  final String? referenceType;
  final String? referenceId;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, dynamic> toCreateBody() {
    return <String, dynamic>{
      'localUuid': localUuid,
      'eventType': eventType,
      'amountCents': amountCents,
      'paymentMethod': paymentMethod?.dbValue,
      'referenceType': referenceType,
      'referenceId': referenceId,
      'notes': notes,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  static String _eventTypeFor(CashEventSyncPayload event) {
    switch (event.type) {
      case CashMovementType.sale:
      case CashMovementType.supply:
        return 'entrada';
      case CashMovementType.fiadoReceipt:
        return 'fiado_pagamento';
      case CashMovementType.sangria:
        return 'retirada';
      case CashMovementType.cancellation:
      case CashMovementType.adjustment:
        return event.amountCents < 0 ? 'saida' : 'entrada';
    }
  }

  static PaymentMethod? _paymentMethodFromDb(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    return PaymentMethodX.fromDb(value);
  }
}
