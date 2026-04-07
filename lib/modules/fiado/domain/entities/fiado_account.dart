class FiadoAccount {
  const FiadoAccount({
    required this.id,
    required this.uuid,
    required this.saleId,
    required this.clientId,
    required this.clientName,
    required this.originalCents,
    required this.openCents,
    required this.dueDate,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.settledAt,
    required this.receiptNumber,
  });

  final int id;
  final String uuid;
  final int saleId;
  final int clientId;
  final String clientName;
  final int originalCents;
  final int openCents;
  final DateTime dueDate;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? settledAt;
  final String receiptNumber;

  bool get isSettled => status == 'quitado';
  bool get isCancelled => status == 'cancelado';
}
