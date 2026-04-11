class CommercialReceiptItem {
  const CommercialReceiptItem({
    required this.title,
    this.supportingLines = const <String>[],
    required this.quantityLabel,
    required this.unitPriceCents,
    required this.subtotalCents,
  });

  final String title;
  final List<String> supportingLines;
  final String quantityLabel;
  final int unitPriceCents;
  final int subtotalCents;
}
