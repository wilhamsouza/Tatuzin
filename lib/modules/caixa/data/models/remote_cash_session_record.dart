class RemoteCashSessionRecord {
  const RemoteCashSessionRecord({
    required this.remoteId,
    required this.localUuid,
    required this.operatorName,
    required this.status,
    required this.openedAt,
    required this.closedAt,
    required this.initialFloatCents,
    required this.expectedBalanceCents,
    required this.countedBalanceCents,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory RemoteCashSessionRecord.fromJson(Map<String, dynamic> json) {
    final remoteId = json['id'] as String;
    return RemoteCashSessionRecord(
      remoteId: remoteId,
      localUuid: (json['localUuid'] as String?)?.trim().isNotEmpty == true
          ? json['localUuid'] as String
          : remoteId,
      operatorName: _cleanNullable(json['operatorName'] as String?),
      status: (json['status'] as String?) ?? 'open',
      openedAt: json['openedAt'] == null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.parse(json['openedAt'] as String),
      closedAt: json['closedAt'] == null
          ? null
          : DateTime.parse(json['closedAt'] as String),
      initialFloatCents: json['openingBalanceCents'] as int? ?? 0,
      expectedBalanceCents: json['expectedBalanceCents'] as int?,
      countedBalanceCents: json['closingBalanceCents'] as int?,
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  final String remoteId;
  final String localUuid;
  final String? operatorName;
  final String status;
  final DateTime openedAt;
  final DateTime? closedAt;
  final int initialFloatCents;
  final int? expectedBalanceCents;
  final int? countedBalanceCents;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
}

String? _cleanNullable(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
