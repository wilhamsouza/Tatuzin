class ReconciliationRemoteComparableRecord {
  const ReconciliationRemoteComparableRecord({
    required this.entityType,
    required this.remoteId,
    required this.localUuid,
    required this.label,
    required this.updatedAt,
    required this.payload,
  });

  final String entityType;
  final String remoteId;
  final String? localUuid;
  final String label;
  final DateTime updatedAt;
  final Map<String, dynamic> payload;
}
