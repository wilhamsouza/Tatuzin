import 'package:flutter/material.dart';

import '../../../core/widgets/owner_management_widgets.dart';

class OwnerFinancePage extends StatelessWidget {
  const OwnerFinancePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OwnerPageIntro(
          title: 'Fiado e financeiro',
          subtitle:
              'Acompanhe contas a receber, valores vencidos e saúde financeira da operação.',
          icon: Icons.account_balance_wallet_rounded,
        ),
        SizedBox(height: 18),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            OwnerMetricCard(
              title: 'Total em aberto',
              value: 'Em preparação',
              detail: 'Valores ainda não recebidos.',
              icon: Icons.receipt_long_outlined,
            ),
            OwnerMetricCard(
              title: 'Vencidos',
              value: 'Em preparação',
              detail: 'Contas que precisam de atenção.',
              icon: Icons.warning_amber_rounded,
            ),
            OwnerMetricCard(
              title: 'A receber',
              value: 'Em preparação',
              detail: 'Previsão de recebimento por período.',
              icon: Icons.event_available_outlined,
            ),
            OwnerMetricCard(
              title: 'Caixa',
              value: 'Em preparação',
              detail: 'Resumo gerencial das sessões de caixa.',
              icon: Icons.point_of_sale_rounded,
            ),
          ],
        ),
        SizedBox(height: 18),
        OwnerSectionCard(
          title: 'Clientes com maior saldo',
          subtitle: 'Lista de contas em aberto por cliente.',
          child: OwnerEmptyState(
            title: 'Relatório financeiro em preparação',
            message:
                'Este indicador será liberado quando os dados gerenciais de fiado e caixa estiverem disponíveis.',
          ),
        ),
      ],
    );
  }
}
