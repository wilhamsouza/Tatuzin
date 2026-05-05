import 'dart:convert';

class OperationalSyncEvent {
  const OperationalSyncEvent({
    required this.eventId,
    required this.feature,
    required this.entity,
    required this.operation,
    required this.occurredAt,
    required this.payload,
    this.entityLocalId,
    this.entityServerId,
  });

  final String eventId;
  final String feature;
  final String entity;
  final String operation;
  final String? entityLocalId;
  final String? entityServerId;
  final DateTime occurredAt;
  final Map<String, dynamic> payload;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'eventId': eventId,
      'feature': feature,
      'entity': entity,
      'operation': operation,
      if (_notBlank(entityLocalId)) 'entityLocalId': entityLocalId,
      if (_notBlank(entityServerId)) 'entityServerId': entityServerId,
      'occurredAt': occurredAt.toUtc().toIso8601String(),
      'payload': payload,
    };
  }

  String encodePayload() => jsonEncode(payload);

  static OperationalSyncEvent fromJson(Map<String, dynamic> json) {
    final payload = json['payload'];
    return OperationalSyncEvent(
      eventId: _readRequiredString(json, 'eventId'),
      feature: _readRequiredString(json, 'feature'),
      entity: _readRequiredString(json, 'entity'),
      operation: _readRequiredString(json, 'operation'),
      entityLocalId: _readOptionalString(json, 'entityLocalId'),
      entityServerId: _readOptionalString(json, 'entityServerId'),
      occurredAt: DateTime.parse(_readRequiredString(json, 'occurredAt')),
      payload: payload is Map<String, dynamic>
          ? payload
          : const <String, dynamic>{},
    );
  }

  static OperationalSyncEvent fromStorage({
    required String eventId,
    required String feature,
    required String entity,
    required String operation,
    required String? entityLocalId,
    required String? entityServerId,
    required String occurredAt,
    required String payloadJson,
  }) {
    final decoded = jsonDecode(payloadJson);
    return OperationalSyncEvent(
      eventId: eventId,
      feature: feature,
      entity: entity,
      operation: operation,
      entityLocalId: entityLocalId,
      entityServerId: entityServerId,
      occurredAt: DateTime.parse(occurredAt),
      payload: decoded is Map<String, dynamic>
          ? decoded
          : const <String, dynamic>{},
    );
  }

  static String buildEventId({
    required String entity,
    required String operation,
    required Object localIdentity,
  }) {
    return '$entity:$operation:$localIdentity';
  }

  static bool _notBlank(String? value) {
    return value != null && value.trim().isNotEmpty;
  }

  static String _readRequiredString(Map<String, dynamic> source, String key) {
    final value = source[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    throw FormatException('Campo obrigatorio ausente: $key');
  }

  static String? _readOptionalString(Map<String, dynamic> source, String key) {
    final value = source[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return null;
  }
}
