class ModifierOption {
  const ModifierOption({
    required this.id,
    required this.uuid,
    required this.groupId,
    required this.name,
    required this.adjustmentType,
    required this.priceDeltaCents,
    required this.linkedProductId,
    required this.sortOrder,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String uuid;
  final int groupId;
  final String name;
  final String adjustmentType;
  final int priceDeltaCents;
  final int? linkedProductId;
  final int sortOrder;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class ModifierOptionInput {
  const ModifierOptionInput({
    required this.groupId,
    required this.name,
    required this.adjustmentType,
    this.priceDeltaCents = 0,
    this.linkedProductId,
    this.sortOrder = 0,
    this.isActive = true,
  });

  final int groupId;
  final String name;
  final String adjustmentType;
  final int priceDeltaCents;
  final int? linkedProductId;
  final int sortOrder;
  final bool isActive;
}
