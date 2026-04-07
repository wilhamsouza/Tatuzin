import 'package:flutter/material.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import '../../../../app/core/widgets/app_status_badge.dart';
import '../../domain/entities/commercial_receipt.dart';
import '../../domain/entities/commercial_receipt_item.dart';

class CommercialReceiptView extends StatelessWidget {
  const CommercialReceiptView({
    super.key,
    required this.receipt,
    this.showSuccessBanner = false,
  });

  final CommercialReceipt receipt;
  final bool showSuccessBanner;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        if (showSuccessBanner) ...[
          Card(
            color: theme.colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Operacao concluida. O comprovante ja esta disponivel para visualizar, salvar em PDF ou compartilhar.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: const LinearGradient(
              colors: [Color(0xFF6C4CF1), Color(0xFF8B5CF6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppStatusBadge(
                label: receipt.statusLabel,
                tone: _toneForReceipt(receipt),
                icon: Icons.receipt_long_rounded,
              ),
              const SizedBox(height: 14),
              Text(
                receipt.businessName,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                receipt.title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Documento ${receipt.identifier}',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: Colors.white.withValues(alpha: 0.88),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                AppFormatters.shortDateTime(receipt.issuedAt),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.82),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AppSectionCard(
          title: 'Dados da operacao',
          subtitle: 'Informacoes persistidas do movimento comercial.',
          child: Column(
            children: [
              for (final detail in receipt.operationDetails) ...[
                _ReceiptInfoRow(label: detail.label, value: detail.value),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
        if (receipt.hasItems) ...[
          const SizedBox(height: 16),
          AppSectionCard(
            title: 'Itens',
            subtitle: 'Lista comercial da operacao registrada.',
            child: Column(
              children: [
                for (var index = 0; index < receipt.items.length; index++) ...[
                  _ReceiptItemTile(item: receipt.items[index]),
                  if (index != receipt.items.length - 1)
                    const Divider(height: 24),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        AppSectionCard(
          title: 'Resumo financeiro',
          subtitle: 'Conferencia dos valores finais do comprovante.',
          child: Column(
            children: [
              _ReceiptInfoRow(
                label: receipt.subtotalLabel,
                value: AppFormatters.currencyFromCents(receipt.subtotalCents),
              ),
              if (receipt.discountCents > 0) ...[
                const SizedBox(height: 10),
                _ReceiptInfoRow(
                  label: 'Desconto',
                  value: AppFormatters.currencyFromCents(receipt.discountCents),
                ),
              ],
              if (receipt.surchargeCents > 0) ...[
                const SizedBox(height: 10),
                _ReceiptInfoRow(
                  label: 'Acrescimo',
                  value: AppFormatters.currencyFromCents(
                    receipt.surchargeCents,
                  ),
                ),
              ],
              if (receipt.paymentMethodLabel != null) ...[
                const SizedBox(height: 10),
                _ReceiptInfoRow(
                  label: 'Forma de pagamento',
                  value: receipt.paymentMethodLabel!,
                ),
              ],
              const Divider(height: 24),
              _ReceiptTotalRow(
                label: receipt.totalLabel,
                value: AppFormatters.currencyFromCents(receipt.totalCents),
              ),
            ],
          ),
        ),
        if (receipt.extraDetails.isNotEmpty) ...[
          const SizedBox(height: 16),
          AppSectionCard(
            title: 'Informacoes adicionais',
            subtitle: 'Contexto util para conferencia e reenvio.',
            child: Column(
              children: [
                for (final detail in receipt.extraDetails) ...[
                  _ReceiptInfoRow(label: detail.label, value: detail.value),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ],
        if (receipt.notes?.isNotEmpty ?? false) ...[
          const SizedBox(height: 16),
          AppSectionCard(
            title: 'Observacoes',
            subtitle: 'Anotacoes registradas na operacao original.',
            child: Text(receipt.notes!),
          ),
        ],
        const SizedBox(height: 16),
        AppSectionCard(
          title: 'Rodape',
          subtitle: 'Mensagem padronizada do documento.',
          child: Text(receipt.footerMessage),
        ),
      ],
    );
  }

  AppStatusTone _toneForReceipt(CommercialReceipt receipt) {
    switch (receipt.type) {
      case CommercialReceiptType.cashSale:
        return AppStatusTone.success;
      case CommercialReceiptType.creditSale:
        return AppStatusTone.warning;
      case CommercialReceiptType.fiadoPayment:
        return AppStatusTone.info;
    }
  }
}

class _ReceiptItemTile extends StatelessWidget {
  const _ReceiptItemTile({required this.item});

  final CommercialReceiptItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.description, style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                item.quantityLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              AppFormatters.currencyFromCents(item.unitPriceCents),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            Text(
              AppFormatters.currencyFromCents(item.subtotalCents),
              style: theme.textTheme.titleMedium,
            ),
          ],
        ),
      ],
    );
  }
}

class _ReceiptInfoRow extends StatelessWidget {
  const _ReceiptInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: theme.textTheme.titleMedium,
          ),
        ),
      ],
    );
  }
}

class _ReceiptTotalRow extends StatelessWidget {
  const _ReceiptTotalRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Text(
          value,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}
