import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/admin_providers.dart';
import '../../../core/models/admin_models.dart';
import '../../../core/utils/admin_formatters.dart';
import '../../../core/widgets/admin_surface.dart';

class AuditPage extends ConsumerStatefulWidget {
  const AuditPage({super.key});

  @override
  ConsumerState<AuditPage> createState() => _AuditPageState();
}

class _AuditPageState extends ConsumerState<AuditPage> {
  late final TextEditingController _actionController;
  late final TextEditingController _actorUserIdController;
  late final TextEditingController _companyIdController;
  int _page = 1;
  int _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _actionController = TextEditingController();
    _actorUserIdController = TextEditingController();
    _companyIdController = TextEditingController();
  }

  @override
  void dispose() {
    _actionController.dispose();
    _actorUserIdController.dispose();
    _companyIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = AdminAuditQuery(
      page: _page,
      pageSize: _pageSize,
      action: _actionController.text,
      actorUserId: _actorUserIdController.text,
      companyId: _companyIdController.text,
    );
    final auditAsync = ref.watch(adminAuditSummaryProvider(query));

    return auditAsync.when(
      data: (summary) => SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AdminSurface(
              title: 'Resumo da auditoria administrativa',
              subtitle: 'Mudancas de licenca e eventos do painel cloud.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _AuditFilters(
                    actionController: _actionController,
                    actorUserIdController: _actorUserIdController,
                    companyIdController: _companyIdController,
                    pageSize: _pageSize,
                    onApply: _applyFilters,
                    onClear: _clearFilters,
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      _AuditMetric(
                        title: 'Total de eventos',
                        value: '${summary.totalEvents}',
                      ),
                      ...summary.countsByAction.entries.take(4).map(
                        (entry) => _AuditMetric(
                          title: entry.key,
                          value: '${entry.value}',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            AdminSurface(
              title: 'Eventos recentes',
              subtitle: 'Historico administrativo mais recente da plataforma.',
              child: summary.recentEvents.isEmpty
                  ? const _EmptyState(
                      message: 'Nenhum evento encontrado para os filtros.',
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          children: summary.recentEvents.map((event) {
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                backgroundColor:
                                    Theme.of(context).colorScheme.primaryContainer,
                                child: Icon(
                                  Icons.history_toggle_off_rounded,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                              title: Text(event.action),
                              subtitle: Text(
                                '${event.actorUserName} - ${event.actorUserEmail} - ${AdminFormatters.formatDateTime(event.createdAt)}',
                              ),
                              trailing: SizedBox(
                                width: 220,
                                child: Text(
                                  event.targetCompanyName ?? 'Plataforma',
                                  textAlign: TextAlign.right,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            );
                          }).toList(),
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
        title: 'Nao foi possivel carregar a auditoria',
        subtitle: error.toString(),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonal(
            onPressed: () => ref.invalidate(adminAuditSummaryProvider(query)),
            child: const Text('Tentar novamente'),
          ),
        ),
      ),
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
    setState(() {
      _page = 1;
      _pageSize = 20;
    });
  }
}

class _AuditFilters extends StatefulWidget {
  const _AuditFilters({
    required this.actionController,
    required this.actorUserIdController,
    required this.companyIdController,
    required this.pageSize,
    required this.onApply,
    required this.onClear,
  });

  final TextEditingController actionController;
  final TextEditingController actorUserIdController;
  final TextEditingController companyIdController;
  final int pageSize;
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
            SizedBox(
              width: 220,
              child: TextField(
                controller: widget.actionController,
                decoration: const InputDecoration(labelText: 'Action'),
                onSubmitted: (_) => _apply(),
              ),
            ),
            SizedBox(
              width: 220,
              child: TextField(
                controller: widget.actorUserIdController,
                decoration: const InputDecoration(labelText: 'Actor user ID'),
                onSubmitted: (_) => _apply(),
              ),
            ),
            SizedBox(
              width: 220,
              child: TextField(
                controller: widget.companyIdController,
                decoration: const InputDecoration(labelText: 'Company ID'),
                onSubmitted: (_) => _apply(),
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

  void _apply() => widget.onApply(pageSize: _pageSize);
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
          'Pagina ${pagination.page} • ${pagination.count} de ${pagination.total} eventos',
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
  const _AuditMetric({
    required this.title,
    required this.value,
  });

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
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
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
        ],
      ),
    );
  }
}
