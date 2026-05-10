import 'package:flutter/material.dart';

import '../../../core/widgets/owner_management_widgets.dart';

class OwnerSalesPage extends StatelessWidget {
  const OwnerSalesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OwnerPageIntro(
          title: 'Vendas',
          subtitle:
              'Acompanhe faturamento, vendas recentes, formas de pagamento e evolução diária.',
          icon: Icons.point_of_sale_rounded,
        ),
        SizedBox(height: 18),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            OwnerMetricCard(
              title: 'Vendas no período',
              value: 'Em preparação',
              detail:
                  'Este indicador será liberado quando os relatórios gerenciais estiverem disponíveis.',
              icon: Icons.shopping_bag_outlined,
            ),
            OwnerMetricCard(
              title: 'Faturamento',
              value: 'Em preparação',
              detail: 'Resumo financeiro de vendas em leitura gerencial.',
              icon: Icons.payments_outlined,
            ),
            OwnerMetricCard(
              title: 'Ticket médio',
              value: 'Em preparação',
              detail: 'Valor médio por venda no período selecionado.',
              icon: Icons.trending_up_rounded,
            ),
            OwnerMetricCard(
              title: 'Formas de pagamento',
              value: 'Em preparação',
              detail: 'Distribuição entre dinheiro, cartão, Pix e fiado.',
              icon: Icons.credit_card_rounded,
            ),
          ],
        ),
        SizedBox(height: 18),
        OwnerSectionCard(
          title: 'Vendas recentes',
          subtitle: 'Últimas vendas registradas pela empresa.',
          child: OwnerEmptyState(
            title: 'Histórico gerencial em preparação',
            message:
                'As vendas recentes aparecerão aqui assim que o backend liberar o relatório do painel da empresa.',
          ),
        ),
        SizedBox(height: 18),
        OwnerSectionCard(
          title: 'Vendas por dia',
          subtitle: 'Tendência de faturamento para comparar períodos.',
          child: OwnerEmptyState(
            title: 'Gráfico ainda indisponível',
            message:
                'Este indicador será liberado quando a API de relatórios de vendas estiver pronta.',
            icon: Icons.show_chart_rounded,
          ),
        ),
      ],
    );
  }
}
