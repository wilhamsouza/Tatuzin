import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/owner_providers.dart';
import '../../../core/models/owner_models.dart';
import '../../../core/widgets/owner_async_view.dart';
import '../../../core/widgets/owner_formatters.dart';
import '../../../core/widgets/owner_management_widgets.dart';

class OwnerEmployeesPage extends ConsumerWidget {
  const OwnerEmployeesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employees = ref.watch(ownerEmployeeReportsProvider);
    return OwnerAsyncView(
      value: employees,
      onRetry: () => ref.invalidate(ownerEmployeeReportsProvider),
      builder: (data) {
        final totalAmount = data.topEmployees.fold<int>(
          0,
          (total, item) => total + item.salesAmountCents,
        );
        final totalCount = data.topEmployees.fold<int>(
          0,
          (total, item) => total + item.salesCount,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const OwnerPageIntro(
              title: 'Funcionários',
              subtitle:
                  'Acompanhe desempenho da equipe, vendas por pessoa e ticket médio.',
              icon: Icons.badge_outlined,
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                OwnerMetricCard(
                  title: 'Funcionários com vendas',
                  value: data.available
                      ? '${data.topEmployees.length}'
                      : 'Em preparação',
                  detail: data.available
                      ? 'Pessoas com vendas vinculadas no período.'
                      : 'Aguardando vendas vinculadas aos usuários.',
                  icon: Icons.groups_outlined,
                  isAvailable: data.available,
                ),
                OwnerMetricCard(
                  title: 'Vendas por funcionário',
                  value: data.available
                      ? OwnerFormatters.moneyFromCents(totalAmount)
                      : 'Em preparação',
                  detail: data.available
                      ? '$totalCount vendas no período.'
                      : 'Faturamento por pessoa aparecerá aqui.',
                  icon: Icons.point_of_sale_rounded,
                  isAvailable: data.available,
                ),
                OwnerMetricCard(
                  title: 'Ticket médio',
                  value: data.available && totalCount > 0
                      ? OwnerFormatters.moneyFromCents(
                          (totalAmount / totalCount).round(),
                        )
                      : 'Em preparação',
                  detail: 'Valor médio por venda em cada atendimento.',
                  icon: Icons.trending_up_rounded,
                  isAvailable: data.available && totalCount > 0,
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
            OwnerSectionCard(
              title: 'Desempenho da equipe',
              subtitle: 'Leitura gerencial por funcionário.',
              child: _EmployeeList(report: data),
            ),
          ],
        );
      },
    );
  }
}

class _EmployeeList extends StatelessWidget {
  const _EmployeeList({required this.report});

  final OwnerEmployeeReports report;

  @override
  Widget build(BuildContext context) {
    if (!report.available) {
      return const OwnerEmptyState(
        title: 'Relatórios de funcionários em preparação',
        message:
            'Os relatórios de funcionários serão liberados quando houver vendas vinculadas aos usuários.',
        icon: Icons.insights_rounded,
      );
    }
    if (report.topEmployees.isEmpty) {
      return const OwnerEmptyState(
        title: 'Nenhuma venda por funcionário no período',
        message:
            'Quando houver vendas vinculadas aos usuários, elas aparecerão aqui.',
        icon: Icons.badge_outlined,
      );
    }
    return Column(
      children: [
        for (final item in report.topEmployees)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.badge_outlined),
            title: Text(item.name),
            subtitle: Text(
              '${item.salesCount} vendas - Última venda ${OwnerFormatters.date(item.lastSaleAt)}',
            ),
            trailing: Text(
              OwnerFormatters.moneyFromCents(item.salesAmountCents),
            ),
          ),
      ],
    );
  }
}
