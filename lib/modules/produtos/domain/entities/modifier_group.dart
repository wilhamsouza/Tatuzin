class ModifierGroup {
  const ModifierGroup({
    required this.id,
    required this.uuid,
    required this.baseProductId,
    required this.name,
    required this.isRequired,
    required this.minSelections,
    required this.maxSelections,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String uuid;
  final int baseProductId;
  final String name;
  final bool isRequired;
  final int minSelections;
  final int? maxSelections;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class ModifierGroupInput {
  const ModifierGroupInput({
    required this.baseProductId,
    required this.name,
    this.isRequired = false,
    this.minSelections = 0,
    this.maxSelections,
    this.isActive = true,
  });

  final int baseProductId;
  final String name;
  final bool isRequired;
  final int minSelections;
  final int? maxSelections;
  final bool isActive;
}
