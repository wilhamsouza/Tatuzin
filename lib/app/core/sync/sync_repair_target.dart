class SyncRepairTarget {
  const SyncRepairTarget({
    required this.featureKey,
    required this.entityType,
    required this.entityLabel,
    required this.localEntityId,
    required this.localUuid,
    required this.remoteId,
  });

  final String featureKey;
  final String entityType;
  final String entityLabel;
  final int? localEntityId;
  final String? localUuid;
  final String? remoteId;

  String get stableKey {
    final localKey = localEntityId?.toString() ?? localUuid ?? remoteId ?? 'na';
    return '$featureKey:$entityType:$localKey';
  }
}
