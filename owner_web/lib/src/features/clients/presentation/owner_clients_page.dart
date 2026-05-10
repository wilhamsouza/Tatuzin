import 'package:flutter/material.dart';

import '../../../core/widgets/owner_management_widgets.dart';

class OwnerClientsPage extends StatelessWidget {
  const OwnerClientsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OwnerPageIntro(
          title: 'Clientes / CRM',
          subtitle:
              'Veja relacionamento, recorrência e oportunidades de reativação da base de clientes.',
          icon: Icons.people_alt_rounded,
        ),
        SizedBox(height: 18),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            OwnerMetricCard(
              title: 'Clientes ativos',
              value: 'Em preparação',
              detail: 'Clientes com compras recentes no período.',
              icon: Icons.person_pin_circle_outlined,
            ),
            OwnerMetricCard(
              title: 'Clientes recorrentes',
              value: 'Em preparação',
              detail: 'Clientes que compraram mais de uma vez.',
              icon: Icons.repeat_rounded,
            ),
            OwnerMetricCard(
              title: 'Clientes inativos',
              value: 'Em preparação',
              detail: 'Base sem compras recentes para recuperar.',
              icon: Icons.person_off_outlined,
            ),
            OwnerMetricCard(
              title: 'Clientes com fiado',
              value: 'Em preparação',
              detail: 'Clientes com valores em aberto.',
              icon: Icons.request_quote_outlined,
            ),
          ],
        ),
        SizedBox(height: 18),
        OwnerSectionCard(
          title: 'Top clientes',
          subtitle: 'Clientes com maior frequência ou valor comprado.',
          child: OwnerEmptyState(
            title: 'Indicadores de CRM em preparação',
            message:
                'Os indicadores de CRM serão liberados em uma próxima atualização.',
          ),
        ),
      ],
    );
  }
}
