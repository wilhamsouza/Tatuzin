class ReportSoldProductSummary {
  const ReportSoldProductSummary({
    required this.productId,
    required this.productName,
    required this.quantityMil,
    required this.unitMeasure,
    required this.soldAmountCents,
    required this.totalCostCents,
  });

  final int? productId;
  final String productName;
  final int quantityMil;
  final String unitMeasure;
  final int soldAmountCents;
  final int totalCostCents;
}
