import 'package:flutter/material.dart';

import '../../../core/widgets/owner_management_widgets.dart';

class OwnerReportsPage extends StatelessWidget {
  const OwnerReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OwnerPageIntro(
          title: 'Relatórios',
          subtitle:
              'Central de relatórios gerenciais por tema para acompanhar a empresa.',
          icon: Icons.assessment_outlined,
        ),
        SizedBox(height: 18),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            OwnerReportThemeCard(
              title: 'Vendas',
              description: 'Faturamento, formas de pagamento e evolução.',
              icon: Icons.point_of_sale_rounded,
            ),
            OwnerReportThemeCard(
              title: 'Produtos',
              description: 'Itens vendidos, margem e desempenho.',
              icon: Icons.inventory_2_outlined,
            ),
            OwnerReportThemeCard(
              title: 'Caixa',
              description: 'Sessões, entradas, saídas e conferências.',
              icon: Icons.account_balance_wallet_outlined,
            ),
            OwnerReportThemeCard(
              title: 'Estoque',
              description: 'Saldo, rupturas, giro e alertas.',
              icon: Icons.warehouse_outlined,
            ),
            OwnerReportThemeCard(
              title: 'Clientes',
              description: 'Recorrência, fiado e relacionamento.',
              icon: Icons.people_alt_outlined,
            ),
            OwnerReportThemeCard(
              title: 'Compras',
              description: 'Fornecedores, reposição e custos.',
              icon: Icons.local_shipping_outlined,
            ),
            OwnerReportThemeCard(
              title: 'Lucratividade',
              description: 'Receita, custo e margem por período.',
              icon: Icons.trending_up_rounded,
            ),
            OwnerReportThemeCard(
              title: 'Funcionários',
              description: 'Vendas, ticket médio e desempenho por pessoa.',
              icon: Icons.badge_outlined,
            ),
          ],
        ),
        SizedBox(height: 18),
        OwnerEmptyState(
          title: 'Relatórios gerenciais em preparação',
          message:
              'Cada tema será liberado conforme as fontes de dados gerenciais ficarem disponíveis.',
          icon: Icons.insights_rounded,
        ),
      ],
    );
  }
}
