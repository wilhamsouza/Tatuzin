enum StockReservationStatus { active, released, converted }

extension StockReservationStatusX on StockReservationStatus {
  String get storageValue {
    return switch (this) {
      StockReservationStatus.active => 'active',
      StockReservationStatus.released => 'released',
      StockReservationStatus.converted => 'converted',
    };
  }

  static StockReservationStatus fromStorage(String value) {
    return switch (value) {
      'released' => StockReservationStatus.released,
      'converted' => StockReservationStatus.converted,
      _ => StockReservationStatus.active,
    };
  }
}

class StockReservation {
  const StockReservation({
    required this.id,
    required this.uuid,
    required this.operationalOrderId,
    required this.operationalOrderItemId,
    required this.productId,
    required this.productVariantId,
    required this.quantityMil,
    required this.status,
    required this.saleId,
    required this.createdAt,
    required this.updatedAt,
    required this.releasedAt,
    required this.convertedToSaleAt,
  });

  final int id;
  final String uuid;
  final int operationalOrderId;
  final int operationalOrderItemId;
  final int productId;
  final int? productVariantId;
  final int quantityMil;
  final StockReservationStatus status;
  final int? saleId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? releasedAt;
  final DateTime? convertedToSaleAt;

  bool get isActive => status == StockReservationStatus.active;
}

class StockReservationInput {
  const StockReservationInput({
    required this.operationalOrderId,
    required this.operationalOrderItemId,
    required this.productId,
    required this.productVariantId,
    required this.quantityMil,
  });

  final int operationalOrderId;
  final int operationalOrderItemId;
  final int productId;
  final int? productVariantId;
  final int quantityMil;
}

class StockReservationProductKey {
  const StockReservationProductKey({
    required this.productId,
    required this.productVariantId,
  });

  final int productId;
  final int? productVariantId;

  @override
  bool operator ==(Object other) {
    return other is StockReservationProductKey &&
        other.productId == productId &&
        other.productVariantId == productVariantId;
  }

  @override
  int get hashCode => Object.hash(productId, productVariantId);
}
