import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/admin_providers.dart';
import '../../../core/models/admin_billing_models.dart';
import '../../../core/models/admin_models.dart';
import '../../../core/utils/admin_formatters.dart';
import '../../../core/widgets/admin_surface.dart';

class AuditPage extends ConsumerStatefulWidget {
  const AuditPage({super.key, this.initialQueryParameters = const {}});

  final Map<String, String> initialQueryParameters;

  @override
  ConsumerState<AuditPage> createState() => _AuditPageState();
}

class _AuditPageState extends ConsumerState<AuditPage> {
  late final TextEditingController _actionController;
  late final TextEditingController _actorUserIdController;
  late final TextEditingController _companyIdController;
  late final TextEditingController _searchController;
  late final TextEditingController _dateFromController;
  late final TextEditingController _dateToController;
  int _page = 1;
  int _pageSize = 20;
  String? _category;
  String? _source;
  String? _status;

  @override
  void initState() {
    super.initState();
    final params = widget.initialQueryParameters;
    _actionController = TextEditingController(text: params['action'] ?? '');
    _actorUserIdController = TextEditingController(
      text: params['actorUserId'] ?? '',
    );
    _companyIdController = TextEditingController(
      text: params['companyId'] ?? '',
    );
    _searchController = TextEditingController(text: params['search'] ?? '');
    _dateFromController = TextEditingController(text: params['dateFrom'] ?? '');
    _dateToController = TextEditingController(text: params['dateTo'] ?? '');
    _category = _filterValue(params['category']);
    _source = _filterValue(params['source']);
    _status = _filterValue(params['status']);
  }

  @override
  void dispose() {
    _actionController.dispose();
    _actorUserIdController.dispose();
    _companyIdController.dispose();
    _searchController.dispose();
    _dateFromController.dispose();
    _dateToController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query;
    final auditAsync = ref.watch(adminAuditLogsProvider(query));

    return auditAsync.when(
      data: (page) => SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AdminSurface(
              title: 'Auditoria global',
              subtitle:
                  'Historico centralizado de acoes administrativas da plataforma.',
              trailing: FilledButton.tonalIcon(
                onPressed: () => ref.invalidate(adminAuditLogsProvider(query)),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Atualizar'),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _AuditNotice(),
                  const SizedBox(height: 18),
                  _AuditFilters(
                    actionController: _actionController,
                    actorUserIdController: _actorUserIdController,
                    companyIdController: _companyIdController,
                    searchController: _searchController,
                    dateFromController: _dateFromController,
                    dateToController: _dateToController,
                    pageSize: _pageSize,
                    category: _category,
                    source: _source,
                    status: _status,
                    onCategoryChanged: (value) {
                      setState(() => _category = value);
                    },
                    onSourceChanged: (value) {
                      setState(() => _source = value);
                    },
                    onStatusChanged: (value) {
                      setState(() => _status = value);
                    },
                    onApply: _applyFilters,
                    onClear: _clearFilters,
                  ),
                  const SizedBox(height: 20),
                  _AuditMetrics(page: page),
                ],
              ),
            ),
            const SizedBox(height: 24),
            AdminSurface(
              title: 'Eventos normalizados',
              subtitle:
                  'Acoes humanas e comandos administrativos; eventos de provider ficam separados quando disponiveis.',
              child: page.items.isEmpty
                  ? const _EmptyState(
                      message: 'Nenhum evento encontrado para os filtros.',
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _AuditEntriesTable(entries: page.items),
                        const SizedBox(height: 20),
                        _PaginationBar(
                          pagination: page.pagination,
                          onPrevious: page.pagination.hasPrevious
                              ? () => setState(() => _page--)
                              : null,
                          onNext: page.pagination.hasNext
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
        title: 'Nao foi possivel carregar a auditoria global',
        subtitle: _safeError(error),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            onPressed: () => ref.invalidate(adminAuditLogsProvider(query)),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Tentar novamente'),
          ),
        ),
      ),
    );
  }

  AdminAuditQuery get _query {
    return AdminAuditQuery(
      page: _page,
      pageSize: _pageSize,
      action: _actionController.text,
      actorUserId: _actorUserIdController.text,
      companyId: _companyIdController.text,
      category: _category,
      source: _source,
      status: _status,
      search: _searchController.text,
      dateFrom: _parseDate(_dateFromController.text),
      dateTo: _parseDate(_dateToController.text),
    );
  }

  void _applyFilters({required int pageSize}) {
    setState(() {
      _page = 1;
      _pageSize = pageSize;
    });
  }

  void _clearFilters() {
    _actionController.clear();
    _actorUserIdController.clear();
    _companyIdController.clear();
    _searchController.clear();
    _dateFromController.clear();
    _dateToController.clear();
    setState(() {
      _page = 1;
      _pageSize = 20;
      _category = null;
      _source = null;
      _status = null;
    });
  }
}

class _AuditNotice extends StatelessWidget {
  const _AuditNotice();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        Chip(
          avatar: Icon(Icons.visibility_rounded, size: 18),
          label: Text('Somente leitura'),
        ),
        Chip(
          avatar: Icon(Icons.security_rounded, size: 18),
          label: Text('Dados sensiveis omitidos por seguranca'),
        ),
        Chip(
          avatar: Icon(Icons.account_tree_rounded, size: 18),
          label: Text('Provider/sistema separados quando disponiveis'),
        ),
      ],
    );
  }
}

class _AuditFilters extends StatefulWidget {
  const _AuditFilters({
    required this.actionController,
    required this.actorUserIdController,
    required this.companyIdController,
    required this.searchController,
    required this.dateFromController,
    required this.dateToController,
    required this.pageSize,
    required this.category,
    required this.source,
    required this.status,
    required this.onCategoryChanged,
    required this.onSourceChanged,
    required this.onStatusChanged,
    required this.onApply,
    required this.onClear,
  });

  final TextEditingController actionController;
  final TextEditingController actorUserIdController;
  final TextEditingController companyIdController;
  final TextEditingController searchController;
  final TextEditingController dateFromController;
  final TextEditingController dateToController;
  final int pageSize;
  final String? category;
  final String? source;
  final String? status;
  final ValueChanged<String?> onCategoryChanged;
  final ValueChanged<String?> onSourceChanged;
  final ValueChanged<String?> onStatusChanged;
  final void Function({required int pageSize}) onApply;
  final VoidCallback onClear;

  @override
  State<_AuditFilters> createState() => _AuditFiltersState();
}

class _AuditFiltersState extends State<_AuditFilters> {
  late int _pageSize;

  @override
  void initState() {
    super.initState();
    _pageSize = widget.pageSize;
  }

  @override
  void didUpdateWidget(covariant _AuditFilters oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageSize != widget.pageSize) {
      _pageSize = widget.pageSize;
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
          children: [
            _FilterTextField(
              controller: widget.companyIdController,
              label: 'Empresa',
              onSubmitted: _apply,
            ),
            _FilterTextField(
              controller: widget.actorUserIdController,
              label: 'Ator',
              onSubmitted: _apply,
            ),
            _FilterTextField(
              controller: widget.actionController,
              label: 'Acao',
              onSubmitted: _apply,
            ),
            _FilterDropdown(
              label: 'Categoria',
              value: widget.category,
              values: const [
                'billing',
                'license',
                'access',
                'sync',
                'session',
                'system',
                'provider',
                'unknown',
              ],
              onChanged: widget.onCategoryChanged,
            ),
            _FilterDropdown(
              label: 'Origem',
              value: widget.source,
              values: const [
                'admin',
                'billing_admin',
                'sync_support',
                'session',
              ],
              onChanged: widget.onSourceChanged,
            ),
            _FilterDropdown(
              label: 'Status',
              value: widget.status,
              values: const ['success', 'failed', 'pending', 'running', 'info'],
              onChanged: widget.onStatusChanged,
            ),
            _FilterTextField(
              controller: widget.dateFromController,
              label: 'Periodo inicial',
              hintText: '2026-05-01',
              onSubmitted: _apply,
            ),
            _FilterTextField(
              controller: widget.dateToController,
              label: 'Periodo final',
              hintText: '2026-05-26',
              onSubmitted: _apply,
            ),
            SizedBox(
              width: 150,
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
            SizedBox(
              width: 300,
              child: TextField(
                controller: widget.searchController,
                decoration: const InputDecoration(
                  labelText: 'Busca textual',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
                onSubmitted: (_) => _apply(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: _apply,
              icon: const Icon(Icons.filter_alt_rounded),
              label: const Text('Aplicar filtros'),
            ),
            OutlinedButton.icon(
              onPressed: widget.onClear,
              icon: const Icon(Icons.filter_alt_off_rounded),
              label: const Text('Limpar filtros'),
            ),
          ],
        ),
      ],
    );
  }

  void _apply() => widget.onApply(pageSize: _pageSize);
}

class _FilterTextField extends StatelessWidget {
  const _FilterTextField({
    required this.controller,
    required this.label,
    required this.onSubmitted,
    this.hintText,
  });

  final TextEditingController controller;
  final String label;
  final String? hintText;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: TextField(
        controller: controller,
        decoration: InputDecoration(labelText: label, hintText: hintText),
        onSubmitted: (_) => onSubmitted(),
      ),
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final List<String> values;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      child: DropdownButtonFormField<String>(
        initialValue: value ?? 'all',
        decoration: InputDecoration(labelText: label),
        items: [
          const DropdownMenuItem(value: 'all', child: Text('Todas')),
          ...values.map(
            (item) => DropdownMenuItem(value: item, child: Text(_label(item))),
          ),
        ],
        onChanged: (selected) {
          onChanged(selected == null || selected == 'all' ? null : selected);
        },
      ),
    );
  }
}

class _AuditMetrics extends StatelessWidget {
  const _AuditMetrics({required this.page});

  final AdminAuditLogPage page;

  @override
  Widget build(BuildContext context) {
    final categories = page.overview.countsByCategory;
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        _AuditMetric(
          title: 'Total no periodo',
          value: '${page.overview.totalEvents}',
        ),
        _AuditMetric(
          title: 'Billing/licenca',
          value:
              '${(categories['billing'] ?? 0) + (categories['license'] ?? 0)}',
        ),
        _AuditMetric(title: 'Acesso', value: '${categories['access'] ?? 0}'),
        _AuditMetric(title: 'Sync', value: '${categories['sync'] ?? 0}'),
        _AuditMetric(title: 'Falhas/erros', value: '${page.overview.failures}'),
        _AuditMetric(
          title: 'Ultimos 7 dias',
          value: '${page.overview.last7Days}',
        ),
      ],
    );
  }
}

class _AuditEntriesTable extends StatelessWidget {
  const _AuditEntriesTable({required this.entries});

  final List<AdminAuditEntry> entries;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Detalhes')),
          DataColumn(label: Text('Data/hora')),
          DataColumn(label: Text('Categoria')),
          DataColumn(label: Text('Acao')),
          DataColumn(label: Text('Empresa')),
          DataColumn(label: Text('Ator')),
          DataColumn(label: Text('Alvo')),
          DataColumn(label: Text('Motivo')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Origem')),
        ],
        rows: entries
            .map((entry) {
              return DataRow(
                cells: [
                  DataCell(
                    TextButton.icon(
                      onPressed: () => _showDetails(context, entry),
                      icon: const Icon(Icons.article_outlined),
                      label: const Text('Detalhes'),
                    ),
                  ),
                  DataCell(
                    Text(AdminFormatters.formatDateTime(entry.createdAt)),
                  ),
                  DataCell(Text(_label(entry.category))),
                  DataCell(Text(_friendlyAction(entry.action))),
                  DataCell(Text(entry.companyLabel)),
                  DataCell(Text(entry.actorLabel)),
                  DataCell(
                    Text(entry.targetLabel ?? entry.targetType ?? 'Sem alvo'),
                  ),
                  DataCell(Text(entry.reason ?? 'Sem motivo')),
                  DataCell(_StatusChip(status: entry.status)),
                  DataCell(Text(_label(entry.source))),
                ],
              );
            })
            .toList(growable: false),
      ),
    );
  }

  void _showDetails(BuildContext context, AdminAuditEntry entry) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_friendlyAction(entry.action)),
        content: SizedBox(
          width: 720,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Dados sensiveis sao omitidos por seguranca.'),
                const SizedBox(height: 16),
                _DetailLine(label: 'Origem', value: _label(entry.source)),
                _DetailLine(label: 'Categoria', value: _label(entry.category)),
                _DetailLine(label: 'Status', value: _label(entry.status)),
                _DetailLine(label: 'Empresa', value: entry.companyLabel),
                _DetailLine(label: 'Ator', value: entry.actorLabel),
                _DetailLine(
                  label: 'Alvo',
                  value: entry.targetLabel ?? entry.targetId ?? 'Sem alvo',
                ),
                _DetailLine(
                  label: 'Motivo',
                  value: entry.reason ?? 'Sem motivo',
                ),
                _DetailLine(
                  label: 'IP',
                  value: entry.ipAddress ?? 'Nao disponivel',
                ),
                _JsonBlock(label: 'Before sanitizado', value: entry.before),
                _JsonBlock(label: 'After sanitizado', value: entry.after),
                _JsonBlock(label: 'Metadata sanitizada', value: entry.metadata),
                _JsonBlock(label: 'User agent', value: entry.userAgent),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final normalized = status.toLowerCase();
    final colorScheme = Theme.of(context).colorScheme;
    final background = normalized == 'failed'
        ? colorScheme.errorContainer
        : normalized == 'success'
        ? colorScheme.primaryContainer
        : colorScheme.surfaceContainerHighest;
    return Chip(
      label: Text(_label(status)),
      backgroundColor: background,
      visualDensity: VisualDensity.compact,
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text('$label: $value'),
    );
  }
}

class _JsonBlock extends StatelessWidget {
  const _JsonBlock({required this.label, required this.value});

  final String label;
  final Object? value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              formatSanitizedAdminJson(
                value ?? const <String, dynamic>{'estado': 'Sem dados'},
              ),
            ),
          ),
        ],
      ),
    );
  }
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
          'Pagina ${pagination.page} - ${pagination.count} de ${pagination.total} eventos',
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
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Text(message),
    );
  }
}

class _AuditMetric extends StatelessWidget {
  const _AuditMetric({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

DateTime? _parseDate(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  return DateTime.tryParse(trimmed);
}

String? _filterValue(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty || trimmed == 'all') {
    return null;
  }
  return trimmed;
}

String _friendlyAction(String action) {
  switch (action) {
    case 'license.emergency_extension':
      return 'Extensao emergencial';
    case 'billing.reconcile':
      return 'Reconciliacao de billing';
    case 'billing.reconcile.failed':
      return 'Falha na reconciliacao';
    case 'license.suspend':
      return 'Suspensao de licenca';
    case 'license.reactivate':
      return 'Reativacao de licenca';
    case 'access.block':
    case 'admin.access.block':
      return 'Bloqueio de acesso operacional';
    case 'access.reactivate':
    case 'admin.access.reactivate':
      return 'Reativacao de acesso operacional';
    case 'sync.support_command.created':
      return 'Comando de suporte criado';
    case 'RETRY_FAILED_SYNC_EVENTS':
      return 'Reprocessar falhas locais';
    case 'REPAIR_OPERATIONAL_ORDER_ITEM_TOTAL_CENTS':
      return 'Reparar totalCents';
    case 'CLEAR_RESOLVED_CONFLICT_CACHE':
      return 'Limpar conflitos resolvidos';
    case 'FORCE_SYNC_PULL':
      return 'Forcar atualizacao da nuvem';
    case 'REFRESH_SYNC_STATUS':
      return 'Recalcular status de sync';
    default:
      return action;
  }
}

String _label(String value) {
  switch (value.toLowerCase()) {
    case 'billing':
      return 'Billing';
    case 'license':
      return 'Licenca';
    case 'access':
      return 'Acesso';
    case 'sync':
      return 'Sync';
    case 'session':
      return 'Sessao';
    case 'system':
      return 'Sistema';
    case 'provider':
      return 'Provider';
    case 'unknown':
      return 'Desconhecido';
    case 'admin':
      return 'Admin';
    case 'billing_admin':
      return 'Admin billing';
    case 'sync_support':
      return 'Suporte sync';
    case 'success':
      return 'Sucesso';
    case 'failed':
      return 'Falha';
    case 'pending':
      return 'Pendente';
    case 'running':
      return 'Em execucao';
    case 'info':
      return 'Info';
    default:
      return value;
  }
}

String _safeError(Object error) {
  final message = error.toString();
  if (message.contains('Exception:')) {
    return message.split('Exception:').last.trim();
  }
  return message;
}
