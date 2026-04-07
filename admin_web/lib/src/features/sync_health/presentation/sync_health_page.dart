import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/admin_providers.dart';
import '../../../core/utils/admin_formatters.dart';
import '../../../core/widgets/admin_surface.dart';

class SyncHealthPage extends ConsumerWidget {
  const SyncHealthPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncSummary = ref.watch(adminSyncSummaryProvider);
    return syncSummary.when(
      data: (summary) => SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final crossAxisCount = constraints.maxWidth >= 1400
                    ? 3
                    : constraints.maxWidth >= 900
                        ? 2
                        : 1;
                final items = <_OverviewMetric>[
                  _OverviewMetric(
                    title: 'Empresas',
                    value: '${summary.totalCompanies}',
                    icon: Icons.apartment_rounded,
                  ),
                  _OverviewMetric(
                    title: 'Sync habilitada',
                    value: '${summary.syncEnabledCompanies}',
                    icon: Icons.cloud_done_rounded,
                  ),
                  _OverviewMetric(
                    title: 'Sem licenca',
                    value: '${summary.licenseStatusCounts['without_license'] ?? 0}',
                    icon: Icons.no_accounts_rounded,
                  ),
                ];

                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: items.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    childAspectRatio: 2.4,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return AdminSurface(
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                            child: Icon(item.icon, color: Theme.of(context).colorScheme.primary),
                          ),
                          const SizedBox(width: 16),
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.title),
                              const SizedBox(height: 8),
                              Text(
                                item.value,
                                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                      fontWeight: FontWeight.w900,
                                    ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
            const SizedBox(height: 24),
            AdminSurface(
              title: 'Visao por tenant',
              subtitle: 'Resumo de status cloud e volume remoto por empresa.',
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Empresa')),
                    DataColumn(label: Text('Plano')),
                    DataColumn(label: Text('Status')),
                    DataColumn(label: Text('Sync')),
                    DataColumn(label: Text('Categorias')),
                    DataColumn(label: Text('Produtos')),
                    DataColumn(label: Text('Clientes')),
                    DataColumn(label: Text('Vendas')),
                    DataColumn(label: Text('Total remoto')),
                  ],
                  rows: summary.companySummaries.map((company) {
                    return DataRow(
                      cells: [
                        DataCell(
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(company.companyName),
                              Text(
                                company.companySlug,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        DataCell(Text(company.licensePlan ?? 'Sem licenca')),
                        DataCell(
                          _StatusBadge(status: company.licenseStatus ?? 'without_license'),
                        ),
                        DataCell(
                          Text(
                            AdminFormatters.formatBool(
                              company.syncEnabled,
                              yes: 'Habilitada',
                              no: 'Desativada',
                            ),
                          ),
                        ),
                        DataCell(Text('${company.entityCounts.categories}')),
                        DataCell(Text('${company.entityCounts.products}')),
                        DataCell(Text('${company.entityCounts.customers}')),
                        DataCell(Text('${company.entityCounts.sales}')),
                        DataCell(Text('${company.remoteRecordCount}')),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => AdminSurface(
        title: 'Nao foi possivel carregar a saude da sync',
        subtitle: error.toString(),
        child: const SizedBox.shrink(),
      ),
    );
  }
}

class _OverviewMetric {
  const _OverviewMetric({
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
  final String value;
  final IconData icon;
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AdminFormatters.statusBackgroundColor(context, status),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        AdminFormatters.formatLicenseStatus(status),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AdminFormatters.statusColor(context, status),
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
