enum SupplyCostHistorySource { manual, purchase }

extension SupplyCostHistorySourceX on SupplyCostHistorySource {
  String get storageValue {
    return switch (this) {
      SupplyCostHistorySource.manual => 'manual',
      SupplyCostHistorySource.purchase => 'purchase',
    };
  }

  String get label {
    return switch (this) {
      SupplyCostHistorySource.manual => 'Manual',
      SupplyCostHistorySource.purchase => 'Compra',
    };
  }
}

SupplyCostHistorySource supplyCostHistorySourceFromStorage(String? value) {
  return switch (value) {
    'purchase' => SupplyCostHistorySource.purchase,
    _ => SupplyCostHistorySource.manual,
  };
}

enum SupplyCostHistoryEventType {
  manualEdit,
  purchaseCreated,
  purchaseUpdated,
  purchaseCanceled,
  conversionChanged,
}

extension SupplyCostHistoryEventTypeX on SupplyCostHistoryEventType {
  String get storageValue {
    return switch (this) {
      SupplyCostHistoryEventType.manualEdit => 'manual_edit',
      SupplyCostHistoryEventType.purchaseCreated => 'purchase_created',
      SupplyCostHistoryEventType.purchaseUpdated => 'purchase_updated',
      SupplyCostHistoryEventType.purchaseCanceled => 'purchase_canceled',
      SupplyCostHistoryEventType.conversionChanged => 'conversion_changed',
    };
  }

  String get label {
    return switch (this) {
      SupplyCostHistoryEventType.manualEdit => 'Edicao manual',
      SupplyCostHistoryEventType.purchaseCreated => 'Compra criada',
      SupplyCostHistoryEventType.purchaseUpdated => 'Compra atualizada',
      SupplyCostHistoryEventType.purchaseCanceled => 'Compra cancelada',
      SupplyCostHistoryEventType.conversionChanged => 'Conversao alterada',
    };
  }
}

SupplyCostHistoryEventType supplyCostHistoryEventTypeFromStorage(
  String? value, {
  SupplyCostHistorySource? fallbackSource,
}) {
  return switch (value) {
    'purchase_created' => SupplyCostHistoryEventType.purchaseCreated,
    'purchase_updated' => SupplyCostHistoryEventType.purchaseUpdated,
    'purchase_canceled' => SupplyCostHistoryEventType.purchaseCanceled,
    'conversion_changed' => SupplyCostHistoryEventType.conversionChanged,
    'manual_edit' => SupplyCostHistoryEventType.manualEdit,
    _ =>
      fallbackSource == SupplyCostHistorySource.purchase
          ? SupplyCostHistoryEventType.purchaseUpdated
          : SupplyCostHistoryEventType.manualEdit,
  };
}

class SupplyCostHistoryEntry {
  const SupplyCostHistoryEntry({
    required this.id,
    required this.uuid,
    required this.supplyId,
    required this.purchaseId,
    required this.purchaseItemId,
    required this.source,
    required this.eventType,
    required this.purchaseUnitType,
    required this.conversionFactor,
    required this.lastPurchasePriceCents,
    required this.averagePurchasePriceCents,
    required this.changeSummary,
    required this.notes,
    required this.occurredAt,
    required this.createdAt,
  });

  final int id;
  final String uuid;
  final int supplyId;
  final int? purchaseId;
  final int? purchaseItemId;
  final SupplyCostHistorySource source;
  final SupplyCostHistoryEventType eventType;
  final String purchaseUnitType;
  final int conversionFactor;
  final int lastPurchasePriceCents;
  final int? averagePurchasePriceCents;
  final String? changeSummary;
  final String? notes;
  final DateTime occurredAt;
  final DateTime createdAt;
}
