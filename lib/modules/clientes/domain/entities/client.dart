import '../../../../app/core/sync/sync_status.dart';

class Client {
  const Client({
    required this.id,
    required this.uuid,
    required this.name,
    required this.phone,
    required this.address,
    required this.notes,
    required this.debtorBalanceCents,
    required this.creditBalanceCents,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    required this.deletedAt,
    this.remoteId,
    this.syncStatus = SyncStatus.localOnly,
    this.lastSyncedAt,
  });

  final int id;
  final String uuid;
  final String name;
  final String? phone;
  final String? address;
  final String? notes;
  final int debtorBalanceCents;
  final int creditBalanceCents;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String? remoteId;
  final SyncStatus syncStatus;
  final DateTime? lastSyncedAt;
}

class ClientInput {
  const ClientInput({
    required this.name,
    this.phone,
    this.address,
    this.notes,
    this.isActive = true,
  });

  final String name;
  final String? phone;
  final String? address;
  final String? notes;
  final bool isActive;
}
