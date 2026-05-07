import 'operational_sync_event.dart';

abstract interface class OperationalSyncRemoteDataSource {
  Future<OperationalSyncPushResponse> pushEvents(
    List<OperationalSyncEvent> events, {
    String? lastKnownServerVersion,
  });

  Future<OperationalSyncPullResponse> pullChanges({
    required String sinceVersion,
    Iterable<String> features = const <String>[],
    int limit = 100,
  });

  Future<OperationalSyncStatusResponse> getStatus();

  Future<List<OperationalSyncConflict>> getConflicts();

  Future<OperationalSyncConflict> resolveConflict(
    String conflictId,
    Map<String, dynamic> resolution,
  );
}

class OperationalSyncPushResponse {
  const OperationalSyncPushResponse({
    required this.currentServerVersion,
    required this.accepted,
    required this.duplicates,
    required this.rejected,
    required this.conflicts,
  });

  final String currentServerVersion;
  final List<OperationalSyncPushItemResult> accepted;
  final List<OperationalSyncPushItemResult> duplicates;
  final List<OperationalSyncPushItemResult> rejected;
  final List<OperationalSyncPushItemResult> conflicts;

  factory OperationalSyncPushResponse.fromJson(Map<String, dynamic> json) {
    return OperationalSyncPushResponse(
      currentServerVersion: _stringValue(json['currentServerVersion']) ?? '0',
      accepted: _readResultList(json['accepted']),
      duplicates: _readResultList(json['duplicates']),
      rejected: _readResultList(json['rejected']),
      conflicts: _readResultList(json['conflicts']),
    );
  }
}

class OperationalSyncPushItemResult {
  const OperationalSyncPushItemResult({
    required this.eventId,
    required this.entity,
    required this.operation,
    this.serverVersion,
    this.code,
    this.message,
  });

  final String eventId;
  final String entity;
  final String operation;
  final String? serverVersion;
  final String? code;
  final String? message;

  factory OperationalSyncPushItemResult.fromJson(Map<String, dynamic> json) {
    return OperationalSyncPushItemResult(
      eventId: _stringValue(json['eventId']) ?? 'unknown',
      entity: _stringValue(json['entity']) ?? 'unknown',
      operation: _stringValue(json['operation']) ?? 'unknown',
      serverVersion: _stringValue(json['serverVersion']),
      code: _stringValue(json['code']),
      message: _stringValue(json['message']),
    );
  }
}

class OperationalSyncPullResponse {
  const OperationalSyncPullResponse({
    required this.currentServerVersion,
    required this.nextSinceVersion,
    required this.hasMore,
    required this.events,
    this.usesProjectionContract = false,
  });

  final String currentServerVersion;
  final String nextSinceVersion;
  final bool hasMore;
  final List<OperationalSyncPulledEvent> events;
  final bool usesProjectionContract;

  List<OperationalSyncPulledEvent> get changes => events;

  factory OperationalSyncPullResponse.fromJson(Map<String, dynamic> json) {
    final rawChanges = json['changes'];
    final usesProjectionContract = rawChanges is List;
    return OperationalSyncPullResponse(
      currentServerVersion: _stringValue(json['currentServerVersion']) ?? '0',
      nextSinceVersion: _stringValue(json['nextSinceVersion']) ?? '0',
      hasMore: json['hasMore'] == true,
      events: _readMapList(
        usesProjectionContract ? rawChanges : json['events'],
      ).map(OperationalSyncPulledEvent.fromJson).toList(growable: false),
      usesProjectionContract: usesProjectionContract,
    );
  }
}

class OperationalSyncPulledEvent {
  const OperationalSyncPulledEvent({
    required this.eventId,
    required this.feature,
    required this.entity,
    required this.operation,
    required this.occurredAt,
    required this.payload,
    this.entityLocalId,
    this.entityServerId,
    this.serverVersion,
    this.materializedAt,
    this.projection,
    this.projectionWarning,
  });

  final String eventId;
  final String feature;
  final String entity;
  final String operation;
  final String? entityLocalId;
  final String? entityServerId;
  final DateTime occurredAt;
  final Map<String, dynamic> payload;
  final String? serverVersion;
  final DateTime? materializedAt;
  final Map<String, dynamic>? projection;
  final String? projectionWarning;

  bool get hasProjection => projection != null;

  factory OperationalSyncPulledEvent.fromJson(Map<String, dynamic> json) {
    final payload = json['payload'];
    final projection = json['projection'];
    return OperationalSyncPulledEvent(
      eventId: _stringValue(json['eventId']) ?? 'unknown',
      feature: _stringValue(json['feature']) ?? 'pdv',
      entity: _stringValue(json['entity']) ?? 'unknown',
      operation: _stringValue(json['operation']) ?? 'unknown',
      entityLocalId: _stringValue(json['entityLocalId']),
      entityServerId: _stringValue(json['entityServerId']),
      occurredAt:
          DateTime.tryParse(_stringValue(json['occurredAt']) ?? '') ??
          DateTime.now(),
      payload: payload is Map<String, dynamic>
          ? payload
          : const <String, dynamic>{},
      serverVersion: _stringValue(json['serverVersion']),
      materializedAt: DateTime.tryParse(
        _stringValue(json['materializedAt']) ?? '',
      ),
      projection: projection is Map<String, dynamic> ? projection : null,
      projectionWarning: _stringValue(json['projectionWarning']),
    );
  }
}

class OperationalSyncStatusResponse {
  const OperationalSyncStatusResponse({
    required this.companyId,
    required this.deviceId,
    required this.syncEnabled,
    required this.currentServerVersion,
    required this.openConflictsCount,
    required this.deviceStatus,
    this.serverFirstSnapshotVersion,
  });

  final String companyId;
  final String deviceId;
  final bool syncEnabled;
  final String currentServerVersion;
  final int openConflictsCount;
  final String deviceStatus;
  final String? serverFirstSnapshotVersion;

  factory OperationalSyncStatusResponse.fromJson(Map<String, dynamic> json) {
    final device = json['device'];
    return OperationalSyncStatusResponse(
      companyId: _stringValue(json['companyId']) ?? '',
      deviceId: _stringValue(json['deviceId']) ?? '',
      syncEnabled: json['syncEnabled'] == true,
      currentServerVersion: _stringValue(json['currentServerVersion']) ?? '0',
      openConflictsCount: _intValue(json['openConflictsCount']) ?? 0,
      deviceStatus: device is Map<String, dynamic>
          ? _stringValue(device['status']) ?? 'UNKNOWN'
          : 'UNKNOWN',
      serverFirstSnapshotVersion: _stringValue(
        json['serverFirstSnapshotVersion'],
      ),
    );
  }
}

class OperationalSyncConflict {
  const OperationalSyncConflict({
    required this.id,
    required this.entity,
    required this.code,
    required this.message,
    required this.status,
    this.entityLocalId,
    this.entityServerId,
    this.eventId,
  });

  final String id;
  final String entity;
  final String? entityLocalId;
  final String? entityServerId;
  final String code;
  final String message;
  final String status;
  final String? eventId;

  factory OperationalSyncConflict.fromJson(Map<String, dynamic> json) {
    final event = json['event'];
    return OperationalSyncConflict(
      id: _stringValue(json['id']) ?? '',
      entity: _stringValue(json['entity']) ?? 'unknown',
      entityLocalId: _stringValue(json['entityLocalId']),
      entityServerId: _stringValue(json['entityServerId']),
      code: _stringValue(json['code']) ?? 'SYNC_CONFLICT',
      message: _stringValue(json['message']) ?? 'Conflito de sincronizacao.',
      status: _stringValue(json['status']) ?? 'OPEN',
      eventId: event is Map<String, dynamic>
          ? _stringValue(event['eventId'])
          : null,
    );
  }
}

List<OperationalSyncPushItemResult> _readResultList(Object? value) {
  return _readMapList(
    value,
  ).map(OperationalSyncPushItemResult.fromJson).toList(growable: false);
}

List<Map<String, dynamic>> _readMapList(Object? value) {
  if (value is! List) {
    return const <Map<String, dynamic>>[];
  }
  return value.whereType<Map<String, dynamic>>().toList(growable: false);
}

String? _stringValue(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  if (value is num || value is bool) {
    return value.toString();
  }
  return null;
}

int? _intValue(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}
