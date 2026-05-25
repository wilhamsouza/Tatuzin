import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
        subtitle: _safeError(error),
        trailing: FilledButton.tonalIcon(
          onPressed: () => ref.invalidate(adminDashboardProvider),
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Tentar novamente'),
        ),
        child: const Text('Revise sua conexao e tente atualizar a tela.'),
      ),
    );
  }
}

class _DashboardContent extends ConsumerWidget {
  const _DashboardContent({required this.data});

  final AdminDashboardSnapshot data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = data.syncSummary;
    final companies = data.companies;
    final activeCompanies = companies
        .where((company) => company.isActive)
        .length;
    final expiringLicenses = companies
        .where((company) => _isExpiringSoon(company.license?.expiresAt))
        .length;
    final problemCompanies = _problemCompanies(
      companies,
      sync.companySummaries,
    );
    final devicesOnline = sync.syncEnabledCompanies;
    final syncAttention = sync.totalCompanies - sync.syncEnabledCompanies;

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(adminDashboardProvider),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Toolbar(
              onRefresh: () => ref.invalidate(adminDashboardProvider),
              onOpenSync: () => context.go('/sync'),
            ),
            const SizedBox(height: 16),
            _KpiGrid(
              items: [
                _KpiData(
                  label: 'Empresas ativas',
                  value: '$activeCompanies',
                  helper: '${companies.length} empresas no total',
                  icon: Icons.apartment_rounded,
                ),
                _KpiData(
                  label: 'Sync com atencao',
                  value: '$syncAttention',
                  helper: 'falhas, conflitos ou pendencias',
                  icon: Icons.sync_problem_rounded,
                  tone: _KpiTone.warning,
                ),
                _KpiData(
                  label: 'Licencas vencendo',
                  value: '$expiringLicenses',
                  helper: 'proximos 7 dias',
                  icon: Icons.workspace_premium_rounded,
                  tone: _KpiTone.danger,
                ),
                _KpiData(
                  label: 'Dispositivos online',
                  value: '$devicesOnline',
                  helper: 'sessoes ativas registradas',
                  icon: Icons.devices_rounded,
                ),
              ],
            ),
            const SizedBox(height: 20),
            AdminSurface(
              title: 'Empresas com problemas ativos',
              subtitle:
                  'OPEN conta como problema ativo. RESOLVED e IGNORED ficam apenas no historico.',
              trailing: FilledButton.tonalIcon(
                onPressed: () => context.go('/sync'),
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Abrir Sync Center'),
              ),
              child: problemCompanies.isEmpty
                  ? const _EmptyState(
                      message:
                          'Nenhuma empresa com problema ativo nos dados carregados.',
                    )
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Empresa')),
                          DataColumn(label: Text('Plano')),
                          DataColumn(label: Text('Sync')),
                          DataColumn(label: Text('Licenca')),
                          DataColumn(label: Text('Ativos')),
                          DataColumn(label: Text('Acao')),
                        ],
                        rows: problemCompanies
                            .map((row) {
                              return DataRow(
                                cells: [
                                  DataCell(
                                    Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(row.company.name),
                                        Text(
                                          row.company.slug,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      AdminFormatters.formatPlan(
                                        row.company.license?.plan ?? 'FREE',
                                      ),
                                    ),
                                  ),
                                  DataCell(_StatusChip(label: row.syncLabel)),
                                  DataCell(
                                    _StatusChip(
                                      label:
                                          AdminFormatters.formatLicenseStatus(
                                            row.company.license?.status,
                                          ),
                                    ),
                                  ),
                                  DataCell(Text(row.problemLabel)),
                                  DataCell(
                                    Wrap(
                                      spacing: 8,
                                      children: [
                                        FilledButton.tonalIcon(
                                          onPressed: () => context.go(
                                            '/companies/${row.company.id}',
                                          ),
                                          icon: const Icon(
                                            Icons.business_rounded,
                                          ),
                                          label: const Text('Abrir empresa'),
                                        ),
                                        OutlinedButton.icon(
                                          onPressed: () => context.go(
                                            '/companies/${row.company.id}/sync',
                                          ),
                                          icon: const Icon(Icons.sync_rounded),
                                          label: const Text('Sync Center'),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            })
                            .toList(growable: false),
                      ),
                    ),
            ),
            const SizedBox(height: 20),
            AdminSurface(
              title: 'Auditoria recente',
              subtitle:
                  'Eventos administrativos recentes sem payload sensivel.',
              child: data.auditSummary.recentEvents.isEmpty
                  ? const _EmptyState(message: 'Nenhum evento recente.')
                  : Column(
                      children: data.auditSummary.recentEvents
                          .take(6)
                          .map((event) {
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              leading: const Icon(Icons.fact_check_rounded),
                              title: Text(event.action),
                              subtitle: Text(
                                '${event.actorUserName} - ${AdminFormatters.formatDateTime(event.createdAt)}',
                              ),
                              trailing: event.targetCompanyName == null
                                  ? null
                                  : Text(event.targetCompanyName!),
                            );
                          })
                          .toList(growable: false),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.onRefresh, required this.onOpenSync});

  final VoidCallback onRefresh;
  final VoidCallback onOpenSync;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        FilledButton.icon(
          onPressed: onOpenSync,
          icon: const Icon(Icons.sync_problem_rounded),
          label: const Text('Abrir Sync Center'),
        ),
        OutlinedButton.icon(
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Atualizar'),
        ),
      ],
    );
  }
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.items});

  final List<_KpiData> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1180
            ? 4
            : constraints.maxWidth >= 760
            ? 2
            : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            childAspectRatio: 2.35,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemBuilder: (context, index) => _KpiCard(data: items[index]),
        );
      },
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.data});

  final _KpiData data;

  @override
  Widget build(BuildContext context) {
    final color = data.color(context);
    return AdminSurface(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.12),
            child: Icon(data.icon, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  data.value,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(data.helper, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _KpiTone { normal, warning, danger }

class _KpiData {
  const _KpiData({
    required this.label,
    required this.value,
    required this.helper,
    required this.icon,
    this.tone = _KpiTone.normal,
  });

  final String label;
  final String value;
  final String helper;
  final IconData icon;
  final _KpiTone tone;

  Color color(BuildContext context) {
    return switch (tone) {
      _KpiTone.warning => Colors.orange.shade800,
      _KpiTone.danger => Theme.of(context).colorScheme.error,
      _ => Theme.of(context).colorScheme.primary,
    };
  }
}

class _ProblemCompany {
  const _ProblemCompany({
    required this.company,
    required this.syncLabel,
    required this.problemLabel,
  });

  final AdminCompanySummary company;
  final String syncLabel;
  final String problemLabel;
}

List<_ProblemCompany> _problemCompanies(
  List<AdminCompanySummary> companies,
  List<AdminSyncCompanySummary> syncCompanies,
) {
  final syncByCompany = {
    for (final company in syncCompanies) company.companyId: company,
  };
  return companies
      .map((company) {
        final sync = syncByCompany[company.id];
        const openConflicts = 0;
        const failedEvents = 0;
        final pendingEvents = sync?.syncEnabled == false ? 1 : 0;
        final licenseExpired =
            _isExpired(company.license?.expiresAt) ||
            _isSuspended(company.license?.status);
        final hasProblem =
            openConflicts > 0 ||
            failedEvents > 0 ||
            pendingEvents > 0 ||
            licenseExpired;
        if (!hasProblem) {
          return null;
        }
        return _ProblemCompany(
          company: company,
          syncLabel: sync?.syncEnabled == true ? 'Saudavel' : 'Sync desativada',
          problemLabel:
              '$openConflicts OPEN / $failedEvents falhas / $pendingEvents pend.',
        );
      })
      .whereType<_ProblemCompany>()
      .take(8)
      .toList(growable: false);
}

bool _isExpiringSoon(DateTime? value) {
  if (value == null) {
    return false;
  }
  final now = DateTime.now();
  return value.isAfter(now) && value.difference(now).inDays <= 7;
}

bool _isExpired(DateTime? value) {
  return value != null && value.isBefore(DateTime.now());
}

bool _isSuspended(String? status) {
  return status?.toLowerCase() == 'suspended';
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text(label));
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Text(message),
    );
  }
}

String _safeError(Object error) {
  final message = error.toString();
  if (message.contains('Exception:')) {
    return message.split('Exception:').last.trim();
  }
  return message;
}
