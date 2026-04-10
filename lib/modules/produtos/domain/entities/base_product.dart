class BaseProduct {
  const BaseProduct({
    required this.id,
    required this.uuid,
    required this.name,
    required this.description,
    required this.categoryId,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String uuid;
  final String name;
  final String? description;
  final int? categoryId;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class BaseProductInput {
  const BaseProductInput({
    required this.name,
    this.description,
    this.categoryId,
    this.isActive = true,
  });

  final String name;
  final String? description;
  final int? categoryId;
  final bool isActive;
}
