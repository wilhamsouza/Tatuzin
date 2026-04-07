import '../app_context/record_identity.dart';
import 'sync_status.dart';

class SyncMetadata {
  const SyncMetadata({
    required this.featureKey,
    required this.identity,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.lastSyncedAt,
    required this.lastError,
    required this.lastErrorType,
    required this.lastErrorAt,
  });

  final String featureKey;
  final RecordIdentity identity;
  final SyncStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastSyncedAt;
  final String? lastError;
  final String? lastErrorType;
  final DateTime? lastErrorAt;
}
