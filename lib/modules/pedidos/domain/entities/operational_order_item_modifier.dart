class OperationalOrderItemModifier {
  const OperationalOrderItemModifier({
    required this.id,
    required this.uuid,
    required this.orderItemId,
    required this.modifierGroupId,
    required this.modifierOptionId,
    required this.groupNameSnapshot,
    required this.optionNameSnapshot,
    required this.adjustmentTypeSnapshot,
    required this.priceDeltaCents,
    required this.quantity,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String uuid;
  final int orderItemId;
  final int? modifierGroupId;
  final int? modifierOptionId;
  final String? groupNameSnapshot;
  final String optionNameSnapshot;
  final String adjustmentTypeSnapshot;
  final int priceDeltaCents;
  final int quantity;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class OperationalOrderItemModifierInput {
  const OperationalOrderItemModifierInput({
    this.modifierGroupId,
    this.modifierOptionId,
    this.groupNameSnapshot,
    required this.optionNameSnapshot,
    required this.adjustmentTypeSnapshot,
    this.priceDeltaCents = 0,
    this.quantity = 1,
  });

  final int? modifierGroupId;
  final int? modifierOptionId;
  final String? groupNameSnapshot;
  final String optionNameSnapshot;
  final String adjustmentTypeSnapshot;
  final int priceDeltaCents;
  final int quantity;
}
