import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/admin_providers.dart';
import '../../../core/models/admin_models.dart';
import '../../../core/utils/admin_formatters.dart';
import '../../../core/widgets/admin_surface.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(adminDashboardProvider);
    return dashboard.when(
      data: (data) => _DashboardContent(data: data),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => AdminSurface(
        title: 'Nao foi possivel carregar o dashboard',
        subtitle: error.toString(),
        child: const SizedBox.shrink(),
      ),
    );
  }
}

class _DashboardContent extends StatelessWidget {
  const _DashboardContent({required this.data});

  final AdminDashboardSnapshot data;

  @override
  Widget build(BuildContext context) {
    final sync = data.syncSummary;
    final companies = [...data.companies]
      ..sort((a, b) => b.remoteRecordCount.compareTo(a.remoteRecordCount));

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MetricGrid(
            items: [
              _MetricData(
                label: 'Empresas',
                value: '${sync.totalCompanies}',
                helper: 'tenants cadastrados',
                icon: Icons.apartment_rounded,
              ),
              _MetricData(
                label: 'Licencas ativas',
                value: '${sync.licenseStatusCounts['active'] ?? 0}',
                helper: 'empresas em operacao cloud',
                icon: Icons.workspace_premium_rounded,
              ),
              _MetricData(
                label: 'Licencas trial',
                value: '${sync.licenseStatusCounts['trial'] ?? 0}',
                helper: 'avaliacao em andamento',
                icon: Icons.rocket_launch_rounded,
              ),
              _MetricData(
                label: 'Licencas expiradas',
                value: '${sync.licenseStatusCounts['expired'] ?? 0}',
                helper: 'requerem acao comercial',
                icon: Icons.warning_amber_rounded,
              ),
              _MetricData(
                label: 'Sync habilitada',
                value: '${sync.syncEnabledCompanies}',
                helper: 'tenants com cloud ativa',
                icon: Icons.cloud_done_rounded,
              ),
              _MetricData(
                label: 'Eventos admin',
                value: '${data.auditSummary.totalEvents}',
                helper: 'trilha administrativa registrada',
                icon: Icons.fact_check_rounded,
              ),
            ],
          ),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              final companiesSurface = AdminSurface(
                title: 'Empresas com mais dados remotos',
                subtitle:
                    'Resumo rapido para suporte e acompanhamento da plataforma.',
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Empresa')),
                      DataColumn(label: Text('Plano')),
                      DataColumn(label: Text('Status')),
                      DataColumn(label: Text('Sync')),
                      DataColumn(label: Text('Registros remotos')),
                    ],
                    rows: companies.take(8).map((company) {
                      return DataRow(
                        cells: [
                          DataCell(
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(company.name),
                                Text(
                                  company.slug,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          DataCell(
                            Text(company.license?.plan ?? 'Sem licenca'),
                          ),
                          DataCell(
                            _StatusBadge(
                              status:
                                  company.license?.status ?? 'without_license',
                            ),
                          ),
                          DataCell(
                            Text(
                              AdminFormatters.formatBool(
                                company.license?.syncEnabled == true,
                                yes: 'Habilitada',
                                no: 'Desativada',
                              ),
                            ),
                          ),
                          DataCell(Text('${company.remoteRecordCount}')),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              );

              final auditSurface = AdminSurface(
                title: 'Acoes administrativas recentes',
                subtitle: 'Ultimos eventos do painel e do fluxo de licencas.',
                child: Column(
                  children: data.auditSummary.recentEvents.take(8).map((event) {
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(event.action),
                      subtitle: Text(
                        '${event.actorUserName} - ${AdminFormatters.formatDateTime(event.createdAt)}',
                      ),
                      trailing: event.targetCompanyName == null
                          ? null
                          : Text(
                              event.targetCompanyName!,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                    );
                  }).toList(),
                ),
              );

              if (constraints.maxWidth < 1200) {
                return Column(
                  children: [
                    companiesSurface,
                    const SizedBox(height: 24),
                    auditSurface,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: companiesSurface),
                  const SizedBox(width: 24),
                  Expanded(flex: 2, child: auditSurface),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.items});

  final List<_MetricData> items;

  @override
  Widget build(BuildContext context) {
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
            childAspectRatio: 2.35,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
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
                          style: Theme.of(context).textTheme.headlineMedium
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

class _MetricData {
  const _MetricData({
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
