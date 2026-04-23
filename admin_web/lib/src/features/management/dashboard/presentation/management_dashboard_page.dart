import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/admin_providers.dart';
import '../../../../core/models/admin_analytics_models.dart';
import '../../../../core/utils/admin_formatters.dart';
import '../../../../core/widgets/admin_surface.dart';
import '../../../management/presentation/widgets/management_scope_panel.dart';

class ManagementDashboardPage extends ConsumerStatefulWidget {
  const ManagementDashboardPage({super.key});

  @override
  ConsumerState<ManagementDashboardPage> createState() =>
      _ManagementDashboardPageState();
}

class _ManagementDashboardPageState
    extends ConsumerState<ManagementDashboardPage> {
  String? _selectedCompanyId;
  late String _startDate;
  late String _endDate;
  int _topN = 8;
  bool _force = false;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now().toUtc();
    _endDate = _formatIsoDay(today);
    _startDate = _formatIsoDay(today.subtract(const Duration(days: 29)));
  }

  @override
  Widget build(BuildContext context) {
    final companiesAsync = ref.watch(adminManagementCompanyOptionsProvider);

    return companiesAsync.when(
      data: (companies) {
        if (companies.isEmpty) {
          return const AdminSurface(
            title: 'Sem empresas para leitura gerencial',
            subtitle:
                'Cadastre ou sincronize uma empresa antes de abrir o dashboard cloud-first.',
            child: SizedBox.shrink(),
          );
        }

        final effectiveCompanyId = _selectedCompanyId ?? companies.first.id;
        final query = AdminManagementScopeQuery(
          companyId: effectiveCompanyId,
          startDate: _startDate,
          endDate: _endDate,
          topN: _topN,
          force: _force,
        );
        final dashboardAsync = ref.watch(
          adminManagementDashboardProvider(query),
        );

        return dashboardAsync.when(
          data: (dashboard) => SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ManagementScopePanel(
                  title: 'Escopo gerencial cloud-first',
                  subtitle:
                      'Selecione a empresa consolidada no backend e o periodo que o admin web deve ler.',
                  companies: companies,
                  selection: ManagementScopeSelection(
                    companyId: effectiveCompanyId,
                    startDate: _startDate,
                    endDate: _endDate,
                    topN: _topN,
                    force: _force,
                  ),
                  onApply: _applySelection,
                ),
                const SizedBox(height: 24),
                _ManagementHeader(dashboard: dashboard),
                const SizedBox(height: 24),
                _HeadlineGrid(headline: dashboard.headline),
                const SizedBox(height: 24),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final salesSurface = _SalesSeriesSurface(
                      salesSeries: dashboard.salesSeries,
                    );
                    final productsSurface = _TopProductsSurface(
                      items: dashboard.topProducts,
                    );
                    final customersSurface = _TopCustomersSurface(
                      items: dashboard.topCustomers,
                    );

                    if (constraints.maxWidth < 1200) {
                      return Column(
                        children: [
                          salesSurface,
                          const SizedBox(height: 24),
                          productsSurface,
                          const SizedBox(height: 24),
                          customersSurface,
                        ],
                      );
                    }

                    return Column(
                      children: [
                        salesSurface,
                        const SizedBox(height: 24),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: productsSurface),
                            const SizedBox(width: 24),
                            Expanded(child: customersSurface),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => AdminSurface(
            title: 'Nao foi possivel carregar o dashboard gerencial',
            subtitle: error.toString(),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonal(
                onPressed: () =>
                    ref.read(adminRefreshTickProvider.notifier).state++,
                child: const Text('Tentar novamente'),
              ),
            ),
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => AdminSurface(
        title: 'Nao foi possivel carregar as empresas',
        subtitle: error.toString(),
        child: const SizedBox.shrink(),
      ),
    );
  }

  void _applySelection(ManagementScopeSelection selection) {
    setState(() {
      _selectedCompanyId = selection.companyId;
      _startDate = selection.startDate;
      _endDate = selection.endDate;
      _topN = selection.topN;
      _force = selection.force;
    });
    ref.read(adminRefreshTickProvider.notifier).state++;
    if (selection.force) {
      setState(() => _force = false);
    }
  }
}

class _ManagementHeader extends StatelessWidget {
  const _ManagementHeader({required this.dashboard});

  final AdminManagementDashboardSnapshot dashboard;

  @override
  Widget build(BuildContext context) {
    return AdminSurface(
      title: dashboard.company.name,
      subtitle:
          'Dashboard gerencial consolidado de ${AdminFormatters.formatIsoDate(dashboard.period.startDate)} ate ${AdminFormatters.formatIsoDate(dashboard.period.endDate)}.',
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _MutedPill(label: dashboard.company.slug),
          _MutedPill(
            label:
                '${dashboard.period.dayCount} dia(s) materializados no backend',
          ),
          _MutedPill(
            label:
                'Atualizado em ${AdminFormatters.formatDateTime(dashboard.materialization.materializedAt)}',
          ),
          _MutedPill(
            label:
                'Snapshots ${dashboard.materialization.coverage.companyDailyRows}/${dashboard.materialization.coverage.productDailyRows}/${dashboard.materialization.coverage.customerDailyRows}',
          ),
        ],
      ),
    );
  }
}

class _HeadlineGrid extends StatelessWidget {
  const _HeadlineGrid({required this.headline});

  final AdminManagementDashboardHeadline headline;

  @override
  Widget build(BuildContext context) {
    final items = <_HeadlineMetric>[
      _HeadlineMetric(
        label: 'Vendas no periodo',
        value: AdminFormatters.formatCurrencyFromCents(
          headline.salesAmountCents,
        ),
        helper: '${headline.salesCount} venda(s) consolidadas',
        icon: Icons.point_of_sale_rounded,
      ),
      _HeadlineMetric(
        label: 'Margem bruta',
        value: AdminFormatters.formatCurrencyFromCents(
          headline.salesProfitCents,
        ),
        helper: 'Leitura consolidada por empresa',
        icon: Icons.trending_up_rounded,
      ),
      _HeadlineMetric(
        label: 'Caixa liquido',
        value: AdminFormatters.formatCurrencyFromCents(headline.cashNetCents),
        helper: 'Entradas menos saidas registradas',
        icon: Icons.account_balance_wallet_rounded,
      ),
      _HeadlineMetric(
        label: 'Compras',
        value: AdminFormatters.formatCurrencyFromCents(
          headline.purchasesAmountCents,
        ),
        helper: 'Total recebido no periodo',
        icon: Icons.shopping_bag_rounded,
      ),
      _HeadlineMetric(
        label: 'Recebimentos de fiado',
        value: AdminFormatters.formatCurrencyFromCents(
          headline.fiadoPaymentsAmountCents,
        ),
        helper: 'Cobrado e consolidado no backend',
        icon: Icons.receipt_long_rounded,
      ),
      _HeadlineMetric(
        label: 'Ticket medio',
        value: AdminFormatters.formatCurrencyFromCents(
          headline.averageTicketCents,
        ),
        helper: '${headline.identifiedCustomersCount} cliente(s) identificados',
        icon: Icons.analytics_rounded,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth >= 1400
            ? 3
            : constraints.maxWidth >= 900
            ? 2
            : 1;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: 2.2,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemBuilder: (context, index) {
            final item = items[index];
            return AdminSurface(
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.primaryContainer,
                    child: Icon(
                      item.icon,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.label,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          item.value,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          item.helper,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _SalesSeriesSurface extends StatelessWidget {
  const _SalesSeriesSurface({required this.salesSeries});

  final List<AdminDashboardSalesSeriesPoint> salesSeries;

  @override
  Widget build(BuildContext context) {
    return AdminSurface(
      title: 'Vendas por dia',
      subtitle:
          'Serie diaria consolidada no backend, sem depender do dashboard operacional local.',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Data')),
            DataColumn(label: Text('Vendas')),
            DataColumn(label: Text('Receita')),
            DataColumn(label: Text('Margem')),
            DataColumn(label: Text('Caixa liquido')),
          ],
          rows: salesSeries.map((point) {
            return DataRow(
              cells: [
                DataCell(Text(AdminFormatters.formatIsoDate(point.date))),
                DataCell(Text('${point.salesCount}')),
                DataCell(
                  Text(
                    AdminFormatters.formatCurrencyFromCents(
                      point.salesAmountCents,
                    ),
                  ),
                ),
                DataCell(
                  Text(
                    AdminFormatters.formatCurrencyFromCents(
                      point.salesProfitCents,
                    ),
                  ),
                ),
                DataCell(
                  Text(
                    AdminFormatters.formatCurrencyFromCents(point.cashNetCents),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _TopProductsSurface extends StatelessWidget {
  const _TopProductsSurface({required this.items});

  final List<AdminTopProductReportItem> items;

  @override
  Widget build(BuildContext context) {
    return AdminSurface(
      title: 'Top produtos',
      subtitle:
          'Produtos mais relevantes do periodo materializado, pela receita consolidada.',
      child: _RankTable(
        columns: const [
          DataColumn(label: Text('Produto')),
          DataColumn(label: Text('Qtd.')),
          DataColumn(label: Text('Receita')),
          DataColumn(label: Text('Margem')),
        ],
        rows: items.map((item) {
          return DataRow(
            cells: [
              DataCell(Text(item.productName)),
              DataCell(
                Text(AdminFormatters.formatQuantityMil(item.quantityMil)),
              ),
              DataCell(
                Text(
                  AdminFormatters.formatCurrencyFromCents(item.revenueCents),
                ),
              ),
              DataCell(
                Text(AdminFormatters.formatCurrencyFromCents(item.profitCents)),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _TopCustomersSurface extends StatelessWidget {
  const _TopCustomersSurface({required this.items});

  final List<AdminTopCustomerReportItem> items;

  @override
  Widget build(BuildContext context) {
    return AdminSurface(
      title: 'Top clientes',
      subtitle:
          'Clientes identificados com mais venda consolidada no periodo selecionado.',
      child: _RankTable(
        columns: const [
          DataColumn(label: Text('Cliente')),
          DataColumn(label: Text('Vendas')),
          DataColumn(label: Text('Receita')),
          DataColumn(label: Text('Recebido fiado')),
        ],
        rows: items.map((item) {
          return DataRow(
            cells: [
              DataCell(Text(item.customerName)),
              DataCell(Text('${item.salesCount}')),
              DataCell(
                Text(
                  AdminFormatters.formatCurrencyFromCents(item.revenueCents),
                ),
              ),
              DataCell(
                Text(
                  AdminFormatters.formatCurrencyFromCents(
                    item.fiadoPaymentsCents,
                  ),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _RankTable extends StatelessWidget {
  const _RankTable({required this.columns, required this.rows});

  final List<DataColumn> columns;
  final List<DataRow> rows;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(columns: columns, rows: rows),
    );
  }
}

class _MutedPill extends StatelessWidget {
  const _MutedPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

class _HeadlineMetric {
  const _HeadlineMetric({
    required this.label,
    required this.value,
    required this.helper,
    required this.icon,
  });

  final String label;
  final String value;
  final String helper;
  final IconData icon;
}

String _formatIsoDay(DateTime date) => date.toIso8601String().split('T').first;
