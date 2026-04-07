import '../../domain/entities/supplier.dart';

class RemoteSupplierRecord {
  const RemoteSupplierRecord({
    required this.remoteId,
    required this.localUuid,
    required this.name,
    required this.tradeName,
    required this.phone,
    required this.email,
    required this.address,
    required this.document,
    required this.contactPerson,
    required this.notes,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    required this.deletedAt,
  });

  factory RemoteSupplierRecord.fromJson(Map<String, dynamic> json) {
    return RemoteSupplierRecord(
      remoteId: json['id'] as String,
      localUuid: json['localUuid'] as String,
      name: json['name'] as String,
      tradeName: json['tradeName'] as String?,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      address: json['address'] as String?,
      document: json['document'] as String?,
      contactPerson: json['contactPerson'] as String?,
      notes: json['notes'] as String?,
      isActive: (json['isActive'] as bool?) ?? true,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      deletedAt: json['deletedAt'] == null
          ? null
          : DateTime.parse(json['deletedAt'] as String),
    );
  }

  factory RemoteSupplierRecord.fromLocalSupplier(Supplier supplier) {
    return RemoteSupplierRecord(
      remoteId: supplier.remoteId ?? '',
      localUuid: supplier.uuid,
      name: supplier.name,
      tradeName: supplier.tradeName,
      phone: supplier.phone,
      email: supplier.email,
      address: supplier.address,
      document: supplier.document,
      contactPerson: supplier.contactPerson,
      notes: supplier.notes,
      isActive: supplier.isActive,
      createdAt: supplier.createdAt,
      updatedAt: supplier.updatedAt,
      deletedAt: supplier.deletedAt,
    );
  }

  final String remoteId;
  final String localUuid;
  final String name;
  final String? tradeName;
  final String? phone;
  final String? email;
  final String? address;
  final String? document;
  final String? contactPerson;
  final String? notes;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  Map<String, dynamic> toUpsertBody() {
    return <String, dynamic>{
      'localUuid': localUuid,
      'name': name,
      'tradeName': tradeName,
      'phone': phone,
      'email': email,
      'address': address,
      'document': document,
      'contactPerson': contactPerson,
      'notes': notes,
      'isActive': isActive,
      'deletedAt': deletedAt?.toIso8601String(),
    };
  }
}
