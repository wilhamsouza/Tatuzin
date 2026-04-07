import '../../../app/core/constants/app_constants.dart';
import '../../../app/core/errors/app_exceptions.dart';
import '../../../app/core/formatters/app_formatters.dart';
import '../../fiado/domain/entities/fiado_detail.dart';
import '../../fiado/domain/entities/fiado_payment_entry.dart';
import '../../vendas/domain/entities/sale_detail.dart';
import '../../vendas/domain/entities/sale_enums.dart';
import '../domain/entities/commercial_receipt.dart';
import '../domain/entities/commercial_receipt_detail_line.dart';
import '../domain/entities/commercial_receipt_item.dart';

abstract final class CommercialReceiptMapper {
  static CommercialReceipt fromSaleDetail(SaleDetail detail) {
    final sale = detail.sale;

    if (sale.status == SaleStatus.cancelled) {
      throw const ValidationException(
        'Vendas canceladas nao possuem comprovante comercial disponivel.',
      );
    }

    final type = sale.saleType == SaleType.fiado
        ? CommercialReceiptType.creditSale
        : CommercialReceiptType.cashSale;

    return CommercialReceipt(
      type: type,
      identifier: sale.receiptNumber,
      issuedAt: sale.soldAt,
      businessName: AppConstants.appName,
      title: type.title,
      statusLabel: sale.saleType == SaleType.fiado
          ? _fiadoStatusLabel(sale.fiadoStatus)
          : sale.status.label,
      customerName: sale.clientName,
      paymentMethodLabel: sale.paymentMethod.label,
      operationDetails: [
        CommercialReceiptDetailLine(label: 'Cupom', value: sale.receiptNumber),
        CommercialReceiptDetailLine(
          label: 'Operacao',
          value: sale.saleType.label,
        ),
        CommercialReceiptDetailLine(
          label: 'Pagamento',
          value: sale.paymentMethod.label,
        ),
        CommercialReceiptDetailLine(
          label: 'Data e hora',
          value: AppFormatters.shortDateTime(sale.soldAt),
        ),
        CommercialReceiptDetailLine(
          label: 'Cliente',
          value: sale.clientName ?? 'Cliente nao informado',
        ),
        if (sale.saleType == SaleType.fiado && sale.fiadoDueDate != null)
          CommercialReceiptDetailLine(
            label: 'Vencimento',
            value: AppFormatters.shortDate(sale.fiadoDueDate!),
          ),
      ],
      items: detail.items
          .map(
            (item) => CommercialReceiptItem(
              description: item.productName,
              quantityLabel:
                  '${AppFormatters.quantityFromMil(item.quantityMil)} ${item.unitMeasure}',
              unitPriceCents: item.unitPriceCents,
              subtotalCents: item.subtotalCents,
            ),
          )
          .toList(growable: false),
      extraDetails: [
        if (sale.saleType == SaleType.fiado && sale.fiadoStatus != null)
          CommercialReceiptDetailLine(
            label: 'Status da nota',
            value: _fiadoStatusLabel(sale.fiadoStatus),
          ),
        if (sale.saleType == SaleType.fiado && sale.fiadoOpenCents != null)
          CommercialReceiptDetailLine(
            label: 'Saldo em aberto',
            value: AppFormatters.currencyFromCents(sale.fiadoOpenCents!),
          ),
      ],
      subtotalCents: sale.totalCents,
      discountCents: sale.discountCents,
      surchargeCents: sale.surchargeCents,
      totalCents: sale.finalCents,
      subtotalLabel: 'Subtotal',
      totalLabel: 'Total final',
      notes: sale.notes,
      footerMessage:
          'Comprovante gerado com base em dados persistidos do ERP. Guarde este documento para conferencia.',
    );
  }

  static CommercialReceipt fromFiadoPayment({
    required FiadoDetail detail,
    required FiadoPaymentEntry entry,
  }) {
    if (entry.entryType != 'pagamento') {
      throw const ValidationException(
        'Somente pagamentos registrados possuem comprovante disponivel.',
      );
    }

    final settledAfterPayment = detail.account.isSettled;
    final paymentStatus = settledAfterPayment
        ? 'Recebimento total'
        : 'Recebimento parcial';

    return CommercialReceipt(
      type: CommercialReceiptType.fiadoPayment,
      identifier: '${detail.account.receiptNumber}-P${entry.id}',
      issuedAt: entry.registeredAt,
      businessName: AppConstants.appName,
      title: CommercialReceiptType.fiadoPayment.title,
      statusLabel: paymentStatus,
      customerName: detail.account.clientName,
      paymentMethodLabel: entry.paymentMethod?.label ?? 'Nao informado',
      operationDetails: [
        CommercialReceiptDetailLine(
          label: 'Cupom de origem',
          value: detail.account.receiptNumber,
        ),
        CommercialReceiptDetailLine(
          label: 'Operacao',
          value: CommercialReceiptType.fiadoPayment.label,
        ),
        CommercialReceiptDetailLine(
          label: 'Pagamento',
          value: entry.paymentMethod?.label ?? 'Nao informado',
        ),
        CommercialReceiptDetailLine(
          label: 'Data e hora',
          value: AppFormatters.shortDateTime(entry.registeredAt),
        ),
        CommercialReceiptDetailLine(
          label: 'Cliente',
          value: detail.account.clientName,
        ),
      ],
      items: const [],
      extraDetails: [
        CommercialReceiptDetailLine(
          label: 'Valor original da nota',
          value: AppFormatters.currencyFromCents(detail.account.originalCents),
        ),
        CommercialReceiptDetailLine(
          label: 'Saldo atual',
          value: AppFormatters.currencyFromCents(detail.account.openCents),
        ),
        CommercialReceiptDetailLine(
          label: 'Vencimento',
          value: AppFormatters.shortDate(detail.account.dueDate),
        ),
        CommercialReceiptDetailLine(
          label: 'Status atual da nota',
          value: _fiadoStatusLabel(detail.account.status),
        ),
      ],
      subtotalCents: entry.amountCents,
      discountCents: 0,
      surchargeCents: 0,
      totalCents: entry.amountCents,
      subtotalLabel: 'Valor recebido',
      totalLabel: 'Valor recebido',
      notes: entry.notes,
      footerMessage:
          'Recebimento registrado com base no historico persistido da conta a prazo.',
    );
  }

  static String _fiadoStatusLabel(String? status) {
    switch (status) {
      case 'quitado':
        return 'Quitado';
      case 'parcial':
        return 'Parcial';
      case 'cancelado':
        return 'Cancelado';
      default:
        return 'Pendente';
    }
  }
}
