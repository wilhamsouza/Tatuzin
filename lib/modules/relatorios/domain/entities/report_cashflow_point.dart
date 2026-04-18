class ReportCashflowPoint {
  const ReportCashflowPoint({
    required this.bucketStart,
    required this.bucketEndExclusive,
    required this.label,
    required this.inflowCents,
    required this.outflowCents,
    required this.netCents,
  });

  final DateTime bucketStart;
  final DateTime bucketEndExclusive;
  final String label;
  final int inflowCents;
  final int outflowCents;
  final int netCents;
}
