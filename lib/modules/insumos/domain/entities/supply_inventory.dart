import 'supply.dart';

enum SupplyInventoryMovementType { inbound, outbound, reversal, adjustment }

extension SupplyInventoryMovementTypeX on SupplyInventoryMovementType {
  String get storageValue {
    return switch (this) {
      SupplyInventoryMovementType.inbound => 'in',
      SupplyInventoryMovementType.outbound => 'out',
      SupplyInventoryMovementType.reversal => 'reversal',
      SupplyInventoryMovementType.adjustment => 'adjustment',
    };
  }

  String get label {
    return switch (this) {
      SupplyInventoryMovementType.inbound => 'Entrada',
      SupplyInventoryMovementType.outbound => 'Saida',
      SupplyInventoryMovementType.reversal => 'Estorno',
      SupplyInventoryMovementType.adjustment => 'Ajuste',
    };
  }
}

SupplyInventoryMovementType supplyInventoryMovementTypeFromStorage(
  String? value,
) {
  return switch (value) {
    'in' => SupplyInventoryMovementType.inbound,
    'out' => SupplyInventoryMovementType.outbound,
    'reversal' => SupplyInventoryMovementType.reversal,
    _ => SupplyInventoryMovementType.adjustment,
  };
}

enum SupplyInventorySourceType {
  purchase,
  purchaseCancel,
  sale,
  saleCancel,
  manualAdjustment,
  migrationSeed,
}

extension SupplyInventorySourceTypeX on SupplyInventorySourceType {
  String get storageValue {
    return switch (this) {
      SupplyInventorySourceType.purchase => 'purchase',
      SupplyInventorySourceType.purchaseCancel => 'purchase_cancel',
      SupplyInventorySourceType.sale => 'sale',
      SupplyInventorySourceType.saleCancel => 'sale_cancel',
      SupplyInventorySourceType.manualAdjustment => 'manual_adjustment',
      SupplyInventorySourceType.migrationSeed => 'migration_seed',
    };
  }

  String get historyLabel {
    return switch (this) {
      SupplyInventorySourceType.purchase => 'Entrada por compra',
      SupplyInventorySourceType.purchaseCancel => 'Estorno de compra',
      SupplyInventorySourceType.sale => 'Consumo por venda',
      SupplyInventorySourceType.saleCancel => 'Estorno por cancelamento',
      SupplyInventorySourceType.manualAdjustment => 'Ajuste manual',
      SupplyInventorySourceType.migrationSeed => 'Saldo inicial migrado',
    };
  }

  String get filterLabel {
    return switch (this) {
      SupplyInventorySourceType.purchase => 'Compra',
      SupplyInventorySourceType.purchaseCancel => 'Estorno compra',
      SupplyInventorySourceType.sale => 'Venda',
      SupplyInventorySourceType.saleCancel => 'Estorno venda',
      SupplyInventorySourceType.manualAdjustment => 'Ajuste',
      SupplyInventorySourceType.migrationSeed => 'Saldo inicial',
    };
  }

  bool get isOperationalEvent {
    return this != SupplyInventorySourceType.migrationSeed;
  }
}

SupplyInventorySourceType supplyInventorySourceTypeFromStorage(String? value) {
  return switch (value) {
    'purchase' => SupplyInventorySourceType.purchase,
    'purchase_cancel' => SupplyInventorySourceType.purchaseCancel,
    'sale' => SupplyInventorySourceType.sale,
    'sale_cancel' => SupplyInventorySourceType.saleCancel,
    'manual_adjustment' => SupplyInventorySourceType.manualAdjustment,
    _ => SupplyInventorySourceType.migrationSeed,
  };
}

enum SupplyInventoryStatus { unknown, normal, low, critical }

extension SupplyInventoryStatusX on SupplyInventoryStatus {
  String get label {
    return switch (this) {
      SupplyInventoryStatus.unknown => 'Sem baseline',
      SupplyInventoryStatus.normal => 'Normal',
      SupplyInventoryStatus.low => 'Baixo',
      SupplyInventoryStatus.critical => 'Critico',
    };
  }
}

enum SupplyReorderFilter { all, critical, low }

extension SupplyReorderFilterX on SupplyReorderFilter {
  String get label {
    return switch (this) {
      SupplyReorderFilter.all => 'Todos',
      SupplyReorderFilter.critical => 'Critico',
      SupplyReorderFilter.low => 'Baixo',
    };
  }
}

enum SupplyInventoryBaselineSeedStatus {
  created,
  skippedAlreadyExists,
  skippedHasMovements,
  skippedInvalid,
}

class SupplyInventoryBaselineSeedResult {
  const SupplyInventoryBaselineSeedResult({
    required this.supplyId,
    required this.status,
  });

  final int supplyId;
  final SupplyInventoryBaselineSeedStatus status;

  bool get created => status == SupplyInventoryBaselineSeedStatus.created;
}

class SupplyInventoryConsistencyIssue {
  const SupplyInventoryConsistencyIssue({
    required this.supplyId,
    required this.supplyName,
    required this.cachedStockMil,
    required this.ledgerStockMil,
    required this.repaired,
  });

  final int supplyId;
  final String supplyName;
  final int? cachedStockMil;
  final int? ledgerStockMil;
  final bool repaired;
}

class SupplyInventoryConsistencyReport {
  const SupplyInventoryConsistencyReport({
    required this.checkedAt,
    required this.checkedSupplyCount,
    required this.issues,
  });

  final DateTime checkedAt;
  final int checkedSupplyCount;
  final List<SupplyInventoryConsistencyIssue> issues;

  int get driftedSupplyCount => issues.length;

  int get repairedSupplyCount => issues.where((issue) => issue.repaired).length;

  bool get hasDrift => issues.isNotEmpty;

  bool get isConsistent => issues.isEmpty;

  List<int> get repairedSupplyIds => issues
      .where((issue) => issue.repaired)
      .map((issue) => issue.supplyId)
      .toList(growable: false);
}

class SupplyInventoryMovement {
  const SupplyInventoryMovement({
    required this.id,
    required this.uuid,
    required this.remoteId,
    required this.supplyId,
    required this.supplyName,
    required this.movementType,
    required this.sourceType,
    required this.sourceLocalUuid,
    required this.sourceRemoteId,
    required this.quantityDeltaMil,
    required this.unitType,
    required this.balanceAfterMil,
    required this.notes,
    required this.occurredAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String uuid;
  final String? remoteId;
  final int supplyId;
  final String supplyName;
  final SupplyInventoryMovementType movementType;
  final SupplyInventorySourceType sourceType;
  final String? sourceLocalUuid;
  final String? sourceRemoteId;
  final int quantityDeltaMil;
  final String unitType;
  final int? balanceAfterMil;
  final String? notes;
  final DateTime occurredAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isEntry => quantityDeltaMil > 0;

  bool get isLegacySeed =>
      sourceType == SupplyInventorySourceType.migrationSeed;

  String get historyLabel => sourceType.historyLabel;

  String? get auditReferenceLabel {
    if (sourceLocalUuid == null || sourceLocalUuid!.trim().isEmpty) {
      return null;
    }
    if (sourceType == SupplyInventorySourceType.migrationSeed) {
      return null;
    }
    return 'Ref. ${sourceLocalUuid!.trim()}';
  }
}

class SupplyInventoryOverview {
  const SupplyInventoryOverview({
    required this.supply,
    required this.hasOperationalBaseline,
    required this.inventoryStatus,
    required this.lastMovementAt,
    required this.lastPurchaseAt,
  });

  final Supply supply;
  final bool hasOperationalBaseline;
  final SupplyInventoryStatus inventoryStatus;
  final DateTime? lastMovementAt;
  final DateTime? lastPurchaseAt;

  int? get currentStockMil => supply.currentStockMil;

  int? get minimumStockMil => supply.minimumStockMil;

  bool get isAlert =>
      supply.isActive &&
      hasOperationalBaseline &&
      supply.hasMinimumStock &&
      inventoryStatus != SupplyInventoryStatus.normal &&
      inventoryStatus != SupplyInventoryStatus.unknown;

  int get shortageMil {
    if (!supply.hasMinimumStock || currentStockMil == null) {
      return 0;
    }
    final shortage = supply.minimumStockMil! - currentStockMil!;
    return shortage < 0 ? 0 : shortage;
  }

  String get statusLabel {
    if (!supply.isActive) {
      return 'Inativo';
    }
    if (!hasOperationalBaseline) {
      return 'Sem baseline';
    }
    if (!supply.hasMinimumStock) {
      return 'Sem minimo';
    }
    return inventoryStatus.label;
  }
}

class SupplyReorderSuggestion {
  const SupplyReorderSuggestion({
    required this.overview,
    required this.shortageMil,
  });

  final SupplyInventoryOverview overview;
  final int shortageMil;

  bool matchesFilter(SupplyReorderFilter filter) {
    return switch (filter) {
      SupplyReorderFilter.all => overview.isAlert,
      SupplyReorderFilter.critical =>
        overview.inventoryStatus == SupplyInventoryStatus.critical,
      SupplyReorderFilter.low =>
        overview.inventoryStatus == SupplyInventoryStatus.low,
    };
  }

  static List<SupplyReorderSuggestion> sortOperational(
    Iterable<SupplyReorderSuggestion> suggestions, {
    SupplyReorderFilter filter = SupplyReorderFilter.all,
  }) {
    final filtered = suggestions
        .where((item) => item.matchesFilter(filter))
        .toList(growable: false);

    filtered.sort((left, right) {
      final leftRank =
          left.overview.inventoryStatus == SupplyInventoryStatus.critical
          ? 0
          : 1;
      final rightRank =
          right.overview.inventoryStatus == SupplyInventoryStatus.critical
          ? 0
          : 1;
      if (leftRank != rightRank) {
        return leftRank.compareTo(rightRank);
      }
      if (left.shortageMil != right.shortageMil) {
        return right.shortageMil.compareTo(left.shortageMil);
      }
      return left.overview.supply.name.toLowerCase().compareTo(
        right.overview.supply.name.toLowerCase(),
      );
    });

    return filtered;
  }
}
