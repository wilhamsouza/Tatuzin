import 'package:flutter/material.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import '../../domain/entities/report_profitability_row.dart';
import 'report_empty_state.dart';

class ProfitabilityTable extends StatelessWidget {
  const ProfitabilityTable({
    super.key,
    required this.rows,
    this.title = 'Lucratividade',
    this.subtitle = 'Receita, custo e margem por item.',
    this.onRowTap,
  });

  final List<ReportProfitabilityRow> rows;
  final String title;
  final String subtitle;
  final ValueChanged<ReportProfitabilityRow>? onRowTap;

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      title: title,
      subtitle: '$subtitle Toque em uma linha para aprofundar o detalhe.',
      padding: const EdgeInsets.all(14),
      child: rows.isEmpty
          ? const ReportEmptyState(
              title: 'Nada para mostrar',
              message:
                  'A lucratividade vai aparecer aqui quando houver vendas no periodo.',
            )
          : Column(
              children: [
                const _HeaderRow(),
                const Divider(height: 20),
                for (var index = 0; index < rows.length; index++) ...[
                  _ProfitabilityRowTile(
                    row: rows[index],
                    onTap: onRowTap == null ? null : () => onRowTap!(rows[index]),
                  ),
                  if (index < rows.length - 1) const Divider(height: 20),
                ],
              ],
            ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800);
    return Row(
      children: [
        Expanded(flex: 4, child: Text('Item', style: style)),
        Expanded(flex: 2, child: Text('Receita', style: style)),
        Expanded(flex: 2, child: Text('Custo', style: style)),
        Expanded(flex: 2, child: Text('Lucro', style: style)),
        Expanded(flex: 1, child: Text('Margem', style: style)),
      ],
    );
  }
}

class _ProfitabilityRowTile extends StatelessWidget {
  const _ProfitabilityRowTile({required this.row, this.onTap});

  final ReportProfitabilityRow row;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: onTap == null
          ? 'Linha de lucratividade'
          : 'Toque para aprofundar este agrupamento',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.label,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if ((row.description ?? '').trim().isNotEmpty)
                      Text(
                        '${row.description} | ${AppFormatters.quantityFromMil(row.quantityMil)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(AppFormatters.currencyFromCents(row.revenueCents)),
              ),
              Expanded(
                flex: 2,
                child: Text(AppFormatters.currencyFromCents(row.costCents)),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  AppFormatters.currencyFromCents(row.profitCents),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: row.profitCents < 0
                        ? Theme.of(context).colorScheme.error
                        : null,
                  ),
                ),
              ),
              Expanded(
                flex: 1,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Flexible(
                      child: Text(
                        '${row.marginPercent.toStringAsFixed(1)}%',
                        textAlign: TextAlign.right,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (onTap != null) ...[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
