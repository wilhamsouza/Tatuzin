import 'commercial_receipt_detail_line.dart';
import 'commercial_receipt_item.dart';

enum CommercialReceiptType { cashSale, creditSale, fiadoPayment }

extension CommercialReceiptTypeX on CommercialReceiptType {
  String get label {
    switch (this) {
      case CommercialReceiptType.cashSale:
        return 'Venda a vista';
      case CommercialReceiptType.creditSale:
        return 'Venda fiado';
      case CommercialReceiptType.fiadoPayment:
        return 'Recebimento de fiado';
    }
  }

  String get title {
    switch (this) {
      case CommercialReceiptType.cashSale:
        return 'Comprovante de venda a vista';
      case CommercialReceiptType.creditSale:
        return 'Comprovante de venda fiado';
      case CommercialReceiptType.fiadoPayment:
        return 'Comprovante de recebimento';
    }
  }

  String get filePrefix {
    switch (this) {
      case CommercialReceiptType.cashSale:
        return 'comprovante_venda_vista';
      case CommercialReceiptType.creditSale:
        return 'comprovante_venda_fiado';
      case CommercialReceiptType.fiadoPayment:
        return 'comprovante_recebimento_fiado';
    }
  }
}

class CommercialReceipt {
  const CommercialReceipt({
    required this.type,
    required this.identifier,
    required this.issuedAt,
    required this.businessName,
    required this.title,
    required this.statusLabel,
    required this.operationDetails,
    required this.items,
    required this.extraDetails,
    required this.subtotalCents,
    required this.discountCents,
    required this.surchargeCents,
    required this.totalCents,
    required this.subtotalLabel,
    required this.totalLabel,
    required this.footerMessage,
    this.customerName,
    this.paymentMethodLabel,
    this.notes,
  });

  final CommercialReceiptType type;
  final String identifier;
  final DateTime issuedAt;
  final String businessName;
  final String title;
  final String statusLabel;
  final String? customerName;
  final String? paymentMethodLabel;
  final List<CommercialReceiptDetailLine> operationDetails;
  final List<CommercialReceiptItem> items;
  final List<CommercialReceiptDetailLine> extraDetails;
  final int subtotalCents;
  final int discountCents;
  final int surchargeCents;
  final int totalCents;
  final String subtotalLabel;
  final String totalLabel;
  final String? notes;
  final String footerMessage;

  bool get hasItems => items.isNotEmpty;
}
