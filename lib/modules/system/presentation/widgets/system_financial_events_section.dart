import 'package:flutter/material.dart';

import '../../../../app/core/sync/sync_queue_feature_summary.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import 'sync_feature_card.dart';

class SystemFinancialEventsSection extends StatelessWidget {
  const SystemFinancialEventsSection({
    required this.canRunManualSync,
    required this.isLoading,
    required this.financialEventSummary,
    required this.cashEventSummary,
    required this.onFinancialSync,
    required this.onFinancialRetry,
    required this.onCashEventSync,
    super.key,
  });

  final bool canRunManualSync;
  final bool isLoading;
  final SyncQueueFeatureSummary? financialEventSummary;
  final SyncQueueFeatureSummary? cashEventSummary;
  final VoidCallback onFinancialSync;
  final VoidCallback onFinancialRetry;
  final VoidCallback onCashEventSync;

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      title: 'Eventos financeiros remotos',
      subtitle:
          'Cancelamentos de venda e pagamentos de fiado entram em uma trilha unica de eventos financeiros. O backend apenas espelha os eventos; caixa, fiado, lucro e relatorios continuam locais.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: isLoading || !canRunManualSync
                    ? null
                    : onFinancialSync,
                icon: const Icon(Icons.account_balance_wallet_outlined),
                label: const Text('Sincronizar eventos'),
              ),
              OutlinedButton.icon(
                onPressed: isLoading || !canRunManualSync
                    ? null
                    : onFinancialRetry,
                icon: const Icon(Icons.restart_alt_rounded),
                label: const Text('Reprocessar eventos'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SyncFeatureCard(
            title: 'Eventos financeiros',
            summary: financialEventSummary,
            description: canRunManualSync
                ? 'Inclui cancelamentos de venda e pagamentos de fiado com idempotencia por localUuid, sem recalcular saldo, lucro ou relatorios no backend.'
                : 'Entre com login remoto e ative o modo hibrido pronto para espelhar os eventos financeiros.',
            buttonLabel: 'Sincronizar eventos',
            isEnabled: canRunManualSync,
            isLoading: isLoading,
            onPressed: onFinancialSync,
          ),
          const SizedBox(height: 12),
          SyncFeatureCard(
            title: 'Espelho de caixa preservado',
            summary: cashEventSummary,
            description: canRunManualSync
                ? 'O espelhamento de caixa ja existente foi preservado e continua isolado da contabilidade local.'
                : 'Entre com login remoto e ative o modo hibrido pronto para espelhar os eventos de caixa.',
            buttonLabel: 'Sincronizar caixa',
            isEnabled: canRunManualSync,
            isLoading: isLoading,
            onPressed: onCashEventSync,
          ),
        ],
      ),
    );
  }
}
