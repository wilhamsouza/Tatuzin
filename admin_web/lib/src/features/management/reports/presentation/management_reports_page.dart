import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/admin_providers.dart';
import '../../../../core/models/admin_analytics_models.dart';
import '../../../../core/utils/admin_formatters.dart';
import '../../../../core/widgets/admin_surface.dart';
import '../../../management/presentation/widgets/management_scope_panel.dart';

class ManagementReportsPage extends ConsumerStatefulWidget {
  const ManagementReportsPage({super.key});

  @override
  ConsumerState<ManagementReportsPage> createState() =>
      _ManagementReportsPageState();
}

class _ManagementReportsPageState extends ConsumerState<ManagementReportsPage> {
  String? _selectedCompanyId;
  late String _startDate;
  late String _endDate;
  int _topN = 12;
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
            title: 'Sem empresas para relatórios',
            subtitle:
                'Os relatórios cloud-first aparecem aqui quando houver empresa consolidada no backend.',
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
        final reportsAsync = ref.watch(
          adminManagementReportsBundleProvider(query),
        );

        return reportsAsync.when(
          data: (bundle) => SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ManagementScopePanel(
                  title: 'Relatorios gerenciais cloud-first',
                  subtitle:
                      'Todos os relatórios desta página sao lidos do backend consolidado por empresa.',
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
                _BundleHeader(bundle: bundle),
                const SizedBox(height: 24),
                _FinancialSummarySurface(report: bundle.financialSummary),
                const SizedBox(height: 24),
                _SalesByDaySurface(report: bundle.salesByDay),
                const SizedBox(height: 24),
                _CashSurface(report: bundle.cashConsolidated),
                const SizedBox(height: 24),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final productSurface = _SalesByProductSurface(
                      report: bundle.salesByProduct,
                    );
                    final customerSurface = _SalesByCustomerSurface(
                      report: bundle.salesByCustomer,
                    );

                    if (constraints.maxWidth < 1200) {
                      return Column(
                        children: [
                          productSurface,
                          const SizedBox(height: 24),
                          customerSurface,
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: productSurface),
                        const SizedBox(width: 24),
                        Expanded(child: customerSurface),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => AdminSurface(
            title: 'Nao foi possivel carregar os relatórios gerenciais',
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

class _BundleHeader extends StatelessWidget {
  const _BundleHeader({required this.bundle});

  final AdminManagementReportsBundle bundle;

  @override
  Widget build(BuildContext context) {
    return AdminSurface(
      title: bundle.financialSummary.company.name,
      subtitle:
          'Relatorios consolidados de ${AdminFormatters.formatIsoDate(bundle.financialSummary.period.startDate)} ate ${AdminFormatters.formatIsoDate(bundle.financialSummary.period.endDate)}.',
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _MutedPill(label: bundle.financialSummary.company.slug),
          _MutedPill(
            label:
                'Atualizado em ${AdminFormatters.formatDateTime(bundle.financialSummary.materialization.materializedAt)}',
          ),
          _MutedPill(
            label:
                'Cobertura ${bundle.financialSummary.materialization.coverage.companyDailyRows}/${bundle.financialSummary.materialization.coverage.productDailyRows}/${bundle.financialSummary.materialization.coverage.customerDailyRows}',
          ),
        ],
      ),
    );
  }
}

class _FinancialSummarySurface extends StatelessWidget {
  const _FinancialSummarySurface({required this.report});

  final AdminFinancialSummaryReport report;

  @override
  Widget build(BuildContext context) {
    final summary = report.summary;

    return AdminSurface(
      title: 'Resumo financeiro consolidado',
      subtitle:
          'Leitura gerencial da empresa no periodo, separada da operação local do app.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _SummaryMetric(
                title: 'Receita',
                value: AdminFormatters.formatCurrencyFromCents(
                  summary.salesAmountCents,
                ),
              ),
              _SummaryMetric(
                title: 'Custo',
                value: AdminFormatters.formatCurrencyFromCents(
                  summary.salesCostCents,
                ),
              ),
              _SummaryMetric(
                title: 'Margem',
                value: AdminFormatters.formatCurrencyFromCents(
                  summary.salesProfitCents,
                ),
              ),
              _SummaryMetric(
                title: 'Compras',
                value: AdminFormatters.formatCurrencyFromCents(
                  summary.purchasesAmountCents,
                ),
              ),
              _SummaryMetric(
                title: 'Recebido fiado',
                value: AdminFormatters.formatCurrencyFromCents(
                  summary.fiadoPaymentsAmountCents,
                ),
              ),
              _SummaryMetric(
                title: 'Margem %',
                value: AdminFormatters.formatBasisPointsPercent(
                  summary.operatingMarginBasisPoints,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Data')),
                DataColumn(label: Text('Receita')),
                DataColumn(label: Text('Margem')),
                DataColumn(label: Text('Compras')),
                DataColumn(label: Text('Fiado')),
                DataColumn(label: Text('Caixa liquido')),
                DataColumn(label: Text('Ajustes')),
              ],
              rows: report.series.map((point) {
                return DataRow(
                  cells: [
                    DataCell(Text(AdminFormatters.formatIsoDate(point.date))),
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
                        AdminFormatters.formatCurrencyFromCents(
                          point.purchasesAmountCents,
                        ),
                      ),
                    ),
                    DataCell(
                      Text(
                        AdminFormatters.formatCurrencyFromCents(
                          point.fiadoPaymentsAmountCents,
                        ),
                      ),
                    ),
                    DataCell(
                      Text(
                        AdminFormatters.formatCurrencyFromCents(
                          point.cashNetCents,
                        ),
                      ),
                    ),
                    DataCell(
                      Text(
                        AdminFormatters.formatCurrencyFromCents(
                          point.financialAdjustmentsCents,
                        ),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _SalesByDaySurface extends StatelessWidget {
  const _SalesByDaySurface({required this.report});

  final AdminSalesByDayReport report;

  @override
  Widget build(BuildContext context) {
    return AdminSurface(
      title: 'Vendas por dia',
      subtitle:
          'Serie diaria consolidada por empresa para fechamento e acompanhamento gerencial.',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Data')),
            DataColumn(label: Text('Vendas')),
            DataColumn(label: Text('Receita')),
            DataColumn(label: Text('Custo')),
            DataColumn(label: Text('Margem')),
          ],
          rows: report.series.map((point) {
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
                      point.salesCostCents,
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
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _CashSurface extends StatelessWidget {
  const _CashSurface({required this.report});

  final AdminCashConsolidatedReport report;

  @override
  Widget build(BuildContext context) {
    return AdminSurface(
      title: 'Caixa consolidado',
      subtitle:
          'Entradas, saídas e líquido do caixa observadas no backend por periodo.',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Data')),
            DataColumn(label: Text('Entradas')),
            DataColumn(label: Text('Saidas')),
            DataColumn(label: Text('Liquido')),
          ],
          rows: report.series.map((point) {
            return DataRow(
              cells: [
                DataCell(Text(AdminFormatters.formatIsoDate(point.date))),
                DataCell(
                  Text(
                    AdminFormatters.formatCurrencyFromCents(
                      point.cashInflowCents,
                    ),
                  ),
                ),
                DataCell(
                  Text(
                    AdminFormatters.formatCurrencyFromCents(
                      point.cashOutflowCents,
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

class _SalesByProductSurface extends StatelessWidget {
  const _SalesByProductSurface({required this.report});

  final AdminSalesByProductReport report;

  @override
  Widget build(BuildContext context) {
    return AdminSurface(
      title: 'Vendas por produto',
      subtitle:
          'Ranking gerencial com base na materialização diária por produto.',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Produto')),
            DataColumn(label: Text('Qtd.')),
            DataColumn(label: Text('Vendas')),
            DataColumn(label: Text('Receita')),
            DataColumn(label: Text('Margem')),
          ],
          rows: report.items.map((item) {
            return DataRow(
              cells: [
                DataCell(Text(item.productName)),
                DataCell(
                  Text(AdminFormatters.formatQuantityMil(item.quantityMil)),
                ),
                DataCell(Text('${item.salesCount}')),
                DataCell(
                  Text(
                    AdminFormatters.formatCurrencyFromCents(item.revenueCents),
                  ),
                ),
                DataCell(
                  Text(
                    AdminFormatters.formatCurrencyFromCents(item.profitCents),
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

class _SalesByCustomerSurface extends StatelessWidget {
  const _SalesByCustomerSurface({required this.report});

  final AdminSalesByCustomerReport report;

  @override
  Widget build(BuildContext context) {
    return AdminSurface(
      title: 'Vendas por cliente',
      subtitle:
          'Clientes identificados com receita, margem e recebimento de fiado no periodo.',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Cliente')),
            DataColumn(label: Text('Vendas')),
            DataColumn(label: Text('Receita')),
            DataColumn(label: Text('Margem')),
            DataColumn(label: Text('Recebido fiado')),
          ],
          rows: report.items.map((item) {
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
                    AdminFormatters.formatCurrencyFromCents(item.profitCents),
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
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 180),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
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

String _formatIsoDay(DateTime date) => date.toIso8601String().split('T').first;
