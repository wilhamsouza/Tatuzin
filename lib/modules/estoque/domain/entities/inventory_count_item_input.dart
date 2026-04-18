class InventoryCountItemInput {
  const InventoryCountItemInput({
    required this.sessionId,
    required this.productId,
    required this.productVariantId,
    required this.countedStockMil,
    this.notes,
  });

  final int sessionId;
  final int productId;
  final int? productVariantId;
  final int countedStockMil;
  final String? notes;
}
