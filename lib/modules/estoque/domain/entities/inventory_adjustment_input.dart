import 'inventory_movement.dart';

enum InventoryAdjustmentDirection { inbound, outbound }

extension InventoryAdjustmentDirectionX on InventoryAdjustmentDirection {
  String get label {
    return switch (this) {
      InventoryAdjustmentDirection.inbound => 'Entrada',
      InventoryAdjustmentDirection.outbound => 'Saida',
    };
  }

  InventoryMovementType get movementType {
    return switch (this) {
      InventoryAdjustmentDirection.inbound =>
        InventoryMovementType.adjustmentIn,
      InventoryAdjustmentDirection.outbound =>
        InventoryMovementType.adjustmentOut,
    };
  }

  int resolveDelta(int quantityMil) {
    return switch (this) {
      InventoryAdjustmentDirection.inbound => quantityMil,
      InventoryAdjustmentDirection.outbound => -quantityMil,
    };
  }
}

enum InventoryAdjustmentReason {
  correction,
  damage,
  loss,
  internalUse,
  operationalAdjustment,
}

extension InventoryAdjustmentReasonX on InventoryAdjustmentReason {
  String get storageValue {
    return switch (this) {
      InventoryAdjustmentReason.correction => 'correcao',
      InventoryAdjustmentReason.damage => 'avaria',
      InventoryAdjustmentReason.loss => 'perda',
      InventoryAdjustmentReason.internalUse => 'consumo_interno',
      InventoryAdjustmentReason.operationalAdjustment => 'ajuste_operacional',
    };
  }

  String get label {
    return switch (this) {
      InventoryAdjustmentReason.correction => 'Correcao',
      InventoryAdjustmentReason.damage => 'Avaria',
      InventoryAdjustmentReason.loss => 'Perda',
      InventoryAdjustmentReason.internalUse => 'Consumo interno',
      InventoryAdjustmentReason.operationalAdjustment => 'Ajuste operacional',
    };
  }
}

InventoryAdjustmentReason inventoryAdjustmentReasonFromStorage(String? value) {
  return switch (value) {
    'correcao' => InventoryAdjustmentReason.correction,
    'avaria' => InventoryAdjustmentReason.damage,
    'perda' => InventoryAdjustmentReason.loss,
    'consumo_interno' => InventoryAdjustmentReason.internalUse,
    'ajuste_operacional' => InventoryAdjustmentReason.operationalAdjustment,
    _ => InventoryAdjustmentReason.correction,
  };
}

class InventoryAdjustmentInput {
  const InventoryAdjustmentInput({
    required this.productId,
    required this.productVariantId,
    required this.direction,
    required this.quantityMil,
    required this.reason,
    this.notes,
  });

  final int productId;
  final int? productVariantId;
  final InventoryAdjustmentDirection direction;
  final int quantityMil;
  final InventoryAdjustmentReason reason;
  final String? notes;
}
