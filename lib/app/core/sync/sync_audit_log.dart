import 'sync_audit_event_type.dart';

class SyncAuditLog {
  const SyncAuditLog({
    required this.id,
    required this.featureKey,
    required this.entityType,
    required this.localEntityId,
    required this.localUuid,
    required this.remoteId,
    required this.eventType,
    required this.message,
    required this.details,
    required this.createdAt,
  });

  final int id;
  final String featureKey;
  final String? entityType;
  final int? localEntityId;
  final String? localUuid;
  final String? remoteId;
  final SyncAuditEventType eventType;
  final String message;
  final Map<String, dynamic>? details;
  final DateTime createdAt;
}
