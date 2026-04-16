import 'package:flutter/material.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/sync/sync_status.dart';
import '../../../../app/core/widgets/app_status_badge.dart';
import '../../domain/entities/purchase.dart';
import 'purchase_status_badge.dart';

class PurchaseCard extends StatelessWidget {
  const PurchaseCard({
    super.key,
    required this.purchase,
    this.onTap,
    this.trailing,
  });

  final Purchase purchase;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
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
                          purchase.supplierName,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _subtitleText(),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (_showSyncBadge) ...[
                          const SizedBox(height: 8),
                          AppStatusBadge(
                            label: _syncBadgeLabel,
                            tone: _syncBadgeTone,
                            icon: _syncBadgeIcon,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  trailing ?? PurchaseStatusBadge(status: purchase.status),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _Metric(
                      label: 'Valor final',
                      value: AppFormatters.currencyFromCents(
                        purchase.finalAmountCents,
                      ),
                    ),
                  ),
                  Expanded(
                    child: _Metric(
                      label: 'Pago',
                      value: AppFormatters.currencyFromCents(
                        purchase.paidAmountCents,
                      ),
                    ),
                  ),
                  Expanded(
                    child: _Metric(
                      label: 'Pendente',
                      value: AppFormatters.currencyFromCents(
                        purchase.pendingAmountCents,
                      ),
                    ),
                  ),
                ],
              ),
              if (purchase.syncIssueMessage?.trim().isNotEmpty ?? false) ...[
                const SizedBox(height: 14),
                Text(
                  purchase.syncIssueMessage!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _subtitleText() {
    final parts = <String>[
      AppFormatters.shortDate(purchase.purchasedAt),
      '${purchase.itemsCount} item(ns)',
      if (purchase.documentNumber?.trim().isNotEmpty ?? false)
        'Doc. ${purchase.documentNumber}',
    ];
    return parts.join(' | ');
  }

  bool get _showSyncBadge {
    return purchase.isLocalOnly ||
        purchase.syncStatus == SyncStatus.syncError ||
        purchase.syncStatus == SyncStatus.pendingUpload ||
        purchase.syncStatus == SyncStatus.pendingUpdate ||
        purchase.syncStatus == SyncStatus.conflict;
  }

  String get _syncBadgeLabel {
    if (purchase.isLocalOnly) {
      return 'Compra local com insumo';
    }
    return switch (purchase.syncStatus) {
      SyncStatus.pendingUpload => 'Sync pendente',
      SyncStatus.pendingUpdate => 'Atualizacao pendente',
      SyncStatus.syncError => 'Falha no sync',
      SyncStatus.conflict => 'Conflito de sync',
      _ => 'Aguardando sync',
    };
  }

  AppStatusTone get _syncBadgeTone {
    return switch (purchase.syncStatus) {
      null => AppStatusTone.info,
      SyncStatus.syncError || SyncStatus.conflict => AppStatusTone.warning,
      _ => AppStatusTone.info,
    };
  }

  IconData get _syncBadgeIcon {
    return switch (purchase.syncStatus) {
      null => Icons.sync_problem_rounded,
      SyncStatus.syncError => Icons.cloud_off_rounded,
      SyncStatus.conflict => Icons.warning_amber_rounded,
      _ => Icons.sync_problem_rounded,
    };
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(value, style: theme.textTheme.titleSmall),
      ],
    );
  }
}
