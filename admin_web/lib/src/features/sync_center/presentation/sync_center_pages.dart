import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/admin_providers.dart';
import '../../../core/models/admin_models.dart';
import '../../../core/models/admin_sync_center_models.dart';
import '../../../core/utils/admin_formatters.dart';
import '../../../core/widgets/admin_operational_status.dart';
import '../../../core/widgets/admin_surface.dart';
import 'company_sync_center_page.dart';

class SyncCenterPage extends ConsumerStatefulWidget {
  const SyncCenterPage({super.key});

  @override
  ConsumerState<SyncCenterPage> createState() => _SyncCenterPageState();
}

class _SyncCenterPageState extends ConsumerState<SyncCenterPage> {
  late final TextEditingController _searchController;
  String _status = 'requires_review';
  String _operationalFilter = 'all';
  String _issueFilter = 'all';
  String _sortBy = 'criticality';
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = AdminSyncCenterCompaniesQuery(
      page: _page,
      pageSize: 20,
      search: _searchController.text,
      status: _status,
    );
    final companiesAsync = ref.watch(adminSyncCenterCompaniesProvider(query));

    return companiesAsync.when(
      data: (result) {
        final visibleCompanies = _sortCompanies(
          _filterCompanies(
            result.items,
            operationalFilter: _operationalFilter,
            issueFilter: _issueFilter,
          ),
          _sortBy,
        );
        return RefreshIndicator(
          onRefresh: () async =>
              ref.invalidate(adminSyncCenterCompaniesProvider(query)),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: AdminSurface(
              title: 'Sync Center',
              subtitle:
                  'Centro interno read-only para priorizar empresas com conflito, falha e incidente de sync.',
              trailing: OutlinedButton.icon(
                onPressed: () =>
                    ref.invalidate(adminSyncCenterCompaniesProvider(query)),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Atualizar'),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _ReadOnlyNotice(),
                  const SizedBox(height: 16),
                  const _SyncObservabilityNotice(),
                  const SizedBox(height: 16),
                  _OperationalSummary(
                    companies: result.items,
                    totalMonitored: result.pagination.total,
                  ),
                  const SizedBox(height: 16),
                  _CompanyFilters(
                    searchController: _searchController,
                    status: _status,
                    operationalFilter: _operationalFilter,
                    issueFilter: _issueFilter,
                    sortBy: _sortBy,
                    onApply: (filters) => setState(() {
                      _status = filters.status;
                      _operationalFilter = filters.operationalFilter;
                      _issueFilter = filters.issueFilter;
                      _sortBy = filters.sortBy;
                      _page = 1;
                    }),
                    onClear: () {
                      _searchController.clear();
                      setState(() {
                        _status = 'requires_review';
                        _operationalFilter = 'all';
                        _issueFilter = 'all';
                        _sortBy = 'criticality';
                        _page = 1;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  if (visibleCompanies.isEmpty)
                    const _EmptyState(
                      message:
                          'Nenhuma empresa encontrada para os filtros. Sem metricas disponiveis para classificar este recorte; observabilidade completa depende de backend/infra futura.',
                    )
                  else
                    _CompaniesTable(companies: visibleCompanies),
                  const SizedBox(height: 16),
                  _PaginationBar(
                    pagination: result.pagination,
                    label: 'empresas',
                    onPrevious: result.pagination.hasPrevious
                        ? () => setState(() => _page--)
                        : null,
                    onNext: result.pagination.hasNext
                        ? () => setState(() => _page++)
                        : null,
                  ),
                ],
              ),
            ),
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ErrorSurface(
        title: 'Nao foi possivel carregar o Sync Center',
        error: error,
        onRetry: () => ref.invalidate(adminSyncCenterCompaniesProvider(query)),
      ),
    );
  }
}

class SyncCompanyPage extends AdminCompanySyncCenterPage {
  const SyncCompanyPage({super.key, required super.companyId});
}

class SyncEventDetailPage extends ConsumerWidget {
  const SyncEventDetailPage({
    super.key,
    required this.companyId,
    required this.eventId,
  });

  final String companyId;
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = AdminSyncCenterDetailKey(
      companyId: companyId,
      targetId: eventId,
    );
    final detailAsync = ref.watch(adminSyncCenterEventDetailProvider(key));
    return detailAsync.when(
      data: (detail) => SingleChildScrollView(
        child: AdminSurface(
          title: 'Evento ${detail.event.eventId}',
          subtitle: detail.message,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _ReadOnlyNotice(),
              const SizedBox(height: 16),
              _DetailGrid(
                rows: {
                  'Status': _eventStatusLabel(detail.event.status),
                  'Modulo': detail.event.feature,
                  'Entidade': detail.event.entity,
                  'Operacao': detail.event.operation,
                  'Classificacao': detail.classification,
                  'Criado em': AdminFormatters.formatDateTime(
                    detail.event.createdAt,
                  ),
                },
              ),
              const SizedBox(height: 16),
              _SafePayload(payload: detail.event.safePayloadPreview),
              const SizedBox(height: 16),
              const _ReadonlyActionPlaceholder(),
            ],
          ),
        ),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ErrorSurface(
        title: 'Nao foi possivel carregar evento',
        error: error,
        onRetry: () => ref.invalidate(adminSyncCenterEventDetailProvider(key)),
      ),
    );
  }
}

class SyncConflictDetailPage extends ConsumerWidget {
  const SyncConflictDetailPage({
    super.key,
    required this.companyId,
    required this.conflictId,
  });

  final String companyId;
  final String conflictId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = AdminSyncCenterDetailKey(
      companyId: companyId,
      targetId: conflictId,
    );
    final detailAsync = ref.watch(adminSyncCenterConflictDetailProvider(key));
    return detailAsync.when(
      data: (detail) => SingleChildScrollView(
        child: AdminSurface(
          title: 'Conflito ${detail.conflict.code}',
          subtitle: detail.message,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _ReadOnlyNotice(),
              const SizedBox(height: 16),
              _DetailGrid(
                rows: {
                  'Status': _conflictStatusLabel(detail.conflict.status),
                  'Entidade': detail.conflict.entity,
                  'Codigo': detail.conflict.code,
                  'Classificacao': detail.classification,
                  'Criado em': AdminFormatters.formatDateTime(
                    detail.conflict.createdAt,
                  ),
                  'Evento': detail.event.eventId,
                },
              ),
              const SizedBox(height: 16),
              _SafePayload(payload: detail.conflict.safePayloadPreview),
              const SizedBox(height: 16),
              const _ReadonlyActionPlaceholder(),
            ],
          ),
        ),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ErrorSurface(
        title: 'Nao foi possivel carregar conflito',
        error: error,
        onRetry: () =>
            ref.invalidate(adminSyncCenterConflictDetailProvider(key)),
      ),
    );
  }
}

class _SyncObservabilityNotice extends StatelessWidget {
  const _SyncObservabilityNotice();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminOperationalLegend(
          subtitle:
              'Sync Center e a principal fonte visual para saude de sincronizacao; metricas reais de latencia e disponibilidade dependem de backend/infra futura.',
        ),
        SizedBox(height: 10),
        Text(
          'Observabilidade read-only: destaque empresas criticas, empresas sem dados recentes e sinais de atencao sem executar comandos reais.',
        ),
      ],
    );
  }
}

class _CompaniesTable extends StatelessWidget {
  const _CompaniesTable({required this.companies});

  final List<AdminSyncCenterCompany> companies;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Empresa')),
          DataColumn(label: Text('Plano')),
          DataColumn(label: Text('Saude')),
          DataColumn(label: Text('Ultimo sync')),
          DataColumn(label: Text('Conflitos')),
          DataColumn(label: Text('Erros')),
          DataColumn(label: Text('Pendencias')),
          DataColumn(label: Text('Acao')),
        ],
        rows: companies
            .map((company) {
              return DataRow(
                cells: [
                  DataCell(Text(company.companyName)),
                  DataCell(
                    Text(AdminFormatters.formatPlan(company.plan ?? 'FREE')),
                  ),
                  DataCell(
                    AdminOperationalStatus(
                      label: _operationalLabel(_companyTone(company)),
                      tone: _companyTone(company),
                      compact: true,
                    ),
                  ),
                  DataCell(Text(_lastSyncLabel(company.lastEventAt))),
                  DataCell(
                    Text(
                      '${company.openConflictCount} abertos / ${company.conflictCount} total',
                    ),
                  ),
                  DataCell(Text('${company.failedCount}')),
                  DataCell(Text('${company.pendingCount}')),
                  DataCell(
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: () => context.go(
                            '/companies/${company.companyId}/sync',
                          ),
                          icon: const Icon(Icons.open_in_new_rounded),
                          label: const Text('Abrir Sync'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => context.go(
                            '/companies/${company.companyId}/support',
                          ),
                          icon: const Icon(Icons.support_agent_rounded),
                          label: const Text('Suporte'),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            })
            .toList(growable: false),
      ),
    );
  }
}

class _OperationalSummary extends StatelessWidget {
  const _OperationalSummary({
    required this.companies,
    required this.totalMonitored,
  });

  final List<AdminSyncCenterCompany> companies;
  final int totalMonitored;

  @override
  Widget build(BuildContext context) {
    final conflicts = companies.fold<int>(
      0,
      (sum, company) => sum + company.openConflictCount,
    );
    final pending = companies.fold<int>(
      0,
      (sum, company) => sum + company.pendingCount,
    );
    final failed = companies.fold<int>(
      0,
      (sum, company) => sum + company.failedCount,
    );
    final ok = companies.where(_isOkCompany).length;
    final attention = companies
        .where(
          (company) => _companyTone(company) == AdminOperationalTone.attention,
        )
        .length;
    final critical = companies
        .where(
          (company) => _companyTone(company) == AdminOperationalTone.critical,
        )
        .length;
    final noData = companies
        .where(
          (company) => _companyTone(company) == AdminOperationalTone.noData,
        )
        .length;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _MetricCard(
          label: 'Empresas monitoradas',
          value: '$totalMonitored',
          icon: Icons.apartment_rounded,
        ),
        _MetricCard(
          label: 'Total de conflitos',
          value: '$conflicts',
          icon: Icons.report_problem_rounded,
        ),
        _MetricCard(
          label: 'Total de pendencias',
          value: '$pending',
          icon: Icons.pending_actions_rounded,
        ),
        _MetricCard(
          label: 'Total de erros',
          value: '$failed',
          icon: Icons.error_outline_rounded,
        ),
        _StatusMetricCard(
          label: 'Empresas OK',
          value: '$ok',
          tone: AdminOperationalTone.ok,
        ),
        _StatusMetricCard(
          label: 'Empresas em atencao',
          value: '$attention',
          tone: AdminOperationalTone.attention,
        ),
        _StatusMetricCard(
          label: 'Empresas criticas',
          value: '$critical',
          tone: AdminOperationalTone.critical,
        ),
        _StatusMetricCard(
          label: 'Empresas sem dados recentes',
          value: '$noData',
          tone: AdminOperationalTone.noData,
        ),
      ],
    );
  }
}

class _CompanyFilters extends StatefulWidget {
  const _CompanyFilters({
    required this.searchController,
    required this.status,
    required this.operationalFilter,
    required this.issueFilter,
    required this.sortBy,
    required this.onApply,
    required this.onClear,
  });

  final TextEditingController searchController;
  final String status;
  final String operationalFilter;
  final String issueFilter;
  final String sortBy;
  final ValueChanged<_CompanyFilterState> onApply;
  final VoidCallback onClear;

  @override
  State<_CompanyFilters> createState() => _CompanyFiltersState();
}

class _CompanyFiltersState extends State<_CompanyFilters> {
  late String _status = widget.status;
  late String _operationalFilter = widget.operationalFilter;
  late String _issueFilter = widget.issueFilter;
  late String _sortBy = widget.sortBy;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 280,
          child: TextField(
            controller: widget.searchController,
            decoration: const InputDecoration(
              labelText: 'Buscar empresa',
              prefixIcon: Icon(Icons.search_rounded),
            ),
            onSubmitted: (_) => widget.onApply(_filters),
          ),
        ),
        DropdownButton<String>(
          value: _status,
          items: const [
            DropdownMenuItem(
              value: 'requires_review',
              child: Text('Com atencao'),
            ),
            DropdownMenuItem(value: 'all', child: Text('Todas')),
            DropdownMenuItem(value: 'healthy', child: Text('Saudaveis')),
          ],
          onChanged: (value) {
            if (value != null) {
              setState(() => _status = value);
            }
          },
        ),
        DropdownButton<String>(
          value: _operationalFilter,
          items: const [
            DropdownMenuItem(value: 'all', child: Text('Operacional: todos')),
            DropdownMenuItem(value: 'ok', child: Text('Operacional: OK')),
            DropdownMenuItem(
              value: 'attention',
              child: Text('Operacional: Atencao'),
            ),
            DropdownMenuItem(
              value: 'critical',
              child: Text('Operacional: Critico'),
            ),
            DropdownMenuItem(
              value: 'no_data',
              child: Text('Operacional: Sem dados'),
            ),
          ],
          onChanged: (value) {
            if (value != null) {
              setState(() => _operationalFilter = value);
            }
          },
        ),
        DropdownButton<String>(
          value: _issueFilter,
          items: const [
            DropdownMenuItem(value: 'all', child: Text('Todas as condicoes')),
            DropdownMenuItem(value: 'conflict', child: Text('Com conflito')),
            DropdownMenuItem(value: 'error', child: Text('Com erro')),
            DropdownMenuItem(value: 'pending', child: Text('Com pendencias')),
            DropdownMenuItem(
              value: 'no_recent_sync',
              child: Text('Sem sync recente'),
            ),
            DropdownMenuItem(value: 'no_data', child: Text('Sem dados')),
          ],
          onChanged: (value) {
            if (value != null) {
              setState(() => _issueFilter = value);
            }
          },
        ),
        DropdownButton<String>(
          value: _sortBy,
          items: const [
            DropdownMenuItem(
              value: 'criticality',
              child: Text('Ordenar: criticidade'),
            ),
            DropdownMenuItem(
              value: 'last_sync',
              child: Text('Ordenar: ultimo sync'),
            ),
            DropdownMenuItem(
              value: 'conflicts',
              child: Text('Ordenar: conflitos'),
            ),
            DropdownMenuItem(
              value: 'pending',
              child: Text('Ordenar: pendencias'),
            ),
            DropdownMenuItem(value: 'errors', child: Text('Ordenar: erros')),
          ],
          onChanged: (value) {
            if (value != null) {
              setState(() => _sortBy = value);
            }
          },
        ),
        FilledButton.icon(
          onPressed: () => widget.onApply(_filters),
          icon: const Icon(Icons.filter_alt_rounded),
          label: const Text('Aplicar'),
        ),
        TextButton(onPressed: widget.onClear, child: const Text('Limpar')),
      ],
    );
  }

  _CompanyFilterState get _filters => _CompanyFilterState(
    status: _status,
    operationalFilter: _operationalFilter,
    issueFilter: _issueFilter,
    sortBy: _sortBy,
  );
}

class _CompanyFilterState {
  const _CompanyFilterState({
    required this.status,
    required this.operationalFilter,
    required this.issueFilter,
    required this.sortBy,
  });

  final String status;
  final String operationalFilter;
  final String issueFilter;
  final String sortBy;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 210,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(label),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusMetricCard extends StatelessWidget {
  const _StatusMetricCard({
    required this.label,
    required this.value,
    required this.tone,
  });

  final String label;
  final String value;
  final AdminOperationalTone tone;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 210,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              AdminOperationalStatus(
                label: _operationalLabel(tone),
                tone: tone,
                compact: true,
              ),
              const SizedBox(height: 6),
              Text(label),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReadOnlyNotice extends StatelessWidget {
  const _ReadOnlyNotice();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Modo seguro/read-only: nenhuma acao remota, reprocessamento, arquivamento ou comando de suporte e criado nesta fase.',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: scheme.onSecondaryContainer,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ReadonlyActionPlaceholder extends StatelessWidget {
  const _ReadonlyActionPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        Chip(label: Text('Acoes remotas bloqueadas nesta fase')),
        Chip(label: Text('Dry-run sera fase posterior')),
        Chip(label: Text('Auditoria obrigatoria futura')),
      ],
    );
  }
}

class _DetailGrid extends StatelessWidget {
  const _DetailGrid({required this.rows});

  final Map<String, String> rows;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: rows.entries
          .map((entry) {
            return SizedBox(
              width: 260,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.key,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      SelectableText(
                        entry.value,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              ),
            );
          })
          .toList(growable: false),
    );
  }
}

class _SafePayload extends StatelessWidget {
  const _SafePayload({required this.payload});

  final Map<String, dynamic> payload;

  @override
  Widget build(BuildContext context) {
    return AdminSurface(
      title: 'Payload seguro',
      subtitle: 'Somente preview sanitizado retornado pelo backend.',
      child: payload.isEmpty
          ? const Text('Sem preview seguro disponivel.')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: payload.entries
                  .map((entry) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: SelectableText('${entry.key}: ${entry.value}'),
                    );
                  })
                  .toList(growable: false),
            ),
    );
  }
}

class _PaginationBar extends StatelessWidget {
  const _PaginationBar({
    required this.pagination,
    required this.label,
    required this.onPrevious,
    required this.onNext,
  });

  final AdminPaginationMeta pagination;
  final String label;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Pagina ${pagination.page}: ${pagination.count} de ${pagination.total} $label.',
          ),
        ),
        IconButton(
          tooltip: 'Anterior',
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        IconButton(
          tooltip: 'Proxima',
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(padding: const EdgeInsets.all(28), child: Text(message)),
    );
  }
}

class _ErrorSurface extends StatelessWidget {
  const _ErrorSurface({
    required this.title,
    required this.error,
    required this.onRetry,
  });

  final String title;
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return AdminSurface(
      title: title,
      subtitle: _safeError(error),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.tonalIcon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Tentar novamente'),
        ),
      ),
    );
  }
}

List<AdminSyncCenterCompany> _filterCompanies(
  List<AdminSyncCenterCompany> companies, {
  required String operationalFilter,
  required String issueFilter,
}) {
  return companies
      .where((company) {
        final tone = _companyTone(company);
        final matchesOperational = switch (operationalFilter) {
          'ok' => tone == AdminOperationalTone.ok,
          'attention' => tone == AdminOperationalTone.attention,
          'critical' => tone == AdminOperationalTone.critical,
          'no_data' => tone == AdminOperationalTone.noData,
          _ => true,
        };
        final matchesIssue = switch (issueFilter) {
          'conflict' =>
            company.openConflictCount > 0 || company.conflictCount > 0,
          'error' => company.failedCount > 0 || company.incidentCount > 0,
          'pending' => company.pendingCount > 0,
          'no_recent_sync' => company.lastEventAt == null,
          'no_data' => _hasNoSyncData(company),
          _ => true,
        };
        return matchesOperational && matchesIssue;
      })
      .toList(growable: false);
}

List<AdminSyncCenterCompany> _sortCompanies(
  List<AdminSyncCenterCompany> companies,
  String sortBy,
) {
  final sorted = [...companies];
  sorted.sort((a, b) {
    final result = switch (sortBy) {
      'last_sync' => _compareNullableDateDesc(a.lastEventAt, b.lastEventAt),
      'conflicts' => b.openConflictCount.compareTo(a.openConflictCount),
      'pending' => b.pendingCount.compareTo(a.pendingCount),
      'errors' => b.failedCount.compareTo(a.failedCount),
      _ => _criticalityRank(a).compareTo(_criticalityRank(b)),
    };
    if (result != 0) {
      return result;
    }
    return a.companyName.compareTo(b.companyName);
  });
  return sorted;
}

int _compareNullableDateDesc(DateTime? a, DateTime? b) {
  if (a == null && b == null) {
    return 0;
  }
  if (a == null) {
    return 1;
  }
  if (b == null) {
    return -1;
  }
  return b.compareTo(a);
}

int _criticalityRank(AdminSyncCenterCompany company) {
  return switch (_companyTone(company)) {
    AdminOperationalTone.critical => 0,
    AdminOperationalTone.attention => 1,
    AdminOperationalTone.ok => 2,
    AdminOperationalTone.noData => 3,
  };
}

bool _isOkCompany(AdminSyncCenterCompany company) =>
    _companyTone(company) == AdminOperationalTone.ok;

AdminOperationalTone _companyTone(AdminSyncCenterCompany company) {
  final status = company.syncStatus.toLowerCase();
  if (_hasNoSyncData(company)) {
    return AdminOperationalTone.noData;
  }
  if (status.contains('fail') ||
      status.contains('critical') ||
      company.failedCount > 0 ||
      company.openConflictCount > 0 ||
      company.incidentCount > 0) {
    return AdminOperationalTone.critical;
  }
  if (status.contains('attention') ||
      status.contains('warning') ||
      status.contains('pending') ||
      status.contains('conflict') ||
      company.requiresReview ||
      company.pendingCount > 0 ||
      company.conflictCount > 0) {
    return AdminOperationalTone.attention;
  }
  return AdminOperationalTone.ok;
}

bool _hasNoSyncData(AdminSyncCenterCompany company) {
  final total =
      company.acceptedCount +
      company.duplicateCount +
      company.pendingCount +
      company.conflictCount +
      company.failedCount +
      company.openConflictCount +
      company.incidentCount;
  return company.lastEventAt == null && total == 0;
}

String _operationalLabel(AdminOperationalTone tone) {
  return switch (tone) {
    AdminOperationalTone.ok => 'OK',
    AdminOperationalTone.attention => 'Atencao',
    AdminOperationalTone.critical => 'Critico',
    AdminOperationalTone.noData => 'Sem dados',
  };
}

String _lastSyncLabel(DateTime? value) {
  if (value == null) {
    return 'Sem sync recente';
  }
  return AdminFormatters.formatDateTime(value);
}

String _eventStatusLabel(String status) {
  switch (status.toLowerCase()) {
    case 'accepted':
      return 'Sincronizado';
    case 'pending':
      return 'Pendente';
    case 'conflict':
      return 'Com conflito';
    case 'failed':
      return 'Com erro';
    case 'rejected':
      return 'Rejeitado';
    case 'duplicate':
      return 'Duplicado';
    default:
      return status;
  }
}

String _conflictStatusLabel(String status) {
  switch (status.toLowerCase()) {
    case 'open':
      return 'OPEN';
    case 'resolved':
      return 'RESOLVED';
    case 'ignored':
      return 'IGNORED';
    default:
      return status.toUpperCase();
  }
}

String _safeError(Object error) {
  final message = error.toString();
  if (message.contains('Exception:')) {
    return message.split('Exception:').last.trim();
  }
  return message;
}
