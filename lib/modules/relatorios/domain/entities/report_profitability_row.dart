import 'report_filter.dart';

class ReportProfitabilityRow {
  const ReportProfitabilityRow({
    required this.grouping,
    required this.label,
    required this.quantityMil,
    required this.revenueCents,
    required this.costCents,
    required this.profitCents,
    required this.marginBasisPoints,
    this.description,
    this.productId,
    this.variantId,
    this.categoryId,
  });

  final ReportGrouping grouping;
  final String label;
  final String? description;
  final int? productId;
  final int? variantId;
  final int? categoryId;
  final int quantityMil;
  final int revenueCents;
  final int costCents;
  final int profitCents;
  final int marginBasisPoints;

  double get marginPercent => marginBasisPoints / 100;
}
