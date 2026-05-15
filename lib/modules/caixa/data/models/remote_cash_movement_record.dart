import '../../../vendas/domain/entities/sale_enums.dart';

class RemoteCashMovementRecord {
  const RemoteCashMovementRecord({
    required this.remoteId,
    required this.localUuid,
    required this.remoteCashSessionId,
    required this.type,
    required this.amountCents,
    required this.paymentMethod,
    required this.referenceType,
    required this.referenceId,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory RemoteCashMovementRecord.fromJson(Map<String, dynamic> json) {
    final remoteId = json['id'] as String;
    return RemoteCashMovementRecord(
      remoteId: remoteId,
      localUuid: (json['localUuid'] as String?)?.trim().isNotEmpty == true
          ? json['localUuid'] as String
          : remoteId,
      remoteCashSessionId: json['cashSessionId'] as String?,
      type: (json['eventType'] as String?) ?? 'ajuste',
      amountCents: json['amountCents'] as int? ?? 0,
      paymentMethod: _paymentMethodFromDb(json['paymentMethod'] as String?),
      referenceType: json['referenceType'] as String?,
      referenceId: _stringFromDynamic(json['referenceId']),
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  final String remoteId;
  final String localUuid;
  final String? remoteCashSessionId;
  final String type;
  final int amountCents;
  final PaymentMethod? paymentMethod;
  final String? referenceType;
  final String? referenceId;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
}

PaymentMethod? _paymentMethodFromDb(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }
  return PaymentMethodX.fromDb(value);
}

String? _stringFromDynamic(Object? value) {
  if (value == null) {
    return null;
  }
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}
