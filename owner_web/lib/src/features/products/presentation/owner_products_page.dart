import 'package:flutter/material.dart';

import '../../../core/widgets/owner_management_widgets.dart';

class OwnerProductsPage extends StatelessWidget {
  const OwnerProductsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OwnerPageIntro(
          title: 'Produtos e estoque',
          subtitle:
              'Monitore produtos mais vendidos, estoque baixo, itens zerados e categorias.',
          icon: Icons.inventory_2_outlined,
        ),
        SizedBox(height: 18),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            OwnerMetricCard(
              title: 'Produtos mais vendidos',
              value: 'Em preparação',
              detail: 'Ranking de vendas por produto.',
              icon: Icons.leaderboard_outlined,
            ),
            OwnerMetricCard(
              title: 'Estoque baixo',
              value: 'Em preparação',
              detail: 'Itens abaixo do mínimo definido.',
              icon: Icons.inventory_outlined,
            ),
            OwnerMetricCard(
              title: 'Zerados',
              value: 'Em preparação',
              detail: 'Produtos sem saldo disponível.',
              icon: Icons.remove_shopping_cart_outlined,
            ),
            OwnerMetricCard(
              title: 'Sem movimentação',
              value: 'Em preparação',
              detail: 'Produtos parados no período.',
              icon: Icons.pause_circle_outline_rounded,
            ),
          ],
        ),
        SizedBox(height: 18),
        OwnerSectionCard(
          title: 'Categorias',
          subtitle: 'Desempenho e composição do catálogo.',
          child: OwnerEmptyState(
            title: 'Indicadores de estoque em preparação',
            message:
                'Os dados de produtos, categorias e estoque serão liberados em uma próxima atualização.',
          ),
        ),
      ],
    );
  }
}
