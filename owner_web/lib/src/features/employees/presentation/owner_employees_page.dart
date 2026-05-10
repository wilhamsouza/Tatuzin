import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/owner_providers.dart';
import '../../../core/widgets/owner_async_view.dart';
import '../../../core/widgets/owner_management_widgets.dart';

class OwnerEmployeesPage extends ConsumerWidget {
  const OwnerEmployeesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employees = ref.watch(ownerEmployeesProvider);
    return OwnerAsyncView(
      value: employees,
      onRetry: () => ref.invalidate(ownerEmployeesProvider),
      builder: (data) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const OwnerPageIntro(
              title: 'Funcionários',
              subtitle:
                  'Acompanhe desempenho da equipe, vendas por pessoa, ticket médio e comissões futuras.',
              icon: Icons.badge_outlined,
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                OwnerMetricCard(
                  title: 'Funcionários ativos',
                  value: data.available ? '${data.count}' : 'Em preparação',
                  detail: data.available
                      ? 'Pessoas cadastradas para operar a empresa.'
                      : 'Os dados de equipe serão liberados em uma próxima atualização.',
                  icon: Icons.groups_outlined,
                  isAvailable: data.available,
                ),
                const OwnerMetricCard(
                  title: 'Vendas por funcionário',
                  value: 'Em preparação',
                  detail: 'Faturamento e quantidade de vendas por pessoa.',
                  icon: Icons.point_of_sale_rounded,
                ),
                const OwnerMetricCard(
                  title: 'Ticket médio',
                  value: 'Em preparação',
                  detail: 'Valor médio por venda em cada atendimento.',
                  icon: Icons.trending_up_rounded,
                ),
                const OwnerMetricCard(
                  title: 'Comissões',
                  value: 'Em preparação',
                  detail: 'Área prevista para acompanhamento futuro.',
                  icon: Icons.payments_outlined,
                ),
              ],
            ),
            const SizedBox(height: 18),
            const OwnerSectionCard(
              title: 'Desempenho da equipe',
              subtitle: 'Leitura gerencial por funcionário.',
              child: OwnerEmptyState(
                title: 'Relatórios de funcionários em preparação',
                message:
                    'Os relatórios de funcionários serão liberados em uma próxima atualização.',
                icon: Icons.insights_rounded,
              ),
            ),
          ],
        );
      },
    );
  }
}
