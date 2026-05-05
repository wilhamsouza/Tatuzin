import 'operational_sync_event.dart';
import 'operational_sync_queue_status.dart';

class OperationalSyncQueueItem {
  const OperationalSyncQueueItem({
    required this.id,
    required this.event,
    required this.status,
    required this.attemptCount,
    required this.createdAt,
    required this.updatedAt,
    this.nextRetryAt,
    this.serverVersion,
    this.errorCode,
    this.errorMessage,
    this.conflictId,
    this.pushingStartedAt,
    this.lastPushedAt,
  });

  final int id;
  final OperationalSyncEvent event;
  final OperationalSyncQueueStatus status;
  final int attemptCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? nextRetryAt;
  final String? serverVersion;
  final String? errorCode;
  final String? errorMessage;
  final String? conflictId;
  final DateTime? pushingStartedAt;
  final DateTime? lastPushedAt;
}
