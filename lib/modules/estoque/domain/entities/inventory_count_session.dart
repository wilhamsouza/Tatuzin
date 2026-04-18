enum InventoryCountSessionStatus { open, counting, reviewed, applied, canceled }

extension InventoryCountSessionStatusX on InventoryCountSessionStatus {
  String get storageValue {
    return switch (this) {
      InventoryCountSessionStatus.open => 'open',
      InventoryCountSessionStatus.counting => 'counting',
      InventoryCountSessionStatus.reviewed => 'reviewed',
      InventoryCountSessionStatus.applied => 'applied',
      InventoryCountSessionStatus.canceled => 'canceled',
    };
  }

  String get label {
    return switch (this) {
      InventoryCountSessionStatus.open => 'Aberta',
      InventoryCountSessionStatus.counting => 'Em contagem',
      InventoryCountSessionStatus.reviewed => 'Revisada',
      InventoryCountSessionStatus.applied => 'Aplicada',
      InventoryCountSessionStatus.canceled => 'Cancelada',
    };
  }

  bool get canEdit {
    return switch (this) {
      InventoryCountSessionStatus.open => true,
      InventoryCountSessionStatus.counting => true,
      InventoryCountSessionStatus.reviewed => true,
      InventoryCountSessionStatus.applied => false,
      InventoryCountSessionStatus.canceled => false,
    };
  }

  bool get canApply {
    return switch (this) {
      InventoryCountSessionStatus.open => true,
      InventoryCountSessionStatus.counting => true,
      InventoryCountSessionStatus.reviewed => true,
      InventoryCountSessionStatus.applied => false,
      InventoryCountSessionStatus.canceled => false,
    };
  }
}

InventoryCountSessionStatus inventoryCountSessionStatusFromStorage(
  String? value,
) {
  return switch (value) {
    'open' => InventoryCountSessionStatus.open,
    'counting' => InventoryCountSessionStatus.counting,
    'reviewed' => InventoryCountSessionStatus.reviewed,
    'applied' => InventoryCountSessionStatus.applied,
    'canceled' => InventoryCountSessionStatus.canceled,
    _ => InventoryCountSessionStatus.open,
  };
}

class InventoryCountSession {
  const InventoryCountSession({
    required this.id,
    required this.uuid,
    required this.name,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.appliedAt,
    this.totalItems = 0,
    this.itemsWithDifference = 0,
    this.surplusMil = 0,
    this.shortageMil = 0,
  });

  final int id;
  final String uuid;
  final String name;
  final InventoryCountSessionStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? appliedAt;
  final int totalItems;
  final int itemsWithDifference;
  final int surplusMil;
  final int shortageMil;

  bool get hasDifferences => itemsWithDifference > 0;
}
