class ReportBreakdownRow {
  const ReportBreakdownRow({
    required this.label,
    this.description,
    this.primaryId,
    this.secondaryId,
    this.amountCents = 0,
    this.quantityMil = 0,
    this.count = 0,
  });

  final String label;
  final String? description;
  final int? primaryId;
  final int? secondaryId;
  final int amountCents;
  final int quantityMil;
  final int count;
}
