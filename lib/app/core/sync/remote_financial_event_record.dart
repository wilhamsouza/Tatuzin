class RemoteFinancialEventRecord {
  const RemoteFinancialEventRecord({
    required this.remoteId,
    required this.companyId,
    required this.saleId,
    required this.fiadoId,
    required this.eventType,
    required this.localUuid,
    required this.amountCents,
    required this.paymentType,
    required this.createdAt,
    required this.updatedAt,
    required this.metadata,
  });

  final String remoteId;
  final String companyId;
  final String? saleId;
  final String? fiadoId;
  final String eventType;
  final String localUuid;
  final int amountCents;
  final String? paymentType;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Map<String, dynamic>? metadata;

  factory RemoteFinancialEventRecord.fromJson(Map<String, dynamic> json) {
    return RemoteFinancialEventRecord(
      remoteId: json['id'] as String,
      companyId: json['companyId'] as String,
      saleId: json['saleId'] as String?,
      fiadoId: json['fiadoId'] as String?,
      eventType: json['eventType'] as String,
      localUuid: json['localUuid'] as String,
      amountCents: json['amountCents'] as int? ?? 0,
      paymentType: json['paymentType'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      metadata: json['metadata'] is Map<String, dynamic>
          ? json['metadata'] as Map<String, dynamic>
          : null,
    );
  }

  Map<String, dynamic> toCreateBody() {
    return <String, dynamic>{
      'saleId': saleId,
      'fiadoId': fiadoId,
      'eventType': eventType,
      'localUuid': localUuid,
      'amountCents': amountCents,
      'paymentType': paymentType,
      'createdAt': createdAt.toIso8601String(),
      'metadata': metadata,
    };
  }
}
