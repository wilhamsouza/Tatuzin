import '../../../../app/core/sync/sync_status.dart';

class Supplier {
  const Supplier({
    required this.id,
    required this.uuid,
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
    this.remoteId,
    this.syncStatus,
    this.lastSyncedAt,
    this.pendingPurchasesCount = 0,
    this.pendingAmountCents = 0,
  });

  final int id;
  final String uuid;
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
  final String? remoteId;
  final SyncStatus? syncStatus;
  final DateTime? lastSyncedAt;
  final int pendingPurchasesCount;
  final int pendingAmountCents;
}

class SupplierInput {
  const SupplierInput({
    required this.name,
    this.tradeName,
    this.phone,
    this.email,
    this.address,
    this.document,
    this.contactPerson,
    this.notes,
    this.isActive = true,
  });

  final String name;
  final String? tradeName;
  final String? phone;
  final String? email;
  final String? address;
  final String? document;
  final String? contactPerson;
  final String? notes;
  final bool isActive;
}
