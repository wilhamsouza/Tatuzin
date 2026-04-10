import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/admin_providers.dart';
import '../../../core/models/admin_models.dart';
import '../../../core/utils/admin_formatters.dart';
import '../../../core/widgets/admin_surface.dart';

class SyncHealthPage extends ConsumerStatefulWidget {
  const SyncHealthPage({super.key});

  @override
  ConsumerState<SyncHealthPage> createState() => _SyncHealthPageState();
}

class _SyncHealthPageState extends ConsumerState<SyncHealthPage> {
  late final TextEditingController _searchController;
  String? _licenseStatus;
  bool? _syncEnabled;
  String _sortBy = 'companyName';
  String _sortDirection = 'asc';
  int _page = 1;
  int _pageSize = 20;

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
    final query = AdminSyncOperationalQuery(
      page: _page,
      pageSize: _pageSize,
      search: _searchController.text,
      licenseStatus: _licenseStatus,
      syncEnabled: _syncEnabled,
      sortBy: _sortBy,
      sortDirection: _sortDirection,
    );
    final summaryAsync = ref.watch(adminSyncOperationalSummaryProvider(query));

    return summaryAsync.when(
      data: (summary) => SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _OverviewGrid(overview: summary.overview),
            const SizedBox(height: 24),
            AdminSurface(
              title: 'Como ler esta visao',
              subtitle:
                  'Este painel mostra apenas os sinais que o backend realmente observa hoje.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _SourceBadge(source: 'observed'),
                      _SourceBadge(source: 'limited_inference'),
                      _SourceBadge(source: 'telemetry_gap'),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ...summary.capabilities.notes.take(3).map(
                    (note) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(note),
                    ),
                  ),
                  if (summary.capabilities.unavailableSignals.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Sinais que o backend nao observa',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: summary.capabilities.unavailableSignals
                          .map(
                            (signal) => _MutedChip(
                              label: _formatUnavailableSignal(signal),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            AdminSurface(
              title: 'Triagem operacional por tenant',
              subtitle:
                  'Use esta lista para encontrar rapidamente tenants em atencao, bloqueio de licenca, sync desabilitada ou telemetria limitada.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SyncFilters(
                    searchController: _searchController,
                    licenseStatus: _licenseStatus,
                    syncEnabled: _syncEnabled,
                    sortBy: _sortBy,
                    sortDirection: _sortDirection,
                    pageSize: _pageSize,
                    onApply: _applyFilters,
                    onClear: _clearFilters,
                  ),
                  const SizedBox(height: 20),
                  if (summary.companies.isEmpty)
                    const _EmptyState(
                      message:
                          'Nenhum tenant encontrado para os filtros atuais.',
                    )
                  else
                    Column(
                      children: summary.companies
                          .map(
                            (company) => Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: _OperationalCompanyCard(company: company),
                            ),
                          )
                          .toList(),
                    ),
                  const SizedBox(height: 20),
                  _PaginationBar(
                    pagination: summary.pagination,
                    onPrevious: summary.pagination.hasPrevious
                        ? () => setState(() => _page--)
                        : null,
                    onNext: summary.pagination.hasNext
                        ? () => setState(() => _page++)
                        : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => AdminSurface(
        title: 'Nao foi possivel carregar a triagem operacional',
        subtitle: error.toString(),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonal(
            onPressed: () => ref.invalidate(
              adminSyncOperationalSummaryProvider(query),
            ),
            child: const Text('Tentar novamente'),
          ),
        ),
      ),
    );
  }

  void _applyFilters({
    required String? licenseStatus,
    required bool? syncEnabled,
    required String sortBy,
    required String sortDirection,
    required int pageSize,
  }) {
    setState(() {
      _licenseStatus = licenseStatus;
      _syncEnabled = syncEnabled;
      _sortBy = sortBy;
      _sortDirection = sortDirection;
      _pageSize = pageSize;
      _page = 1;
    });
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _licenseStatus = null;
      _syncEnabled = null;
      _sortBy = 'companyName';
      _sortDirection = 'asc';
      _pageSize = 20;
      _page = 1;
    });
  }
}

class _OverviewGrid extends StatelessWidget {
  const _OverviewGrid({required this.overview});

  final AdminSyncOperationalOverview overview;

  @override
  Widget build(BuildContext context) {
    final items = <_OverviewMetric>[
      _OverviewMetric(
        title: 'Tenants observados',
        value: '${overview.totalCompanies}',
        icon: Icons.apartment_rounded,
      ),
      _OverviewMetric(
        title: 'Em atencao',
        value: '${overview.statusCounts['attention'] ?? 0}',
        icon: Icons.warning_amber_rounded,
      ),
      _OverviewMetric(
        title: 'Sync desabilitada',
        value: '${overview.statusCounts['sync_disabled'] ?? 0}',
        icon: Icons.cloud_off_rounded,
      ),
      _OverviewMetric(
        title: 'Licenca inativa',
        value: '${overview.statusCounts['license_inactive'] ?? 0}',
        icon: Icons.block_rounded,
      ),
      _OverviewMetric(
        title: 'Telemetria limitada',
        value: '${overview.statusCounts['telemetry_limited'] ?? 0}',
        icon: Icons.sensors_off_rounded,
      ),
      _OverviewMetric(
        title: 'Inferencia parcial',
        value: '${overview.telemetryLevelCounts['partial'] ?? 0}',
        icon: Icons.manage_search_rounded,
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
            childAspectRatio: 2.35,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemBuilder: (context, index) {
            final item = items[index];
            return AdminSurface(
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor:
                        Theme.of(context).colorScheme.primaryContainer,
                    child: Icon(
                      item.icon,
                      color: Theme.of(context).colorScheme.primary,
                    ),
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
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                    ],
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

class _SyncFilters extends StatefulWidget {
  const _SyncFilters({
    required this.searchController,
    required this.licenseStatus,
    required this.syncEnabled,
    required this.sortBy,
    required this.sortDirection,
    required this.pageSize,
    required this.onApply,
    required this.onClear,
  });

  final TextEditingController searchController;
  final String? licenseStatus;
  final bool? syncEnabled;
  final String sortBy;
  final String sortDirection;
  final int pageSize;
  final void Function({
    required String? licenseStatus,
    required bool? syncEnabled,
    required String sortBy,
    required String sortDirection,
    required int pageSize,
  })
  onApply;
  final VoidCallback onClear;

  @override
  State<_SyncFilters> createState() => _SyncFiltersState();
}

class _SyncFiltersState extends State<_SyncFilters> {
  late String? _licenseStatus;
  late bool? _syncEnabled;
  late String _sortBy;
  late String _sortDirection;
  late int _pageSize;

  @override
  void initState() {
    super.initState();
    _syncFromWidget();
  }

  @override
  void didUpdateWidget(covariant _SyncFilters oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.licenseStatus != widget.licenseStatus ||
        oldWidget.syncEnabled != widget.syncEnabled ||
        oldWidget.sortBy != widget.sortBy ||
        oldWidget.sortDirection != widget.sortDirection ||
        oldWidget.pageSize != widget.pageSize) {
      _syncFromWidget();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 280,
              child: TextField(
                controller: widget.searchController,
                decoration: const InputDecoration(
                  labelText: 'Buscar tenant',
                  hintText: 'Nome ou slug',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
                onSubmitted: (_) => _apply(),
              ),
            ),
            SizedBox(
              width: 190,
              child: DropdownButtonFormField<String?>(
                initialValue: _licenseStatus,
                decoration: const InputDecoration(labelText: 'Licenca'),
                items: const [
                  DropdownMenuItem<String?>(value: null, child: Text('Todas')),
                  DropdownMenuItem<String?>(value: 'trial', child: Text('Trial')),
                  DropdownMenuItem<String?>(value: 'active', child: Text('Ativa')),
                  DropdownMenuItem<String?>(
                    value: 'suspended',
                    child: Text('Suspensa'),
                  ),
                  DropdownMenuItem<String?>(
                    value: 'expired',
                    child: Text('Expirada'),
                  ),
                  DropdownMenuItem<String?>(
                    value: 'without_license',
                    child: Text('Sem licenca'),
                  ),
                ],
                onChanged: (value) => setState(() => _licenseStatus = value),
              ),
            ),
            SizedBox(
              width: 170,
              child: DropdownButtonFormField<bool?>(
                initialValue: _syncEnabled,
                decoration: const InputDecoration(labelText: 'Sync'),
                items: const [
                  DropdownMenuItem<bool?>(value: null, child: Text('Todas')),
                  DropdownMenuItem<bool?>(value: true, child: Text('Habilitada')),
                  DropdownMenuItem<bool?>(
                    value: false,
                    child: Text('Desativada'),
                  ),
                ],
                onChanged: (value) => setState(() => _syncEnabled = value),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<String>(
                initialValue: _sortBy,
                decoration: const InputDecoration(labelText: 'Ordenar por'),
                items: const [
                  DropdownMenuItem(
                    value: 'companyName',
                    child: Text('Empresa'),
                  ),
                  DropdownMenuItem(
                    value: 'remoteRecordCount',
                    child: Text('Total remoto'),
                  ),
                  DropdownMenuItem(
                    value: 'licenseStatus',
                    child: Text('Status da licenca'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _sortBy = value);
                  }
                },
              ),
            ),
            SizedBox(
              width: 160,
              child: DropdownButtonFormField<String>(
                initialValue: _sortDirection,
                decoration: const InputDecoration(labelText: 'Direcao'),
                items: const [
                  DropdownMenuItem(value: 'asc', child: Text('Crescente')),
                  DropdownMenuItem(value: 'desc', child: Text('Decrescente')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _sortDirection = value);
                  }
                },
              ),
            ),
            SizedBox(
              width: 140,
              child: DropdownButtonFormField<int>(
                initialValue: _pageSize,
                decoration: const InputDecoration(labelText: 'Por pagina'),
                items: const [
                  DropdownMenuItem(value: 10, child: Text('10')),
                  DropdownMenuItem(value: 20, child: Text('20')),
                  DropdownMenuItem(value: 50, child: Text('50')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _pageSize = value);
                  }
                },
              ),
            ),
            FilledButton.icon(
              onPressed: _apply,
              icon: const Icon(Icons.filter_alt_rounded),
              label: const Text('Aplicar'),
            ),
            TextButton(
              onPressed: widget.onClear,
              child: const Text('Limpar'),
            ),
          ],
        ),
      ],
    );
  }

  void _apply() {
    widget.onApply(
      licenseStatus: _licenseStatus,
      syncEnabled: _syncEnabled,
      sortBy: _sortBy,
      sortDirection: _sortDirection,
      pageSize: _pageSize,
    );
  }

  void _syncFromWidget() {
    _licenseStatus = widget.licenseStatus;
    _syncEnabled = widget.syncEnabled;
    _sortBy = widget.sortBy;
    _sortDirection = widget.sortDirection;
    _pageSize = widget.pageSize;
  }
}

class _OperationalCompanyCard extends StatelessWidget {
  const _OperationalCompanyCard({required this.company});

  final AdminSyncOperationalCompanySummary company;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final featuresWithData = company.observedFeatures
        .where((feature) => feature.remoteRecordCount > 0)
        .toList(growable: false);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _statusColor(context, company.status).withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    company.companyName,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    company.companySlug,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              _OperationalStatusBadge(status: company.status),
              _SourceBadge(source: company.statusSource),
              _LicenseBadge(status: company.licenseStatus),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            company.statusReason,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _MiniMetric(
                label: 'Sessoes ativas',
                value: '${company.activeSessionsCount}',
              ),
              _MiniMetric(
                label: 'Sessoes mobile',
                value: '${company.activeMobileSessionsCount}',
              ),
              _MiniMetric(
                label: 'Total remoto observado',
                value: '${company.observedRemoteRecordCount}',
              ),
              _MiniMetric(
                label: 'Cobertura observada',
                value:
                    '${company.remoteCoverage.featuresWithRemoteRecords}/${company.remoteCoverage.observedFeatureCount} features',
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MutedChip(
                label: company.syncEnabled ? 'Sync habilitada' : 'Sync desabilitada',
              ),
              _MutedChip(
                label:
                    'Telemetria ${_formatTelemetryLevel(company.telemetryAvailability.level)}',
              ),
              _MutedChip(
                label: company.lastObservedRemoteChangeAt == null
                    ? 'Sem atividade remota observada'
                    : 'Ultima atividade remota ${AdminFormatters.formatDateTime(company.lastObservedRemoteChangeAt)}',
              ),
              _MutedChip(
                label: company.lastSessionSeenAt == null
                    ? 'Sem sessao ativa observada'
                    : 'Ultima sessao ${AdminFormatters.formatDateTime(company.lastSessionSeenAt)}',
              ),
            ],
          ),
          const SizedBox(height: 16),
          _TelemetrySummary(telemetry: company.telemetryAvailability),
          if (featuresWithData.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Features remotas observadas',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: featuresWithData
                  .map(
                    (feature) => _MutedChip(
                      label:
                          '${feature.displayName}: ${feature.remoteRecordCount}',
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _TelemetrySummary extends StatelessWidget {
  const _TelemetrySummary({required this.telemetry});

  final AdminTelemetryAvailability telemetry;

  @override
  Widget build(BuildContext context) {
    final items = <String>[
      if (telemetry.hasDeviceSessionSignals) 'sessoes',
      if (telemetry.hasRemoteMirrorSignals) 'espelho remoto',
      if (!telemetry.hasLocalQueueSignals) 'sem fila local',
      if (!telemetry.hasConflictSignals) 'sem conflitos',
      if (!telemetry.hasRetrySignals) 'sem retries',
      if (!telemetry.hasClientRepairSignals) 'sem repair',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Disponibilidade de telemetria',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: items
              .map((item) => _MutedChip(label: item))
              .toList(growable: false),
        ),
      ],
    );
  }
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 140),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}

class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (source) {
      'observed' => ('Observado', Theme.of(context).colorScheme.tertiary),
      'limited_inference' => (
          'Inferencia limitada',
          Theme.of(context).colorScheme.secondary,
        ),
      _ => ('Lacuna de telemetria', Theme.of(context).colorScheme.error),
    };

    return _ColoredBadge(
      label: label,
      backgroundColor: color.withValues(alpha: 0.16),
      foregroundColor: color,
    );
  }
}

class _OperationalStatusBadge extends StatelessWidget {
  const _OperationalStatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    return _ColoredBadge(
      label: _formatOperationalStatus(status),
      backgroundColor: _statusColor(context, status).withValues(alpha: 0.16),
      foregroundColor: _statusColor(context, status),
    );
  }
}

class _LicenseBadge extends StatelessWidget {
  const _LicenseBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    return _ColoredBadge(
      label: 'Licenca: ${AdminFormatters.formatLicenseStatus(status)}',
      backgroundColor:
          AdminFormatters.statusBackgroundColor(context, status).withValues(
        alpha: 0.8,
      ),
      foregroundColor: AdminFormatters.statusColor(context, status),
    );
  }
}

class _ColoredBadge extends StatelessWidget {
  const _ColoredBadge({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final String label;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: foregroundColor,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _MutedChip extends StatelessWidget {
  const _MutedChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall,
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

class _PaginationBar extends StatelessWidget {
  const _PaginationBar({
    required this.pagination,
    required this.onPrevious,
    required this.onNext,
  });

  final AdminPaginationMeta pagination;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          'Pagina ${pagination.page} • ${pagination.count} de ${pagination.total} tenants',
        ),
        OutlinedButton.icon(
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left_rounded),
          label: const Text('Anterior'),
        ),
        OutlinedButton.icon(
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right_rounded),
          label: const Text('Proxima'),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Text(message),
    );
  }
}

Color _statusColor(BuildContext context, String status) {
  switch (status) {
    case 'healthy':
      return Colors.green.shade700;
    case 'attention':
      return Colors.orange.shade800;
    case 'sync_disabled':
      return Colors.blueGrey.shade700;
    case 'license_inactive':
      return Colors.red.shade700;
    default:
      return Theme.of(context).colorScheme.secondary;
  }
}

String _formatOperationalStatus(String status) {
  switch (status) {
    case 'healthy':
      return 'Saudavel';
    case 'attention':
      return 'Atencao';
    case 'sync_disabled':
      return 'Sync desabilitada';
    case 'license_inactive':
      return 'Licenca inativa';
    default:
      return 'Telemetria limitada';
  }
}

String _formatTelemetryLevel(String level) {
  switch (level) {
    case 'blocked':
      return 'bloqueada';
    case 'partial':
      return 'parcial';
    default:
      return 'limitada';
  }
}

String _formatUnavailableSignal(String signal) {
  switch (signal) {
    case 'local_queue':
      return 'sem fila local';
    case 'retry_state':
      return 'sem retries';
    case 'conflict_state':
      return 'sem conflitos';
    case 'client_repair_state':
      return 'sem repair';
    case 'client_sync_errors':
      return 'sem erros do cliente';
    default:
      return signal;
  }
}
