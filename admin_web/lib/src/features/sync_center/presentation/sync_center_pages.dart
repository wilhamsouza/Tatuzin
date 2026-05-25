import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/admin_providers.dart';
import '../../../core/models/admin_models.dart';
import '../../../core/models/admin_sync_center_models.dart';
import '../../../core/utils/admin_formatters.dart';
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
        final openConflicts = result.items.fold<int>(
          0,
          (sum, company) => sum + company.openConflictCount,
        );
        final failed = result.items.fold<int>(
          0,
          (sum, company) => sum + company.failedCount,
        );
        final pending = result.items.fold<int>(
          0,
          (sum, company) => sum + company.pendingCount,
        );
        return RefreshIndicator(
          onRefresh: () async =>
              ref.invalidate(adminSyncCenterCompaniesProvider(query)),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: AdminSurface(
              title: 'Sync global',
              subtitle:
                  'Centro read-only para priorizar empresas com conflito, falha e incidente.',
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
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _MetricCard(
                        label: 'Empresas com atencao',
                        value: '${result.items.length}',
                        icon: Icons.apartment_rounded,
                      ),
                      _MetricCard(
                        label: 'Conflitos OPEN',
                        value: '$openConflicts',
                        icon: Icons.report_problem_rounded,
                      ),
                      _MetricCard(
                        label: 'Eventos failed',
                        value: '$failed',
                        icon: Icons.error_outline_rounded,
                      ),
                      _MetricCard(
                        label: 'Eventos pending',
                        value: '$pending',
                        icon: Icons.pending_actions_rounded,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _CompanyFilters(
                    searchController: _searchController,
                    status: _status,
                    onApply: (status) => setState(() {
                      _status = status;
                      _page = 1;
                    }),
                    onClear: () {
                      _searchController.clear();
                      setState(() {
                        _status = 'requires_review';
                        _page = 1;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  if (result.items.isEmpty)
                    const _EmptyState(
                      message: 'Nenhuma empresa encontrada para os filtros.',
                    )
                  else
                    _CompaniesTable(companies: result.items),
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
        title: 'Nao foi possivel carregar Sync global',
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
          DataColumn(label: Text('Sync')),
          DataColumn(label: Text('OPEN')),
          DataColumn(label: Text('Failed')),
          DataColumn(label: Text('Pending')),
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
                    _StatusChip(label: _syncStatusLabel(company.syncStatus)),
                  ),
                  DataCell(Text('${company.openConflictCount}')),
                  DataCell(Text('${company.failedCount}')),
                  DataCell(Text('${company.pendingCount}')),
                  DataCell(
                    FilledButton.tonalIcon(
                      onPressed: () =>
                          context.go('/companies/${company.companyId}/sync'),
                      icon: const Icon(Icons.open_in_new_rounded),
                      label: const Text('Abrir'),
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

class _CompanyFilters extends StatefulWidget {
  const _CompanyFilters({
    required this.searchController,
    required this.status,
    required this.onApply,
    required this.onClear,
  });

  final TextEditingController searchController;
  final String status;
  final ValueChanged<String> onApply;
  final VoidCallback onClear;

  @override
  State<_CompanyFilters> createState() => _CompanyFiltersState();
}

class _CompanyFiltersState extends State<_CompanyFilters> {
  late String _status = widget.status;

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
            onSubmitted: (_) => widget.onApply(_status),
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
        FilledButton.icon(
          onPressed: () => widget.onApply(_status),
          icon: const Icon(Icons.filter_alt_rounded),
          label: const Text('Aplicar'),
        ),
        TextButton(onPressed: widget.onClear, child: const Text('Limpar')),
      ],
    );
  }
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

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text(label));
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

String _syncStatusLabel(String status) {
  final normalized = status.toLowerCase();
  if (normalized.contains('fail')) {
    return 'Com falha';
  }
  if (normalized.contains('conflict')) {
    return 'Com conflito';
  }
  if (normalized.contains('pending')) {
    return 'Pendente';
  }
  if (normalized.contains('attention')) {
    return 'Atencao';
  }
  return 'Saudavel';
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
