import '../../../app/core/constants/app_constants.dart';
import '../../../app/core/errors/app_exceptions.dart';
import '../../../app/core/formatters/app_formatters.dart';
import '../../../app/core/session/company_context.dart';
import '../../clientes/domain/entities/customer_credit_transaction.dart';
import '../../clientes/domain/entities/client.dart';
import '../../fiado/domain/entities/fiado_detail.dart';
import '../../fiado/domain/entities/fiado_payment_entry.dart';
import '../../vendas/domain/entities/sale_detail.dart';
import '../../vendas/domain/entities/sale_enums.dart';
import '../../vendas/domain/entities/sale_item_detail.dart';
import '../domain/entities/commercial_receipt.dart';
import '../domain/entities/commercial_receipt_detail_line.dart';
import '../domain/entities/commercial_receipt_item.dart';

abstract final class CommercialReceiptMapper {
  static CommercialReceipt fromSaleDetail(
    SaleDetail detail, {
    String? businessName,
    CompanyReceiptSettings receiptSettings =
        const CompanyReceiptSettings.defaults(),
  }) {
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
      businessName: _resolvedBusinessName(businessName, receiptSettings),
      businessDetails: _businessDetails(receiptSettings),
      title: type.title,
      statusLabel: sale.saleType == SaleType.fiado
          ? _fiadoStatusLabel(sale.fiadoStatus)
          : sale.status.label,
      customerName: sale.clientName,
      paymentMethodLabel: sale.wasSettledFullyWithCredit
          ? 'Haver'
          : sale.paymentMethod.label,
      operationDetails: [
        CommercialReceiptDetailLine(label: 'Cupom', value: sale.receiptNumber),
        CommercialReceiptDetailLine(
          label: 'Operacao',
          value: sale.saleType.label,
        ),
        CommercialReceiptDetailLine(
          label: 'Pagamento',
          value: sale.wasSettledFullyWithCredit
              ? 'Haver'
              : sale.paymentMethod.label,
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
              title: _composeItemTitle(item),
              supportingLines: _buildItemSupportingLines(item),
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
        if (sale.creditUsedCents > 0)
          CommercialReceiptDetailLine(
            label: 'Haver utilizado',
            value: AppFormatters.currencyFromCents(sale.creditUsedCents),
          ),
        if (sale.creditGeneratedCents > 0)
          CommercialReceiptDetailLine(
            label: 'Haver gerado',
            value: AppFormatters.currencyFromCents(sale.creditGeneratedCents),
          ),
        if (sale.immediateReceivedCents > 0)
          CommercialReceiptDetailLine(
            label: 'Recebido agora',
            value: AppFormatters.currencyFromCents(sale.immediateReceivedCents),
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
      footerMessage: receiptSettings.footerOrFallback(
        'Comprovante gerado com base em dados persistidos do ERP. Guarde este documento para conferencia.',
      ),
    );
  }

  static CommercialReceipt fromFiadoPayment({
    required FiadoDetail detail,
    required FiadoPaymentEntry entry,
    String? businessName,
    CompanyReceiptSettings receiptSettings =
        const CompanyReceiptSettings.defaults(),
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
      businessName: _resolvedBusinessName(businessName, receiptSettings),
      businessDetails: _businessDetails(receiptSettings),
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
      footerMessage: receiptSettings.footerOrFallback(
        'Recebimento registrado com base no historico persistido da conta a prazo.',
      ),
    );
  }

  static CommercialReceipt fromCustomerCredit({
    required CustomerCreditTransaction transaction,
    required Client? client,
    String? businessName,
    CompanyReceiptSettings receiptSettings =
        const CompanyReceiptSettings.defaults(),
  }) {
    final customerName =
        client?.name ?? transaction.customerName ?? 'Cliente nao informado';
    return CommercialReceipt(
      type: CommercialReceiptType.customerCredit,
      identifier: 'HAV-${transaction.id}',
      issuedAt: transaction.createdAt,
      businessName: _resolvedBusinessName(businessName, receiptSettings),
      businessDetails: _businessDetails(receiptSettings),
      title: CommercialReceiptType.customerCredit.title,
      statusLabel: transaction.isCredit ? 'Credito' : 'Debito',
      customerName: customerName,
      paymentMethodLabel: null,
      operationDetails: [
        CommercialReceiptDetailLine(
          label: 'Lancamento',
          value: 'HAV-${transaction.id}',
        ),
        CommercialReceiptDetailLine(
          label: 'Tipo',
          value: _customerCreditTypeLabel(transaction.type),
        ),
        CommercialReceiptDetailLine(
          label: 'Data e hora',
          value: AppFormatters.shortDateTime(transaction.createdAt),
        ),
        CommercialReceiptDetailLine(label: 'Cliente', value: customerName),
        if (transaction.saleId != null)
          CommercialReceiptDetailLine(
            label: 'Venda vinculada',
            value: '#${transaction.saleId}',
          ),
        if (transaction.fiadoId != null)
          CommercialReceiptDetailLine(
            label: 'Fiado vinculado',
            value: '#${transaction.fiadoId}',
          ),
      ],
      items: const [],
      extraDetails: [
        CommercialReceiptDetailLine(
          label: 'Saldo anterior',
          value: AppFormatters.currencyFromCents(
            transaction.balanceBeforeCents,
          ),
        ),
        CommercialReceiptDetailLine(
          label: 'Saldo atual',
          value: AppFormatters.currencyFromCents(transaction.balanceAfterCents),
        ),
        if (transaction.isReversed)
          const CommercialReceiptDetailLine(
            label: 'Status',
            value: 'Lancamento estornado',
          ),
      ],
      subtotalCents: transaction.absoluteAmountCents,
      discountCents: 0,
      surchargeCents: 0,
      totalCents: transaction.absoluteAmountCents,
      subtotalLabel: transaction.isCredit
          ? 'Credito lançado'
          : 'Debito lançado',
      totalLabel: transaction.isCredit ? 'Credito lançado' : 'Debito lançado',
      notes: transaction.description,
      footerMessage: receiptSettings.footerOrFallback(
        'Lancamento de haver persistido com saldo materializado e extrato transacional.',
      ),
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

  static String _resolvedBusinessName(
    String? businessName,
    CompanyReceiptSettings settings,
  ) {
    return settings.displayNameOrFallback(
      businessName?.trim().isNotEmpty == true
          ? businessName!.trim()
          : AppConstants.appName,
    );
  }

  static List<CommercialReceiptDetailLine> _businessDetails(
    CompanyReceiptSettings settings,
  ) {
    final details = <CommercialReceiptDetailLine>[];
    void addIfVisible({
      required bool visible,
      required String label,
      required String? value,
    }) {
      final normalized = value?.trim();
      if (!visible || normalized == null || normalized.isEmpty) {
        return;
      }
      details.add(CommercialReceiptDetailLine(label: label, value: normalized));
    }

    addIfVisible(
      visible: settings.showDocumentOnReceipt,
      label: 'CPF/CNPJ',
      value: settings.receiptDocument,
    );
    addIfVisible(
      visible: settings.showPhoneOnReceipt,
      label: 'Telefone/WhatsApp',
      value: settings.receiptPhone,
    );
    addIfVisible(
      visible: settings.showAddressOnReceipt,
      label: 'Endereco',
      value: settings.receiptAddress,
    );
    return details;
  }

  static String _customerCreditTypeLabel(String type) {
    switch (type) {
      case CustomerCreditTransactionType.manualCredit:
        return 'Credito manual';
      case CustomerCreditTransactionType.manualDebit:
        return 'Debito manual';
      case CustomerCreditTransactionType.overpaymentCredit:
        return 'Excedente convertido em haver';
      case CustomerCreditTransactionType.saleReturnCredit:
        return 'Devolucao em haver';
      case CustomerCreditTransactionType.saleCancelCredit:
        return 'Cancelamento convertido em haver';
      case CustomerCreditTransactionType.changeLeftAsCredit:
        return 'Troco deixado como haver';
      case CustomerCreditTransactionType.creditUsedInSale:
        return 'Haver usado em venda';
      case CustomerCreditTransactionType.creditReversal:
        return 'Estorno de lancamento';
      default:
        return 'Movimentacao de haver';
    }
  }

  static String _composeItemTitle(SaleItemDetail item) {
    final labels = <String>[
      if ((item.variantSizeSnapshot ?? '').trim().isNotEmpty)
        item.variantSizeSnapshot!.trim(),
      if ((item.variantColorSnapshot ?? '').trim().isNotEmpty)
        item.variantColorSnapshot!.trim(),
    ];

    final variantSuffix = labels.isEmpty ? null : '[${labels.join('/')}]';
    if (variantSuffix == null) {
      return item.productName.trim();
    }

    final productName = item.productName.trim();
    final normalizedBaseName = _stripTrailingVariantSummary(
      productName,
      labels,
    );
    final baseName = normalizedBaseName.trim().isEmpty
        ? productName
        : normalizedBaseName.trim();
    return '$baseName $variantSuffix';
  }

  static List<String> _buildItemSupportingLines(SaleItemDetail item) {
    final lines = <String>[];
    if (item.modifiers.isNotEmpty) {
      for (final modifier in item.modifiers) {
        final option = modifier.optionNameSnapshot;
        final prefix = modifier.adjustmentTypeSnapshot == 'remove'
            ? '- '
            : '+ ';
        final quantityPrefix = modifier.quantity > 1
            ? '${modifier.quantity}x '
            : '';
        lines.add('$prefix$quantityPrefix$option');
      }
    }

    final notes = item.itemNotes;
    if (notes?.trim().isNotEmpty ?? false) {
      lines.add('Obs.: ${notes!.trim()}');
    }
    return lines;
  }

  static String _stripTrailingVariantSummary(
    String productName,
    List<String> labels,
  ) {
    final candidates = <String>[
      ' - ${labels.join(' / ')}',
      ' - ${labels.join('/')}',
      ' – ${labels.join(' / ')}',
      ' – ${labels.join('/')}',
    ];

    final lowerName = productName.toLowerCase();
    for (final candidate in candidates) {
      if (lowerName.endsWith(candidate.toLowerCase())) {
        return productName.substring(0, productName.length - candidate.length);
      }
    }

    return productName;
  }
}
