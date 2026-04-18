class ReportSalesTrendPoint {
  const ReportSalesTrendPoint({
    required this.bucketStart,
    required this.bucketEndExclusive,
    required this.label,
    required this.salesCount,
    required this.grossSalesCents,
    required this.netSalesCents,
  });

  final DateTime bucketStart;
  final DateTime bucketEndExclusive;
  final String label;
  final int salesCount;
  final int grossSalesCents;
  final int netSalesCents;
}
