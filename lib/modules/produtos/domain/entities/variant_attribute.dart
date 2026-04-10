class VariantAttribute {
  const VariantAttribute({
    required this.id,
    required this.uuid,
    required this.productId,
    required this.key,
    required this.value,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String uuid;
  final int productId;
  final String key;
  final String value;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class VariantAttributeInput {
  const VariantAttributeInput({
    required this.productId,
    required this.key,
    required this.value,
  });

  final int productId;
  final String key;
  final String value;
}
