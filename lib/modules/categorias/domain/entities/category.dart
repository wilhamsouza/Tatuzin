import '../../../../app/core/sync/sync_status.dart';

class Category {
  const Category({
    required this.id,
    required this.uuid,
    required this.name,
    required this.description,
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
  final String? description;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String? remoteId;
  final SyncStatus syncStatus;
  final DateTime? lastSyncedAt;
}

class CategoryInput {
  const CategoryInput({
    required this.name,
    this.description,
    this.isActive = true,
  });

  final String name;
  final String? description;
  final bool isActive;
}
