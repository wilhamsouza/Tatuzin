import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/admin_providers.dart';
import '../../../core/models/admin_billing_models.dart';
import '../../../core/models/admin_models.dart';
import '../../../core/utils/admin_formatters.dart';
import '../../../core/utils/admin_safe_display.dart';
import '../../../core/widgets/admin_operational_status.dart';
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
  String _toneFilter = 'all';
  String _sortBy = 'newest';

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
      data: (page) {
        final visibleEntries = _sortEntries(
          _filterEntries(page.items, toneFilter: _toneFilter),
          _sortBy,
        );
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AdminSurface(
                title: 'Auditoria global',
                subtitle:
                    'Historico centralizado de acoes administrativas da plataforma.',
                trailing: FilledButton.tonalIcon(
                  onPressed: () =>
                      ref.invalidate(adminAuditLogsProvider(query)),
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
                      toneFilter: _toneFilter,
                      sortBy: _sortBy,
                      onCategoryChanged: (value) {
                        setState(() => _category = value);
                      },
                      onSourceChanged: (value) {
                        setState(() => _source = value);
                      },
                      onStatusChanged: (value) {
                        setState(() => _status = value);
                      },
                      onToneFilterChanged: (value) {
                        setState(() => _toneFilter = value);
                      },
                      onSortByChanged: (value) {
                        setState(() => _sortBy = value);
                      },
                      onApply: _applyFilters,
                      onClear: _clearFilters,
                    ),
                    const SizedBox(height: 20),
                    const _AuditCategoryLegend(),
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
                child: visibleEntries.isEmpty
                    ? _EmptyState(message: _emptyAuditMessage(query))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _AuditEntriesTable(entries: visibleEntries),
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
        );
      },
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
      _toneFilter = 'all';
      _sortBy = 'newest';
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
        Chip(
          avatar: Icon(Icons.rule_rounded, size: 18),
          label: Text(
            'Acoes reais futuras exigem dry-run, motivo, confirmacao e auditoria',
          ),
        ),
        Chip(
          avatar: Icon(Icons.lock_clock_rounded, size: 18),
          label: Text('revoke_session real depende do gate operacional'),
        ),
      ],
    );
  }
}

class _AuditCategoryLegend extends StatelessWidget {
  const _AuditCategoryLegend();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        Chip(label: Text('Sessoes')),
        Chip(label: Text('Usuarios')),
        Chip(label: Text('Dispositivos')),
        Chip(label: Text('Billing')),
        Chip(label: Text('Licencas')),
        Chip(label: Text('Sync Center')),
        Chip(label: Text('Permissoes')),
        Chip(label: Text('Support-actions')),
        Chip(label: Text('Revoke session')),
        Chip(label: Text('Seguranca')),
        Chip(label: Text('Sistema')),
        Chip(label: Text('Outros')),
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
    required this.toneFilter,
    required this.sortBy,
    required this.onCategoryChanged,
    required this.onSourceChanged,
    required this.onStatusChanged,
    required this.onToneFilterChanged,
    required this.onSortByChanged,
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
  final String toneFilter;
  final String sortBy;
  final ValueChanged<String?> onCategoryChanged;
  final ValueChanged<String?> onSourceChanged;
  final ValueChanged<String?> onStatusChanged;
  final ValueChanged<String> onToneFilterChanged;
  final ValueChanged<String> onSortByChanged;
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
                'user',
                'device',
                'sync',
                'session',
                'security',
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
            _FilterDropdown(
              label: 'Indicador visual',
              value: widget.toneFilter,
              values: const ['ok', 'attention', 'critical', 'no_data'],
              onChanged: (value) => widget.onToneFilterChanged(value ?? 'all'),
            ),
            _FilterDropdown(
              label: 'Ordenacao local',
              value: widget.sortBy,
              values: const [
                'newest',
                'oldest',
                'criticality',
                'category',
                'company',
                'action',
              ],
              onChanged: (value) => widget.onSortByChanged(value ?? 'newest'),
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
      width: 300,
      child: DropdownButtonFormField<String>(
        initialValue: value ?? 'all',
        isExpanded: true,
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
    final permissions = page.items
        .where((entry) => _isAdminPermissionEvent(entry.action))
        .length;
    final supportActions = page.items
        .where((entry) => _isSupportActionEvent(entry.action))
        .length;
    final revokeSession = page.items
        .where((entry) => _isRevokeSessionEvent(entry.action))
        .length;
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
        _AuditMetric(title: 'Permissoes', value: '$permissions'),
        _AuditMetric(title: 'Support-actions', value: '$supportActions'),
        _AuditMetric(title: 'Revoke session', value: '$revokeSession'),
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
          DataColumn(label: Text('Categoria operacional')),
          DataColumn(label: Text('Tipo de acao')),
          DataColumn(label: Text('Empresa')),
          DataColumn(label: Text('Ator')),
          DataColumn(label: Text('Recurso afetado')),
          DataColumn(label: Text('ID recurso')),
          DataColumn(label: Text('Motivo')),
          DataColumn(label: Text('Resultado')),
          DataColumn(label: Text('Severidade')),
          DataColumn(label: Text('Origem/contexto')),
          DataColumn(label: Text('Navegacao')),
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
                  DataCell(Text(_operationalCategory(entry))),
                  DataCell(Text(_friendlyAction(entry.action))),
                  DataCell(Text(_companyLabel(entry))),
                  DataCell(Text(_actorLabel(entry))),
                  DataCell(
                    Text(
                      _fallback(
                        entry.targetLabel ?? entry.targetType,
                        'Sem recurso relacionado',
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      safeAdminSensitiveText(
                        _fallback(entry.targetId, 'Sem recurso relacionado'),
                        fallback: 'Sem recurso relacionado',
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      safeAdminSensitiveText(
                        _fallback(entry.reason, 'Sem contexto registrado'),
                        fallback: 'Sem contexto registrado',
                      ),
                    ),
                  ),
                  DataCell(Text(_resultLabel(entry.status))),
                  DataCell(
                    AdminOperationalStatus(
                      label: _operationalLabel(_auditTone(entry)),
                      tone: _auditTone(entry),
                      compact: true,
                    ),
                  ),
                  DataCell(Text(_originContext(entry))),
                  DataCell(_NavigationCell(entry: entry)),
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
                _DetailLine(
                  label: 'Categoria operacional',
                  value: _operationalCategory(entry),
                ),
                _DetailLine(
                  label: 'Resultado',
                  value: _resultLabel(entry.status),
                ),
                _DetailLine(label: 'Empresa', value: _companyLabel(entry)),
                _DetailLine(label: 'Ator', value: _actorLabel(entry)),
                _DetailLine(
                  label: 'Recurso afetado',
                  value: _fallback(
                    entry.targetLabel ?? entry.targetType,
                    'Sem recurso relacionado',
                  ),
                ),
                _DetailLine(
                  label: 'ID recurso',
                  value: safeAdminSensitiveText(
                    _fallback(entry.targetId, 'Sem recurso relacionado'),
                    fallback: 'Sem recurso relacionado',
                  ),
                ),
                _DetailLine(
                  label: 'Motivo',
                  value: safeAdminSensitiveText(
                    _fallback(entry.reason, 'Sem contexto registrado'),
                    fallback: 'Sem contexto registrado',
                  ),
                ),
                _DetailLine(
                  label: 'IP',
                  value: safeAdminSensitiveText(
                    _fallback(entry.ipAddress, 'Indisponivel'),
                    fallback: 'Indisponivel',
                  ),
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
          if (entry.companyId != null)
            TextButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                context.go('/companies/${entry.companyId}/support');
              },
              icon: const Icon(Icons.support_agent_rounded),
              label: const Text('Abrir central de suporte'),
            ),
          if (_isAdminPermissionEvent(entry.action) &&
              entry.actorUserId?.trim().isNotEmpty == true)
            TextButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                context.go('/permissions?adminUserId=${entry.actorUserId}');
              },
              icon: const Icon(Icons.admin_panel_settings_rounded),
              label: const Text('Abrir permissoes'),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }
}

class _NavigationCell extends StatelessWidget {
  const _NavigationCell({required this.entry});

  final AdminAuditEntry entry;

  @override
  Widget build(BuildContext context) {
    final actions = <Widget>[];
    if (entry.companyId != null) {
      actions.add(
        OutlinedButton.icon(
          onPressed: () => context.go('/companies/${entry.companyId}/support'),
          icon: const Icon(Icons.support_agent_rounded),
          label: const Text('Suporte'),
        ),
      );
    }
    if (_isAdminPermissionEvent(entry.action) &&
        entry.actorUserId?.trim().isNotEmpty == true) {
      actions.add(
        OutlinedButton.icon(
          onPressed: () =>
              context.go('/permissions?adminUserId=${entry.actorUserId}'),
          icon: const Icon(Icons.admin_panel_settings_rounded),
          label: const Text('Permissoes'),
        ),
      );
    }
    if (_isRevokeSessionEvent(entry.action) && entry.companyId != null) {
      actions.add(
        OutlinedButton.icon(
          onPressed: () => context.go('/companies/${entry.companyId}/sessions'),
          icon: const Icon(Icons.login_rounded),
          label: const Text('Sessoes'),
        ),
      );
    }
    if (actions.isEmpty) {
      return const Text('Sem recurso relacionado');
    }
    return Wrap(spacing: 8, runSpacing: 8, children: actions);
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

List<AdminAuditEntry> _filterEntries(
  List<AdminAuditEntry> entries, {
  required String toneFilter,
}) {
  return entries
      .where((entry) {
        final tone = _auditTone(entry);
        return switch (toneFilter) {
          'ok' => tone == AdminOperationalTone.ok,
          'attention' => tone == AdminOperationalTone.attention,
          'critical' => tone == AdminOperationalTone.critical,
          'no_data' => tone == AdminOperationalTone.noData,
          _ => true,
        };
      })
      .toList(growable: false);
}

List<AdminAuditEntry> _sortEntries(
  List<AdminAuditEntry> entries,
  String sortBy,
) {
  final sorted = [...entries];
  sorted.sort((a, b) {
    final result = switch (sortBy) {
      'oldest' => _compareNullableDateAsc(a.createdAt, b.createdAt),
      'criticality' => _auditRank(a).compareTo(_auditRank(b)),
      'category' => _operationalCategory(a).compareTo(_operationalCategory(b)),
      'company' => _companyLabel(a).compareTo(_companyLabel(b)),
      'action' => _friendlyAction(
        a.action,
      ).compareTo(_friendlyAction(b.action)),
      _ => _compareNullableDateDesc(a.createdAt, b.createdAt),
    };
    if (result != 0) {
      return result;
    }
    return _friendlyAction(a.action).compareTo(_friendlyAction(b.action));
  });
  return sorted;
}

int _compareNullableDateAsc(DateTime? a, DateTime? b) {
  if (a == null && b == null) {
    return 0;
  }
  if (a == null) {
    return 1;
  }
  if (b == null) {
    return -1;
  }
  return a.compareTo(b);
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

int _auditRank(AdminAuditEntry entry) {
  return switch (_auditTone(entry)) {
    AdminOperationalTone.critical => 0,
    AdminOperationalTone.attention => 1,
    AdminOperationalTone.ok => 2,
    AdminOperationalTone.noData => 3,
  };
}

AdminOperationalTone _auditTone(AdminAuditEntry entry) {
  final status = entry.status.toLowerCase();
  final action = entry.action.toLowerCase();
  if (status.contains('failed') ||
      status.contains('error') ||
      status.contains('denied') ||
      action.contains('failed') ||
      action.contains('block') ||
      action.contains('suspend')) {
    return AdminOperationalTone.critical;
  }
  if (status.contains('pending') ||
      status.contains('running') ||
      entry.category.toLowerCase() == 'sync') {
    return AdminOperationalTone.attention;
  }
  if (status.contains('success') || status.contains('info')) {
    return AdminOperationalTone.ok;
  }
  return AdminOperationalTone.noData;
}

String _operationalLabel(AdminOperationalTone tone) {
  return switch (tone) {
    AdminOperationalTone.ok => 'OK',
    AdminOperationalTone.attention => 'Atencao',
    AdminOperationalTone.critical => 'Critico',
    AdminOperationalTone.noData => 'Sem dados',
  };
}

String _operationalCategory(AdminAuditEntry entry) {
  final category = entry.category.toLowerCase();
  final action = entry.action.toLowerCase();
  final source = entry.source.toLowerCase();
  if (_isAdminPermissionEvent(action) || action.contains('permission')) {
    return 'Permissoes';
  }
  if (_isSupportActionEvent(action)) {
    return 'Support-actions';
  }
  if (category == 'session' || action.contains('session')) {
    return 'Sessoes';
  }
  if (category == 'access' || category == 'user' || action.contains('access')) {
    return 'Usuarios';
  }
  if (category == 'device' || action.contains('device')) {
    return 'Dispositivos';
  }
  if (category == 'billing' || source.contains('billing')) {
    return 'Billing';
  }
  if (category == 'license' || action.contains('license')) {
    return 'Licencas';
  }
  if (category == 'sync' || action.contains('sync')) {
    return 'Sync Center';
  }
  if (category == 'security' || action.contains('auth')) {
    return 'Seguranca';
  }
  if (category == 'system' || source == 'system') {
    return 'Sistema';
  }
  return 'Outros';
}

String _companyLabel(AdminAuditEntry entry) {
  final name = entry.companyName?.trim();
  if (name != null && name.isNotEmpty) {
    return name;
  }
  final id = entry.companyId?.trim();
  if (id != null && id.isNotEmpty) {
    return id;
  }
  return 'Nao informado';
}

String _actorLabel(AdminAuditEntry entry) {
  final label = entry.actorLabel.trim();
  if (label.isEmpty || label == 'Sistema') {
    return label == 'Sistema' ? label : 'Nao informado';
  }
  return label;
}

String _resultLabel(String status) {
  final label = _label(status);
  return label == status && status.trim().isEmpty ? 'Indisponivel' : label;
}

String _originContext(AdminAuditEntry entry) {
  final source = _label(entry.source);
  final summary = entry.summary?.trim();
  if (summary != null && summary.isNotEmpty) {
    return '$source - $summary';
  }
  return source.trim().isEmpty ? 'Sem contexto registrado' : source;
}

String _fallback(String? value, String fallback) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return fallback;
  }
  return trimmed;
}

String _emptyAuditMessage(AdminAuditQuery query) {
  if ((query.companyId ?? '').trim().isNotEmpty) {
    return 'Nenhum evento de auditoria encontrado para a empresa com os filtros atuais.';
  }
  if ((query.category ?? '').trim().isNotEmpty ||
      (query.status ?? '').trim().isNotEmpty ||
      (query.search ?? '').trim().isNotEmpty) {
    return 'Nenhum resultado com o filtro atual. Revise categoria, status, ator ou periodo.';
  }
  return 'Nenhum evento de auditoria encontrado.';
}

String _friendlyAction(String action) {
  switch (action) {
    case 'admin.permissions.grant':
    case 'admin-permissions.grant':
      return 'Permissao administrativa concedida';
    case 'admin.permissions.revoke':
    case 'admin-permissions.revoke':
      return 'Permissao administrativa revogada';
    case 'admin.permissions.list':
    case 'admin-permissions.list':
      return 'Consulta de permissoes administrativas';
    case 'admin.permissions.bootstrap':
    case 'admin-permissions.bootstrap':
      return 'Bootstrap de permissoes administrativas';
    case 'admin.sessions.legacy_revoke.used':
      return 'Uso da rota legada de sessao';
    case 'support.revoke_session.dry_run':
    case 'support.revoke_session.dry_run.succeeded':
      return 'Dry-run de revoke_session';
    case 'support.revoke_session.execute_requested':
      return 'Solicitacao de execute revoke_session';
    case 'support.revoke_session.execute_succeeded':
      return 'revoke_session executado';
    case 'support.revoke_session.execute_failed':
      return 'Falha no execute revoke_session';
    case 'support.revoke_session.execute_denied':
      return 'execute revoke_session negado';
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

bool _isAdminPermissionEvent(String action) {
  final normalized = action.toLowerCase();
  return normalized.contains('admin.permissions') ||
      normalized.contains('admin-permissions') ||
      normalized.contains('admin_permission');
}

bool _isSupportActionEvent(String action) {
  final normalized = action.toLowerCase();
  return normalized.startsWith('support.') ||
      normalized.contains('support_action') ||
      normalized.contains('support-action');
}

bool _isRevokeSessionEvent(String action) {
  final normalized = action.toLowerCase();
  return normalized.contains('revoke_session') ||
      normalized == 'admin.sessions.legacy_revoke.used';
}

String _label(String value) {
  switch (value.toLowerCase()) {
    case 'billing':
      return 'Billing';
    case 'license':
      return 'Licenca';
    case 'access':
      return 'Acesso';
    case 'user':
      return 'Usuario';
    case 'device':
      return 'Dispositivo';
    case 'sync':
      return 'Sync Center';
    case 'session':
      return 'Sessao';
    case 'security':
      return 'Seguranca';
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
    case 'ok':
      return 'OK';
    case 'attention':
      return 'Atencao';
    case 'critical':
      return 'Critico';
    case 'no_data':
      return 'Sem dados';
    case 'newest':
      return 'Data mais recente';
    case 'oldest':
      return 'Data mais antiga';
    case 'criticality':
      return 'Criticidade';
    case 'category':
      return 'Categoria';
    case 'company':
      return 'Empresa';
    case 'action':
      return 'Tipo de acao';
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
