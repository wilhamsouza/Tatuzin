import 'package:flutter/material.dart';

import '../../../../app/core/formatters/app_formatters.dart';

class PurchaseSummary extends StatelessWidget {
  const PurchaseSummary({
    super.key,
    required this.subtotalCents,
    required this.discountCents,
    required this.surchargeCents,
    required this.freightCents,
    required this.finalAmountCents,
    required this.paidAmountCents,
    required this.pendingAmountCents,
    this.compact = false,
  });

  final int subtotalCents;
  final int discountCents;
  final int surchargeCents;
  final int freightCents;
  final int finalAmountCents;
  final int paidAmountCents;
  final int pendingAmountCents;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[
      _SummaryLine(
        label: 'Subtotal',
        value: AppFormatters.currencyFromCents(subtotalCents),
      ),
      _SummaryLine(
        label: 'Desconto',
        value: AppFormatters.currencyFromCents(discountCents),
      ),
      _SummaryLine(
        label: 'Acrescimo',
        value: AppFormatters.currencyFromCents(surchargeCents),
      ),
      _SummaryLine(
        label: 'Frete',
        value: AppFormatters.currencyFromCents(freightCents),
      ),
      _SummaryLine(
        label: 'Valor final',
        value: AppFormatters.currencyFromCents(finalAmountCents),
        emphasize: true,
      ),
      _SummaryLine(
        label: 'Valor pago',
        value: AppFormatters.currencyFromCents(paidAmountCents),
      ),
      _SummaryLine(
        label: 'Pendente',
        value: AppFormatters.currencyFromCents(pendingAmountCents),
        emphasize: pendingAmountCents > 0,
      ),
    ];

    return Column(
      children: [
        for (var index = 0; index < rows.length; index++) ...[
          rows[index],
          if (index < rows.length - 1) Divider(height: compact ? 18 : 24),
        ],
      ],
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          value,
          textAlign: TextAlign.right,
          style: emphasize
              ? theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                )
              : theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
        ),
      ],
    );
  }
}
