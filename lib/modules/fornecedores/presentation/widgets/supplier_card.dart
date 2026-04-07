import 'package:flutter/material.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/widgets/app_status_badge.dart';
import '../../domain/entities/supplier.dart';

class SupplierCard extends StatelessWidget {
  const SupplierCard({
    super.key,
    required this.supplier,
    this.onTap,
    this.trailing,
  });

  final Supplier supplier;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final subtitleParts = <String>[
      if (supplier.tradeName?.trim().isNotEmpty ?? false) supplier.tradeName!,
      if (supplier.phone?.trim().isNotEmpty ?? false) supplier.phone!,
    ];

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          supplier.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (subtitleParts.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            subtitleParts.join(' | '),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  trailing ??
                      AppStatusBadge(
                        label: supplier.isActive ? 'Ativo' : 'Inativo',
                        tone: supplier.isActive
                            ? AppStatusTone.success
                            : AppStatusTone.neutral,
                      ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  AppStatusBadge(
                    label:
                        '${supplier.pendingPurchasesCount} compra(s) pendente(s)',
                    tone: supplier.pendingPurchasesCount > 0
                        ? AppStatusTone.warning
                        : AppStatusTone.neutral,
                  ),
                  AppStatusBadge(
                    label: AppFormatters.currencyFromCents(
                      supplier.pendingAmountCents,
                    ),
                    tone: supplier.pendingAmountCents > 0
                        ? AppStatusTone.info
                        : AppStatusTone.neutral,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
