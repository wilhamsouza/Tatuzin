class CommercialReceiptItem {
  const CommercialReceiptItem({
    required this.description,
    required this.quantityLabel,
    required this.unitPriceCents,
    required this.subtotalCents,
  });

  final String description;
  final String quantityLabel;
  final int unitPriceCents;
  final int subtotalCents;
}
