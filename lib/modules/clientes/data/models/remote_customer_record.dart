import '../../domain/entities/client.dart';

class RemoteCustomerRecord {
  const RemoteCustomerRecord({
    required this.remoteId,
    required this.localUuid,
    required this.name,
    required this.phone,
    required this.address,
    required this.notes,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    required this.deletedAt,
  });

  factory RemoteCustomerRecord.fromJson(Map<String, dynamic> json) {
    final remoteId = json['id'] as String;
    return RemoteCustomerRecord(
      remoteId: remoteId,
      localUuid: (json['localUuid'] as String?)?.trim().isNotEmpty == true
          ? json['localUuid'] as String
          : remoteId,
      name: json['name'] as String,
      phone: json['phone'] as String?,
      address: json['address'] as String?,
      notes: json['notes'] as String?,
      isActive: (json['isActive'] as bool?) ?? true,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      deletedAt: json['deletedAt'] == null
          ? null
          : DateTime.parse(json['deletedAt'] as String),
    );
  }

  factory RemoteCustomerRecord.fromLocalClient(Client client) {
    return RemoteCustomerRecord(
      remoteId: client.remoteId ?? '',
      localUuid: client.uuid,
      name: client.name,
      phone: client.phone,
      address: client.address,
      notes: client.notes,
      isActive: client.isActive,
      createdAt: client.createdAt,
      updatedAt: client.updatedAt,
      deletedAt: client.deletedAt,
    );
  }

  final String remoteId;
  final String localUuid;
  final String name;
  final String? phone;
  final String? address;
  final String? notes;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  RemoteCustomerRecord copyWithInactive() {
    final now = DateTime.now();
    return RemoteCustomerRecord(
      remoteId: remoteId,
      localUuid: localUuid,
      name: name,
      phone: phone,
      address: address,
      notes: notes,
      isActive: false,
      createdAt: createdAt,
      updatedAt: now,
      deletedAt: deletedAt ?? now,
    );
  }

  Map<String, dynamic> toUpsertBody() {
    return <String, dynamic>{
      'localUuid': localUuid,
      'name': name,
      'phone': phone,
      'address': address,
      'notes': notes,
      'isActive': isActive,
      'deletedAt': deletedAt?.toIso8601String(),
    };
  }
}
