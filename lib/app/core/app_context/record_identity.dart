enum RecordOrigin { local, remote, merged }

class RecordIdentity {
  const RecordIdentity({
    required this.localId,
    required this.localUuid,
    required this.remoteId,
    required this.origin,
    required this.lastSyncedAt,
  });

  const RecordIdentity.local({required this.localId, required this.localUuid})
    : remoteId = null,
      origin = RecordOrigin.local,
      lastSyncedAt = null;

  final int? localId;
  final String? localUuid;
  final String? remoteId;
  final RecordOrigin origin;
  final DateTime? lastSyncedAt;

  bool get hasRemoteIdentity => remoteId != null && remoteId!.isNotEmpty;
}

String recordOriginToStorage(RecordOrigin origin) {
  switch (origin) {
    case RecordOrigin.local:
      return 'local';
    case RecordOrigin.remote:
      return 'remote';
    case RecordOrigin.merged:
      return 'merged';
  }
}

RecordOrigin recordOriginFromStorage(String? value) {
  switch (value) {
    case 'remote':
      return RecordOrigin.remote;
    case 'merged':
      return RecordOrigin.merged;
    case 'local':
    default:
      return RecordOrigin.local;
  }
}
