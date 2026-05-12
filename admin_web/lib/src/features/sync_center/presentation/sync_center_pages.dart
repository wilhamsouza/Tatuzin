import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/admin_providers.dart';
import '../../../core/models/admin_models.dart';
import '../../../core/models/admin_sync_center_models.dart';
import '../../../core/network/admin_api_client.dart';
import '../../../core/utils/admin_formatters.dart';
import '../../../core/widgets/admin_surface.dart';

class SyncCenterPage extends ConsumerStatefulWidget {
  const SyncCenterPage({super.key});

  @override
  ConsumerState<SyncCenterPage> createState() => _SyncCenterPageState();
}

class _SyncCenterPageState extends ConsumerState<SyncCenterPage> {
  late final TextEditingController _searchController;
  String _status = 'requires_review';
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
    final query = AdminSyncCenterCompaniesQuery(
      page: _page,
      pageSize: _pageSize,
      search: _searchController.text,
      status: _status,
    );
    final companiesAsync = ref.watch(adminSyncCenterCompaniesProvider(query));

    return companiesAsync.when(
      data: (result) {
        final reviewCount = result.items
            .where((company) => company.requiresReview)
            .length;
        final openConflicts = result.items.fold<int>(
          0,
          (total, company) => total + company.openConflictCount,
        );
        final failures = result.items.fold<int>(
          0,
          (total, company) => total + company.failedCount,
        );
        final pending = result.items.fold<int>(
          0,
          (total, company) => total + company.pendingCount,
        );
        return SingleChildScrollView(
          child: AdminSurface(
            title: 'Sincronização',
            subtitle:
                'Centro interno para diagnosticar e resolver problemas de sync operacional com auditoria.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _MetricCard(
                      label: 'Empresas com revisão',
                      value: '$reviewCount',
                      icon: Icons.fact_check_rounded,
                    ),
                    _MetricCard(
                      label: 'Conflitos abertos',
                      value: '$openConflicts',
                      icon: Icons.report_problem_rounded,
                    ),
                    _MetricCard(
                      label: 'Falhas',
                      value: '$failures',
                      icon: Icons.error_outline_rounded,
                    ),
                    _MetricCard(
                      label: 'Eventos pendentes',
                      value: '$pending',
                      icon: Icons.pending_actions_rounded,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _CompanyFilters(
                  searchController: _searchController,
                  status: _status,
                  pageSize: _pageSize,
                  onApply: ({required status, required pageSize}) {
                    setState(() {
                      _status = status;
                      _pageSize = pageSize;
                      _page = 1;
                    });
                  },
                  onClear: () {
                    _searchController.clear();
                    setState(() {
                      _status = 'requires_review';
                      _pageSize = 20;
                      _page = 1;
                    });
                  },
                ),
                const SizedBox(height: 20),
                if (result.items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Text('Nenhuma empresa encontrada para os filtros.'),
                  )
                else
                  _CompaniesTable(
                    companies: result.items,
                    onOpen: (companyId) => context.go('/sync/$companyId'),
                  ),
                const SizedBox(height: 20),
                _PaginationBar(
                  pagination: result.pagination,
                  itemLabel: 'empresas',
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
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ErrorSurface(
        title: 'Não foi possível carregar Sincronização',
        error: error,
        onRetry: () => ref.invalidate(adminSyncCenterCompaniesProvider(query)),
      ),
    );
  }
}

class SyncCompanyPage extends ConsumerStatefulWidget {
  const SyncCompanyPage({super.key, required this.companyId});

  final String companyId;

  @override
  ConsumerState<SyncCompanyPage> createState() => _SyncCompanyPageState();
}

class _SyncCompanyPageState extends ConsumerState<SyncCompanyPage> {
  int _eventsPage = 1;
  int _conflictsPage = 1;

  @override
  Widget build(BuildContext context) {
    final summaryAsync = ref.watch(
      adminSyncCenterCompanySummaryProvider(widget.companyId),
    );
    final eventsQuery = AdminSyncCenterEventsQuery(
      companyId: widget.companyId,
      page: _eventsPage,
      pageSize: 20,
    );
    final conflictsQuery = AdminSyncCenterConflictsQuery(
      companyId: widget.companyId,
      page: _conflictsPage,
      pageSize: 20,
    );
    final eventsAsync = ref.watch(adminSyncCenterEventsProvider(eventsQuery));
    final conflictsAsync = ref.watch(
      adminSyncCenterConflictsProvider(conflictsQuery),
    );

    return summaryAsync.when(
      data: (summary) => SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AdminSurface(
              title: summary.company.companyName,
              subtitle: summary.recommendation,
              child: _CompanySummary(summary: summary),
            ),
            const SizedBox(height: 24),
            DefaultTabController(
              length: 4,
              child: AdminSurface(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const TabBar(
                      isScrollable: true,
                      tabs: [
                        Tab(text: 'Eventos'),
                        Tab(text: 'Conflitos'),
                        Tab(text: 'Incidentes'),
                        Tab(text: 'Auditoria'),
                      ],
                    ),
                    SizedBox(
                      height: 620,
                      child: TabBarView(
                        children: [
                          _EventsTab(
                            companyId: widget.companyId,
                            eventsAsync: eventsAsync,
                            onPrevious:
                                eventsAsync.value?.pagination.hasPrevious ==
                                    true
                                ? () => setState(() => _eventsPage--)
                                : null,
                            onNext:
                                eventsAsync.value?.pagination.hasNext == true
                                ? () => setState(() => _eventsPage++)
                                : null,
                          ),
                          _ConflictsTab(
                            companyId: widget.companyId,
                            conflictsAsync: conflictsAsync,
                            onPrevious:
                                conflictsAsync.value?.pagination.hasPrevious ==
                                    true
                                ? () => setState(() => _conflictsPage--)
                                : null,
                            onNext:
                                conflictsAsync.value?.pagination.hasNext == true
                                ? () => setState(() => _conflictsPage++)
                                : null,
                          ),
                          _IncidentsTab(incidents: summary.latestIncidents),
                          const _AuditTab(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ErrorSurface(
        title: 'Não foi possível carregar resumo da empresa',
        error: error,
        onRetry: () => ref.invalidate(
          adminSyncCenterCompanySummaryProvider(widget.companyId),
        ),
      ),
    );
  }
}

class SyncEventDetailPage extends ConsumerStatefulWidget {
  const SyncEventDetailPage({
    super.key,
    required this.companyId,
    required this.eventId,
  });

  final String companyId;
  final String eventId;

  @override
  ConsumerState<SyncEventDetailPage> createState() =>
      _SyncEventDetailPageState();
}

class _SyncEventDetailPageState extends ConsumerState<SyncEventDetailPage> {
  bool _isRunning = false;
  bool _dryRunApproved = false;

  @override
  Widget build(BuildContext context) {
    final key = AdminSyncCenterDetailKey(
      companyId: widget.companyId,
      targetId: widget.eventId,
    );
    final detailAsync = ref.watch(adminSyncCenterEventDetailProvider(key));

    return detailAsync.when(
      data: (detail) => SingleChildScrollView(
        child: AdminSurface(
          title:
              'Evento ${adminSyncCenterEntityLabel(detail.event.entity)} / ${adminSyncCenterOperationLabel(detail.event.operation)}',
          subtitle: detail.message,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DiagnosticHeader(
                classification: detail.classification,
                recommendedAction: detail.recommendedAction,
                canReprocess: detail.canReprocess,
                canArchive: detail.canArchive,
              ),
              const SizedBox(height: 20),
              _DetailGrid(
                rows: {
                  'Status': adminSyncCenterStatusLabel(detail.event.status),
                  'Módulo': adminSyncCenterFeatureLabel(detail.event.feature),
                  'Entidade': adminSyncCenterEntityLabel(detail.event.entity),
                  'Operação': adminSyncCenterOperationLabel(
                    detail.event.operation,
                  ),
                  'Código de rejeição':
                      detail.event.rejectionCode ?? 'Sem rejeição',
                  'Criado em': AdminFormatters.formatDateTime(
                    detail.event.createdAt,
                  ),
                  if (detail.conflict != null)
                    'Conflito relacionado': detail.conflict!.conflictId,
                },
              ),
              const SizedBox(height: 20),
              _RiskBlock(risks: detail.risks, blockers: detail.blockers),
              const SizedBox(height: 20),
              _PayloadPreview(payload: detail.event.safePayloadPreview),
              const SizedBox(height: 20),
              _AdvancedPayload(payload: detail.event.payload),
              const SizedBox(height: 20),
              _RelatedIncidents(incidents: detail.incidents),
              const SizedBox(height: 20),
              _EventActions(
                canReprocess: detail.canReprocess,
                dryRunApproved: _dryRunApproved,
                relatedConflictId: detail.conflict?.conflictId,
                companyId: widget.companyId,
                isRunning: _isRunning,
                onDryRun: () => _dryRunReprocess(detail),
                onReprocess: () => _reprocess(detail),
              ),
            ],
          ),
        ),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ErrorSurface(
        title: 'Não foi possível carregar evento',
        error: error,
        onRetry: () => ref.invalidate(adminSyncCenterEventDetailProvider(key)),
      ),
    );
  }

  Future<void> _dryRunReprocess(AdminSyncCenterEventDetail detail) async {
    final reason = await _askReason(context, title: 'Dry-run reprocessar');
    if (reason == null || !mounted) {
      return;
    }
    if (_isRunning) {
      return;
    }
    setState(() => _isRunning = true);
    try {
      final result = await ref
          .read(adminApiServiceProvider)
          .dryRunSyncEventReprocess(
            companyId: widget.companyId,
            eventId: detail.event.id,
            reason: reason,
          );
      if (mounted) {
        setState(() => _dryRunApproved = result.wouldReprocess);
        await _showDryRunResultDialog(context, result);
      }
    } on AdminApiException catch (error) {
      if (!mounted) {
        return;
      }
      _showActionError(context, error.message);
    } finally {
      if (mounted) {
        setState(() => _isRunning = false);
      }
    }
  }

  Future<void> _reprocess(AdminSyncCenterEventDetail detail) async {
    if (!_dryRunApproved) {
      _showActionError(
        context,
        'Rode o dry-run e confirme que o evento pode ser reprocessado antes do write.',
      );
      return;
    }
    final input = await _showSyncWriteDialog(
      context: context,
      title: 'Reprocessar evento',
      warning:
          'Reprocessar pode materializar dados operacionais. Use somente se o dry-run estiver limpo.',
      expectedConfirmation: 'REPROCESSAR',
    );
    if (input == null || !mounted) {
      return;
    }
    await _runAction(
      () => ref
          .read(adminApiServiceProvider)
          .reprocessSyncEvent(
            companyId: widget.companyId,
            eventId: detail.event.id,
            reason: input.reason,
            confirmationText: input.confirmationText,
          ),
      successBuilder: (result) => result.message ?? 'Evento reprocessado.',
      refreshKey: AdminSyncCenterDetailKey(
        companyId: widget.companyId,
        targetId: widget.eventId,
      ),
    );
    if (mounted) {
      setState(() => _dryRunApproved = false);
    }
  }

  Future<void> _runAction<T>(
    Future<T> Function() action, {
    required String Function(T result) successBuilder,
    AdminSyncCenterDetailKey? refreshKey,
  }) async {
    if (_isRunning) {
      return;
    }
    setState(() => _isRunning = true);
    try {
      final result = await action();
      ref.read(adminRefreshTickProvider.notifier).state++;
      if (refreshKey != null) {
        ref.invalidate(adminSyncCenterEventDetailProvider(refreshKey));
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successBuilder(result))));
    } on AdminApiException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isRunning = false);
      }
    }
  }
}

class SyncConflictDetailPage extends ConsumerStatefulWidget {
  const SyncConflictDetailPage({
    super.key,
    required this.companyId,
    required this.conflictId,
  });

  final String companyId;
  final String conflictId;

  @override
  ConsumerState<SyncConflictDetailPage> createState() =>
      _SyncConflictDetailPageState();
}

class _SyncConflictDetailPageState
    extends ConsumerState<SyncConflictDetailPage> {
  bool _isRunning = false;
  bool _archiveDryRunApproved = false;

  @override
  Widget build(BuildContext context) {
    final key = AdminSyncCenterDetailKey(
      companyId: widget.companyId,
      targetId: widget.conflictId,
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
              _DiagnosticHeader(
                classification: detail.classification,
                recommendedAction: detail.recommendedAction,
                canReprocess: detail.canReprocess,
                canArchive: detail.canArchive,
              ),
              const SizedBox(height: 20),
              _LegacyStockMessage(detail: detail),
              const SizedBox(height: 20),
              _DetailGrid(
                rows: {
                  'Status': adminSyncCenterStatusLabel(detail.conflict.status),
                  'Entidade': adminSyncCenterEntityLabel(
                    detail.conflict.entity,
                  ),
                  'Código': detail.conflict.code,
                  'Mensagem': detail.conflict.message,
                  'Criado em': AdminFormatters.formatDateTime(
                    detail.conflict.createdAt,
                  ),
                  'Evento relacionado': detail.event.eventId,
                },
              ),
              const SizedBox(height: 20),
              _RiskBlock(risks: detail.risks, blockers: detail.blockers),
              const SizedBox(height: 20),
              _PayloadPreview(payload: detail.event.safePayloadPreview),
              const SizedBox(height: 20),
              _AdvancedPayload(payload: detail.event.payload),
              const SizedBox(height: 20),
              _RelatedIncidents(incidents: detail.incidents),
              const SizedBox(height: 20),
              _ConflictActions(
                canArchive: detail.canArchive,
                archiveDryRunApproved: _archiveDryRunApproved,
                canCreateManualStockAdjustment:
                    detail.canCreateManualStockAdjustment,
                isRunning: _isRunning,
                onDryRunArchive: () => _dryRunArchive(detail),
                onArchive: () => _archive(detail),
                onDryRunStock: () => _dryRunStock(detail),
              ),
            ],
          ),
        ),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ErrorSurface(
        title: 'Não foi possível carregar conflito',
        error: error,
        onRetry: () =>
            ref.invalidate(adminSyncCenterConflictDetailProvider(key)),
      ),
    );
  }

  Future<void> _dryRunArchive(AdminSyncCenterConflictDetail detail) async {
    final reason = await _askReason(context, title: 'Dry-run arquivar');
    if (reason == null || !mounted) {
      return;
    }
    if (_isRunning) {
      return;
    }
    setState(() => _isRunning = true);
    try {
      final result = await ref
          .read(adminApiServiceProvider)
          .dryRunSyncConflictArchive(
            companyId: widget.companyId,
            conflictId: detail.conflict.conflictId,
            reason: reason,
          );
      if (mounted) {
        setState(() => _archiveDryRunApproved = result.wouldArchive);
        await _showDryRunResultDialog(context, result);
      }
    } on AdminApiException catch (error) {
      if (!mounted) {
        return;
      }
      _showActionError(context, error.message);
    } finally {
      if (mounted) {
        setState(() => _isRunning = false);
      }
    }
  }

  Future<void> _archive(AdminSyncCenterConflictDetail detail) async {
    if (!_archiveDryRunApproved) {
      _showActionError(
        context,
        'Rode o dry-run e confirme que o conflito pode ser arquivado antes do write.',
      );
      return;
    }
    final input = await _showSyncWriteDialog(
      context: context,
      title: 'Arquivar conflito',
      warning:
          'Arquivar não apaga evento, venda, produto ou incidente. A ação registra auditoria.',
      expectedConfirmation: 'ARQUIVAR',
      includeNote: true,
    );
    if (input == null || !mounted) {
      return;
    }
    await _runAction(
      () => ref
          .read(adminApiServiceProvider)
          .archiveSyncConflict(
            companyId: widget.companyId,
            conflictId: detail.conflict.conflictId,
            reason: input.reason,
            confirmationText: input.confirmationText,
            note: input.note,
          ),
      successBuilder: (result) => result.message ?? 'Conflito arquivado.',
      refreshKey: AdminSyncCenterDetailKey(
        companyId: widget.companyId,
        targetId: widget.conflictId,
      ),
    );
    if (mounted) {
      setState(() => _archiveDryRunApproved = false);
    }
  }

  Future<void> _dryRunStock(AdminSyncCenterConflictDetail detail) async {
    final reason = await _askReason(context, title: 'Dry-run ajuste manual');
    if (reason == null || !mounted) {
      return;
    }
    if (_isRunning) {
      return;
    }
    setState(() => _isRunning = true);
    try {
      final result = await ref
          .read(adminApiServiceProvider)
          .dryRunManualStockAdjustment(
            companyId: widget.companyId,
            conflictId: detail.conflict.conflictId,
            reason: reason,
          );
      if (mounted) {
        await _showDryRunResultDialog(context, result);
      }
    } on AdminApiException catch (error) {
      if (!mounted) {
        return;
      }
      _showActionError(context, error.message);
    } finally {
      if (mounted) {
        setState(() => _isRunning = false);
      }
    }
  }

  Future<void> _runAction<T>(
    Future<T> Function() action, {
    required String Function(T result) successBuilder,
    AdminSyncCenterDetailKey? refreshKey,
  }) async {
    if (_isRunning) {
      return;
    }
    setState(() => _isRunning = true);
    try {
      final result = await action();
      ref.read(adminRefreshTickProvider.notifier).state++;
      if (refreshKey != null) {
        ref.invalidate(adminSyncCenterConflictDetailProvider(refreshKey));
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successBuilder(result))));
    } on AdminApiException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isRunning = false);
      }
    }
  }
}

class _CompanyFilters extends StatelessWidget {
  const _CompanyFilters({
    required this.searchController,
    required this.status,
    required this.pageSize,
    required this.onApply,
    required this.onClear,
  });

  final TextEditingController searchController;
  final String status;
  final int pageSize;
  final void Function({required String status, required int pageSize}) onApply;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    var selectedStatus = status;
    var selectedPageSize = pageSize;
    return StatefulBuilder(
      builder: (context, setLocalState) => Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          SizedBox(
            width: 320,
            child: TextField(
              controller: searchController,
              decoration: const InputDecoration(
                labelText: 'Buscar empresa',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onSubmitted: (_) =>
                  onApply(status: selectedStatus, pageSize: selectedPageSize),
            ),
          ),
          SizedBox(
            width: 280,
            child: DropdownButtonFormField<String>(
              initialValue: selectedStatus,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Status'),
              items: const [
                DropdownMenuItem(
                  value: 'requires_review',
                  child: Text('Requer revisão'),
                ),
                DropdownMenuItem(value: 'failed', child: Text('Falhas')),
                DropdownMenuItem(value: 'conflict', child: Text('Conflitos')),
                DropdownMenuItem(value: 'healthy', child: Text('Saudáveis')),
                DropdownMenuItem(value: 'all', child: Text('Todas')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setLocalState(() => selectedStatus = value);
                }
              },
            ),
          ),
          SizedBox(
            width: 120,
            child: DropdownButtonFormField<int>(
              initialValue: selectedPageSize,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Itens'),
              items: const [
                DropdownMenuItem(value: 10, child: Text('10')),
                DropdownMenuItem(value: 20, child: Text('20')),
                DropdownMenuItem(value: 50, child: Text('50')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setLocalState(() => selectedPageSize = value);
                }
              },
            ),
          ),
          FilledButton.icon(
            onPressed: () =>
                onApply(status: selectedStatus, pageSize: selectedPageSize),
            icon: const Icon(Icons.filter_alt_rounded),
            label: const Text('Aplicar'),
          ),
          TextButton(onPressed: onClear, child: const Text('Limpar')),
        ],
      ),
    );
  }
}

class _CompaniesTable extends StatelessWidget {
  const _CompaniesTable({required this.companies, required this.onOpen});

  final List<AdminSyncCenterCompany> companies;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        dataRowMinHeight: 76,
        dataRowMaxHeight: 104,
        columns: const [
          DataColumn(label: Text('Empresa')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Conflitos')),
          DataColumn(label: Text('Erros')),
          DataColumn(label: Text('Pendências')),
          DataColumn(label: Text('Último evento')),
          DataColumn(label: Text('Último incidente')),
          DataColumn(label: Text('Ação')),
        ],
        rows: companies
            .map(
              (company) => DataRow(
                cells: [
                  DataCell(
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          company.companyName,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text(company.companyId),
                      ],
                    ),
                    onTap: () => onOpen(company.companyId),
                  ),
                  DataCell(
                    _StatusChip(
                      label: adminSyncCenterStatusLabel(company.syncStatus),
                    ),
                  ),
                  DataCell(Text('${company.openConflictCount}')),
                  DataCell(Text('${company.failedCount}')),
                  DataCell(Text('${company.pendingCount}')),
                  DataCell(
                    Text(AdminFormatters.formatDateTime(company.lastEventAt)),
                  ),
                  DataCell(
                    Text(
                      AdminFormatters.formatDateTime(company.lastIncidentAt),
                    ),
                  ),
                  DataCell(
                    FilledButton.tonalIcon(
                      onPressed: () => onOpen(company.companyId),
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label: const Text('Abrir'),
                    ),
                  ),
                ],
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _CompanySummary extends StatelessWidget {
  const _CompanySummary({required this.summary});

  final AdminSyncCenterCompanySummary summary;

  @override
  Widget build(BuildContext context) {
    final counts = summary.eventStatusCounts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _MetricCard(
              label: 'currentVersion',
              value: summary.syncState.currentVersion,
              icon: Icons.tag_rounded,
            ),
            _MetricCard(
              label: 'serverFirstSnapshotVersion',
              value: summary.syncState.serverFirstSnapshotVersion,
              icon: Icons.cloud_sync_rounded,
            ),
            _MetricCard(
              label: 'Aceitos',
              value: '${counts.accepted}',
              icon: Icons.check_circle_outline_rounded,
            ),
            _MetricCard(
              label: 'Duplicados',
              value: '${counts.duplicate}',
              icon: Icons.copy_rounded,
            ),
            _MetricCard(
              label: 'Conflitos',
              value: '${counts.conflict}',
              icon: Icons.report_problem_rounded,
            ),
            _MetricCard(
              label: 'Falhas',
              value: '${counts.failed}',
              icon: Icons.error_outline_rounded,
            ),
            _MetricCard(
              label: 'Pendentes',
              value: '${counts.pending}',
              icon: Icons.pending_actions_rounded,
            ),
          ],
        ),
        const SizedBox(height: 20),
        _StatusChip(
          label: summary.requiresReview ? 'Requer revisão' : 'Saudável',
        ),
        const SizedBox(height: 20),
        _EntityCountsTable(counts: summary.entityOperationStatusCounts),
      ],
    );
  }
}

class _EventsTab extends ConsumerStatefulWidget {
  const _EventsTab({
    required this.companyId,
    required this.eventsAsync,
    required this.onPrevious,
    required this.onNext,
  });

  final String companyId;
  final AsyncValue<AdminPaginatedResult<AdminSyncCenterEvent>> eventsAsync;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  ConsumerState<_EventsTab> createState() => _EventsTabState();
}

class _EventsTabState extends ConsumerState<_EventsTab> {
  final Set<String> _approvedDryRuns = <String>{};
  final Set<String> _runningEvents = <String>{};

  @override
  Widget build(BuildContext context) {
    return widget.eventsAsync.when(
      data: (events) => Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: _EventsTable(
                  companyId: widget.companyId,
                  events: events.items,
                  approvedDryRuns: _approvedDryRuns,
                  runningEvents: _runningEvents,
                  onDryRun: _dryRunReprocess,
                  onReprocess: _reprocess,
                ),
              ),
            ),
            _PaginationBar(
              pagination: events.pagination,
              itemLabel: 'eventos',
              onPrevious: widget.onPrevious,
              onNext: widget.onNext,
            ),
          ],
        ),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text(error.toString())),
    );
  }

  Future<void> _dryRunReprocess(AdminSyncCenterEvent event) async {
    final reason = await _askReason(context, title: 'Dry-run reprocessar');
    if (reason == null || !mounted) {
      return;
    }
    if (_runningEvents.contains(event.id)) {
      return;
    }
    setState(() => _runningEvents.add(event.id));
    try {
      final result = await ref
          .read(adminApiServiceProvider)
          .dryRunSyncEventReprocess(
            companyId: widget.companyId,
            eventId: event.id,
            reason: reason,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        if (result.wouldReprocess) {
          _approvedDryRuns.add(event.id);
        } else {
          _approvedDryRuns.remove(event.id);
        }
      });
      await _showDryRunResultDialog(context, result);
    } on AdminApiException catch (error) {
      if (mounted) {
        _showActionError(context, error.message);
      }
    } finally {
      if (mounted) {
        setState(() => _runningEvents.remove(event.id));
      }
    }
  }

  Future<void> _reprocess(AdminSyncCenterEvent event) async {
    if (!_approvedDryRuns.contains(event.id)) {
      _showActionError(
        context,
        'Rode o dry-run e confirme que o evento pode ser reprocessado antes do write.',
      );
      return;
    }
    final input = await _showSyncWriteDialog(
      context: context,
      title: 'Reprocessar evento',
      warning:
          'Reprocessar pode materializar dados operacionais. Use somente se o dry-run estiver limpo.',
      expectedConfirmation: 'REPROCESSAR',
    );
    if (input == null || !mounted) {
      return;
    }
    setState(() => _runningEvents.add(event.id));
    try {
      final result = await ref
          .read(adminApiServiceProvider)
          .reprocessSyncEvent(
            companyId: widget.companyId,
            eventId: event.id,
            reason: input.reason,
            confirmationText: input.confirmationText,
          );
      _approvedDryRuns.remove(event.id);
      ref.read(adminRefreshTickProvider.notifier).state++;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.message ?? 'Evento reprocessado.')),
        );
      }
    } on AdminApiException catch (error) {
      if (mounted) {
        _showActionError(context, error.message);
      }
    } finally {
      if (mounted) {
        setState(() => _runningEvents.remove(event.id));
      }
    }
  }
}

class _EventsTable extends StatelessWidget {
  const _EventsTable({
    required this.companyId,
    required this.events,
    required this.approvedDryRuns,
    required this.runningEvents,
    required this.onDryRun,
    required this.onReprocess,
  });

  final String companyId;
  final List<AdminSyncCenterEvent> events;
  final Set<String> approvedDryRuns;
  final Set<String> runningEvents;
  final ValueChanged<AdminSyncCenterEvent> onDryRun;
  final ValueChanged<AdminSyncCenterEvent> onReprocess;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Text('Nenhum evento encontrado.'),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        dataRowMinHeight: 76,
        dataRowMaxHeight: 104,
        columns: const [
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Ações')),
          DataColumn(label: Text('Entidade')),
          DataColumn(label: Text('Operação')),
          DataColumn(label: Text('Módulo')),
          DataColumn(label: Text('Código de rejeição')),
          DataColumn(label: Text('Classificação')),
          DataColumn(label: Text('Ação recomendada')),
          DataColumn(label: Text('Criado em')),
        ],
        rows: events
            .map(
              (event) => DataRow(
                cells: [
                  DataCell(
                    _StatusChip(
                      label: adminSyncCenterStatusLabel(event.status),
                    ),
                  ),
                  DataCell(
                    _EventRowActions(
                      companyId: companyId,
                      event: event,
                      dryRunApproved: approvedDryRuns.contains(event.id),
                      isRunning: runningEvents.contains(event.id),
                      onDryRun: () => onDryRun(event),
                      onReprocess: () => onReprocess(event),
                    ),
                  ),
                  DataCell(_CellText(adminSyncCenterEntityLabel(event.entity))),
                  DataCell(
                    _CellText(adminSyncCenterOperationLabel(event.operation)),
                  ),
                  DataCell(
                    _CellText(adminSyncCenterFeatureLabel(event.feature)),
                  ),
                  DataCell(_CellText(event.rejectionCode ?? 'Sem rejeição')),
                  DataCell(
                    _CellText(
                      adminSyncCenterClassificationLabel(event.classification),
                    ),
                  ),
                  DataCell(
                    _CellText(
                      adminSyncCenterActionLabel(event.recommendedAction),
                    ),
                  ),
                  DataCell(
                    Text(AdminFormatters.formatDateTime(event.createdAt)),
                  ),
                ],
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _ConflictsTab extends ConsumerStatefulWidget {
  const _ConflictsTab({
    required this.companyId,
    required this.conflictsAsync,
    required this.onPrevious,
    required this.onNext,
  });

  final String companyId;
  final AsyncValue<AdminPaginatedResult<AdminSyncCenterConflict>>
  conflictsAsync;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  ConsumerState<_ConflictsTab> createState() => _ConflictsTabState();
}

class _ConflictsTabState extends ConsumerState<_ConflictsTab> {
  final Set<String> _approvedArchiveDryRuns = <String>{};
  final Set<String> _runningConflicts = <String>{};

  @override
  Widget build(BuildContext context) {
    return widget.conflictsAsync.when(
      data: (conflicts) => Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: _ConflictsTable(
                  companyId: widget.companyId,
                  conflicts: conflicts.items,
                  approvedArchiveDryRuns: _approvedArchiveDryRuns,
                  runningConflicts: _runningConflicts,
                  onDryRunArchive: _dryRunArchive,
                  onArchive: _archive,
                ),
              ),
            ),
            _PaginationBar(
              pagination: conflicts.pagination,
              itemLabel: 'conflitos',
              onPrevious: widget.onPrevious,
              onNext: widget.onNext,
            ),
          ],
        ),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text(error.toString())),
    );
  }

  Future<void> _dryRunArchive(AdminSyncCenterConflict conflict) async {
    final reason = await _askReason(context, title: 'Dry-run arquivar');
    if (reason == null || !mounted) {
      return;
    }
    if (_runningConflicts.contains(conflict.conflictId)) {
      return;
    }
    setState(() => _runningConflicts.add(conflict.conflictId));
    try {
      final result = await ref
          .read(adminApiServiceProvider)
          .dryRunSyncConflictArchive(
            companyId: widget.companyId,
            conflictId: conflict.conflictId,
            reason: reason,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        if (result.wouldArchive) {
          _approvedArchiveDryRuns.add(conflict.conflictId);
        } else {
          _approvedArchiveDryRuns.remove(conflict.conflictId);
        }
      });
      await _showDryRunResultDialog(context, result);
    } on AdminApiException catch (error) {
      if (mounted) {
        _showActionError(context, error.message);
      }
    } finally {
      if (mounted) {
        setState(() => _runningConflicts.remove(conflict.conflictId));
      }
    }
  }

  Future<void> _archive(AdminSyncCenterConflict conflict) async {
    if (!_approvedArchiveDryRuns.contains(conflict.conflictId)) {
      _showActionError(
        context,
        'Rode o dry-run e confirme que o conflito pode ser arquivado antes do write.',
      );
      return;
    }
    final input = await _showSyncWriteDialog(
      context: context,
      title: 'Arquivar conflito',
      warning:
          'Arquivar não apaga evento, venda, produto ou incidente. A ação registra auditoria.',
      expectedConfirmation: 'ARQUIVAR',
      includeNote: true,
    );
    if (input == null || !mounted) {
      return;
    }
    setState(() => _runningConflicts.add(conflict.conflictId));
    try {
      final result = await ref
          .read(adminApiServiceProvider)
          .archiveSyncConflict(
            companyId: widget.companyId,
            conflictId: conflict.conflictId,
            reason: input.reason,
            confirmationText: input.confirmationText,
            note: input.note,
          );
      _approvedArchiveDryRuns.remove(conflict.conflictId);
      ref.read(adminRefreshTickProvider.notifier).state++;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.message ?? 'Conflito arquivado.')),
        );
      }
    } on AdminApiException catch (error) {
      if (mounted) {
        _showActionError(context, error.message);
      }
    } finally {
      if (mounted) {
        setState(() => _runningConflicts.remove(conflict.conflictId));
      }
    }
  }
}

class _ConflictsTable extends StatelessWidget {
  const _ConflictsTable({
    required this.companyId,
    required this.conflicts,
    required this.approvedArchiveDryRuns,
    required this.runningConflicts,
    required this.onDryRunArchive,
    required this.onArchive,
  });

  final String companyId;
  final List<AdminSyncCenterConflict> conflicts;
  final Set<String> approvedArchiveDryRuns;
  final Set<String> runningConflicts;
  final ValueChanged<AdminSyncCenterConflict> onDryRunArchive;
  final ValueChanged<AdminSyncCenterConflict> onArchive;

  @override
  Widget build(BuildContext context) {
    if (conflicts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Text('Nenhum conflito encontrado.'),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Ações')),
          DataColumn(label: Text('Código')),
          DataColumn(label: Text('Entidade')),
          DataColumn(label: Text('Mensagem')),
          DataColumn(label: Text('Classificação')),
          DataColumn(label: Text('Ação recomendada')),
          DataColumn(label: Text('Criado em')),
        ],
        rows: conflicts
            .map(
              (conflict) => DataRow(
                cells: [
                  DataCell(
                    _StatusChip(
                      label: adminSyncCenterStatusLabel(conflict.status),
                    ),
                  ),
                  DataCell(
                    _ConflictRowActions(
                      companyId: companyId,
                      conflict: conflict,
                      archiveDryRunApproved: approvedArchiveDryRuns.contains(
                        conflict.conflictId,
                      ),
                      isRunning: runningConflicts.contains(conflict.conflictId),
                      onDryRunArchive: () => onDryRunArchive(conflict),
                      onArchive: () => onArchive(conflict),
                    ),
                  ),
                  DataCell(_CellText(conflict.code, width: 180)),
                  DataCell(
                    _CellText(adminSyncCenterEntityLabel(conflict.entity)),
                  ),
                  DataCell(_CellText(conflict.message, width: 320)),
                  DataCell(
                    _CellText(
                      adminSyncCenterClassificationLabel(
                        conflict.classification,
                      ),
                    ),
                  ),
                  DataCell(
                    _CellText(
                      adminSyncCenterActionLabel(conflict.recommendedAction),
                    ),
                  ),
                  DataCell(
                    Text(AdminFormatters.formatDateTime(conflict.createdAt)),
                  ),
                ],
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _EventRowActions extends StatelessWidget {
  const _EventRowActions({
    required this.companyId,
    required this.event,
    required this.dryRunApproved,
    required this.isRunning,
    required this.onDryRun,
    required this.onReprocess,
  });

  final String companyId;
  final AdminSyncCenterEvent event;
  final bool dryRunApproved;
  final bool isRunning;
  final VoidCallback onDryRun;
  final VoidCallback onReprocess;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 560,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.tonalIcon(
            onPressed: () => context.go('/sync/$companyId/events/${event.id}'),
            icon: const Icon(Icons.visibility_rounded),
            label: const Text('Detalhes'),
          ),
          if (event.canReprocess) ...[
            FilledButton.tonalIcon(
              onPressed: isRunning ? null : onDryRun,
              icon: const Icon(Icons.science_rounded),
              label: const Text('Dry-run'),
            ),
            Tooltip(
              message: dryRunApproved
                  ? 'Dry-run aprovado para este evento.'
                  : 'Rode o dry-run antes de reprocessar.',
              child: FilledButton.icon(
                onPressed: isRunning || !dryRunApproved ? null : onReprocess,
                icon: const Icon(Icons.sync_rounded),
                label: const Text('Reprocessar'),
              ),
            ),
          ] else
            Tooltip(
              message: _eventBlockedMessage(event),
              child: OutlinedButton.icon(
                onPressed: null,
                icon: const Icon(Icons.lock_rounded),
                label: const Text('Bloqueado por segurança'),
              ),
            ),
          if (event.relatedConflictId != null)
            FilledButton.tonalIcon(
              onPressed: () => context.go(
                '/sync/$companyId/conflicts/${event.relatedConflictId}',
              ),
              icon: const Icon(Icons.report_problem_rounded),
              label: const Text('Ver conflito'),
            ),
        ],
      ),
    );
  }
}

class _ConflictRowActions extends StatelessWidget {
  const _ConflictRowActions({
    required this.companyId,
    required this.conflict,
    required this.archiveDryRunApproved,
    required this.isRunning,
    required this.onDryRunArchive,
    required this.onArchive,
  });

  final String companyId;
  final AdminSyncCenterConflict conflict;
  final bool archiveDryRunApproved;
  final bool isRunning;
  final VoidCallback onDryRunArchive;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 620,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.tonalIcon(
            onPressed: () =>
                context.go('/sync/$companyId/conflicts/${conflict.conflictId}'),
            icon: const Icon(Icons.visibility_rounded),
            label: const Text('Detalhes'),
          ),
          FilledButton.tonalIcon(
            onPressed: isRunning ? null : onDryRunArchive,
            icon: const Icon(Icons.science_rounded),
            label: const Text('Dry-run arquivar'),
          ),
          if (conflict.canArchive)
            Tooltip(
              message: archiveDryRunApproved
                  ? 'Dry-run aprovado para este conflito.'
                  : 'Rode o dry-run antes de arquivar.',
              child: FilledButton.icon(
                onPressed: isRunning || !archiveDryRunApproved
                    ? null
                    : onArchive,
                icon: const Icon(Icons.archive_rounded),
                label: const Text('Arquivar legado'),
              ),
            )
          else
            Tooltip(
              message:
                  'Arquivamento bloqueado pela classificação de segurança.',
              child: OutlinedButton.icon(
                onPressed: null,
                icon: const Icon(Icons.lock_rounded),
                label: const Text('Bloqueado por segurança'),
              ),
            ),
          if (conflict.canCreateManualStockAdjustment)
            FilledButton.tonalIcon(
              onPressed: () => context.go(
                '/sync/$companyId/conflicts/${conflict.conflictId}',
              ),
              icon: const Icon(Icons.inventory_2_rounded),
              label: const Text('Ajuste manual'),
            )
          else
            const Chip(label: Text('Ajuste manual indisponível')),
        ],
      ),
    );
  }
}

class _IncidentsTab extends StatelessWidget {
  const _IncidentsTab({required this.incidents});

  final List<AdminSyncCenterIncident> incidents;

  @override
  Widget build(BuildContext context) {
    if (incidents.isEmpty) {
      return const Center(child: Text('Nenhum incidente recente.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.only(top: 16),
      itemCount: incidents.length,
      separatorBuilder: (_, __) => const Divider(),
      itemBuilder: (context, index) {
        final incident = incidents[index];
        return ListTile(
          leading: const Icon(Icons.warning_amber_rounded),
          title: Text(incident.code),
          subtitle: Text(incident.message),
          trailing: Text(AdminFormatters.formatDateTime(incident.createdAt)),
        );
      },
    );
  }
}

class _AuditTab extends StatelessWidget {
  const _AuditTab();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Auditoria registrada no log administrativo da plataforma.'),
    );
  }
}

class _EntityCountsTable extends StatelessWidget {
  const _EntityCountsTable({required this.counts});

  final List<AdminSyncCenterEntityOperationStatusCount> counts;

  @override
  Widget build(BuildContext context) {
    if (counts.isEmpty) {
      return const Text('Sem contadores por entidade.');
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Entidade')),
          DataColumn(label: Text('Operação')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Total')),
        ],
        rows: counts
            .map(
              (count) => DataRow(
                cells: [
                  DataCell(_CellText(adminSyncCenterEntityLabel(count.entity))),
                  DataCell(
                    _CellText(adminSyncCenterOperationLabel(count.operation)),
                  ),
                  DataCell(Text(adminSyncCenterStatusLabel(count.status))),
                  DataCell(Text('${count.count}')),
                ],
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _DiagnosticHeader extends StatelessWidget {
  const _DiagnosticHeader({
    required this.classification,
    required this.recommendedAction,
    required this.canReprocess,
    required this.canArchive,
  });

  final String classification;
  final String recommendedAction;
  final bool canReprocess;
  final bool canArchive;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _StatusChip(label: adminSyncCenterClassificationLabel(classification)),
        _StatusChip(label: adminSyncCenterActionLabel(recommendedAction)),
        _StatusChip(
          label: canReprocess ? 'Reprocessável' : 'Bloqueado por segurança',
        ),
        _StatusChip(
          label: canArchive ? 'Pode arquivar' : 'Arquivamento bloqueado',
        ),
      ],
    );
  }
}

class _LegacyStockMessage extends StatelessWidget {
  const _LegacyStockMessage({required this.detail});

  final AdminSyncCenterConflictDetail detail;

  @override
  Widget build(BuildContext context) {
    if (detail.classification != 'IRRECOVERABLE_LEGACY_EVENT' ||
        detail.conflict.entity != 'stockDeduction') {
      return const SizedBox.shrink();
    }
    return const _NoticeBox(
      message:
          'Evento antigo sem identificação remota segura. Não é recomendado reprocessar automaticamente. Revise estoque manualmente ou arquive como evento legado de teste.',
    );
  }
}

class _RiskBlock extends StatelessWidget {
  const _RiskBlock({required this.risks, required this.blockers});

  final List<String> risks;
  final List<String> blockers;

  @override
  Widget build(BuildContext context) {
    if (risks.isEmpty && blockers.isEmpty) {
      return const Text('Sem bloqueios adicionais registrados.');
    }
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        _TextList(title: 'Riscos', items: risks),
        _TextList(title: 'Bloqueios', items: blockers),
      ],
    );
  }
}

class _PayloadPreview extends StatelessWidget {
  const _PayloadPreview({required this.payload});

  final Map<String, dynamic> payload;

  @override
  Widget build(BuildContext context) {
    return AdminSurface(
      title: 'Payload preview',
      subtitle: 'Campos seguros para diagnóstico.',
      padding: const EdgeInsets.all(16),
      child: _JsonLines(payload: payload),
    );
  }
}

class _AdvancedPayload extends StatelessWidget {
  const _AdvancedPayload({required this.payload});

  final Map<String, dynamic> payload;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: const Text('Payload sanitizado avançado'),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SelectableText(
            const JsonEncoder.withIndent('  ').convert(payload),
          ),
        ),
      ],
    );
  }
}

class _RelatedIncidents extends StatelessWidget {
  const _RelatedIncidents({required this.incidents});

  final List<AdminSyncCenterIncident> incidents;

  @override
  Widget build(BuildContext context) {
    if (incidents.isEmpty) {
      return const Text('Sem incidente relacionado.');
    }
    return AdminSurface(
      title: 'Incidente relacionado',
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: incidents
            .map(
              (incident) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.warning_amber_rounded),
                title: Text(incident.code),
                subtitle: Text(incident.message),
                trailing: Text(
                  AdminFormatters.formatDateTime(incident.createdAt),
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _EventActions extends StatelessWidget {
  const _EventActions({
    required this.canReprocess,
    required this.dryRunApproved,
    required this.relatedConflictId,
    required this.companyId,
    required this.isRunning,
    required this.onDryRun,
    required this.onReprocess,
  });

  final bool canReprocess;
  final bool dryRunApproved;
  final String? relatedConflictId;
  final String companyId;
  final bool isRunning;
  final VoidCallback onDryRun;
  final VoidCallback onReprocess;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        FilledButton.tonalIcon(
          onPressed: isRunning ? null : onDryRun,
          icon: const Icon(Icons.science_rounded),
          label: const Text('Dry-run reprocessar'),
        ),
        if (canReprocess)
          Tooltip(
            message: dryRunApproved
                ? 'Dry-run aprovado para este evento.'
                : 'Rode o dry-run antes de reprocessar.',
            child: FilledButton.icon(
              onPressed: !dryRunApproved || isRunning ? null : onReprocess,
              icon: const Icon(Icons.sync_rounded),
              label: const Text('Reprocessar'),
            ),
          )
        else
          OutlinedButton.icon(
            onPressed: null,
            icon: const Icon(Icons.lock_rounded),
            label: const Text('Bloqueado por segurança'),
          ),
        if (!canReprocess)
          const Chip(label: Text('Reprocessamento automático bloqueado')),
        if (relatedConflictId != null)
          FilledButton.tonalIcon(
            onPressed: () =>
                context.go('/sync/$companyId/conflicts/$relatedConflictId'),
            icon: const Icon(Icons.report_problem_rounded),
            label: const Text('Ver conflito'),
          ),
      ],
    );
  }
}

class _ConflictActions extends StatelessWidget {
  const _ConflictActions({
    required this.canArchive,
    required this.archiveDryRunApproved,
    required this.canCreateManualStockAdjustment,
    required this.isRunning,
    required this.onDryRunArchive,
    required this.onArchive,
    required this.onDryRunStock,
  });

  final bool canArchive;
  final bool archiveDryRunApproved;
  final bool canCreateManualStockAdjustment;
  final bool isRunning;
  final VoidCallback onDryRunArchive;
  final VoidCallback onArchive;
  final VoidCallback onDryRunStock;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        FilledButton.tonalIcon(
          onPressed: isRunning ? null : onDryRunArchive,
          icon: const Icon(Icons.science_rounded),
          label: const Text('Dry-run arquivar'),
        ),
        Tooltip(
          message: archiveDryRunApproved
              ? 'Dry-run aprovado para este conflito.'
              : 'Rode o dry-run antes de arquivar.',
          child: FilledButton.icon(
            onPressed: !canArchive || !archiveDryRunApproved || isRunning
                ? null
                : onArchive,
            icon: const Icon(Icons.archive_rounded),
            label: const Text('Arquivar legado'),
          ),
        ),
        if (canCreateManualStockAdjustment)
          FilledButton.tonalIcon(
            onPressed: isRunning ? null : onDryRunStock,
            icon: const Icon(Icons.inventory_2_rounded),
            label: const Text('Dry-run ajuste manual'),
          )
        else
          const Chip(label: Text('Ajuste manual indisponível')),
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
    final theme = Theme.of(context);
    return SizedBox(
      width: 220,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      style: theme.textTheme.titleLarge?.copyWith(
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

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text(label));
  }
}

class _CellText extends StatelessWidget {
  const _CellText(this.value, {this.width = 160});

  final String value;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: value,
      child: SizedBox(
        width: width,
        child: Text(value, maxLines: 2, overflow: TextOverflow.ellipsis),
      ),
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
          .map(
            (entry) => SizedBox(
              width: 260,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.key,
                        style: Theme.of(context).textTheme.bodySmall,
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
            ),
          )
          .toList(growable: false),
    );
  }
}

class _JsonLines extends StatelessWidget {
  const _JsonLines({required this.payload});

  final Map<String, dynamic> payload;

  @override
  Widget build(BuildContext context) {
    if (payload.isEmpty) {
      return const Text('Sem preview seguro disponível.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: payload.entries
          .map(
            (entry) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: SelectableText('${entry.key}: ${entry.value}'),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _TextList extends StatelessWidget {
  const _TextList({required this.title, required this.items});

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 360,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              if (items.isEmpty)
                const Text('Nenhum.')
              else
                ...items.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(item),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoticeBox extends StatelessWidget {
  const _NoticeBox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: scheme.onSecondaryContainer,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _PaginationBar extends StatelessWidget {
  const _PaginationBar({
    required this.pagination,
    required this.itemLabel,
    required this.onPrevious,
    required this.onNext,
  });

  final AdminPaginationMeta pagination;
  final String itemLabel;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            '${pagination.count} de ${pagination.total} $itemLabel. Página ${pagination.page}.',
          ),
        ),
        IconButton(
          tooltip: 'Anterior',
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        IconButton(
          tooltip: 'Próxima',
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
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
      subtitle: error.toString(),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.tonal(
          onPressed: onRetry,
          child: const Text('Tentar novamente'),
        ),
      ),
    );
  }
}

String _eventBlockedMessage(AdminSyncCenterEvent event) {
  if (event.classification == 'IRRECOVERABLE_LEGACY_EVENT' &&
      event.entity == 'stockDeduction') {
    return 'Evento antigo sem identificação remota segura. Não é recomendado reprocessar automaticamente.';
  }
  if (event.rejectionMessage != null && event.rejectionMessage!.isNotEmpty) {
    return event.rejectionMessage!;
  }
  return 'A classificação de segurança bloqueia o reprocessamento automático.';
}

void _showActionError(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: Theme.of(context).colorScheme.error,
    ),
  );
}

Future<void> _showDryRunResultDialog(
  BuildContext context,
  AdminSyncCenterDryRunResult result,
) {
  final canExecute =
      result.wouldReprocess ||
      result.wouldArchive ||
      result.canCreateManualStockAdjustment;
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Resultado do dry-run'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DetailGrid(
                rows: {
                  'Pode executar': canExecute ? 'Sim' : 'Não',
                  'Classificação': adminSyncCenterClassificationLabel(
                    result.classification,
                  ),
                  if (result.expectedAction != null)
                    'Ação esperada': adminSyncCenterActionLabel(
                      result.expectedAction!,
                    ),
                },
              ),
              const SizedBox(height: 16),
              if (result.message.isNotEmpty) Text(result.message),
              const SizedBox(height: 16),
              _RiskBlock(risks: result.risks, blockers: result.blockers),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Fechar'),
        ),
      ],
    ),
  );
}

Future<String?> _askReason(
  BuildContext context, {
  required String title,
}) async {
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => _ReasonDialog(title: title),
  );
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.title});

  final String title;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: 3,
        decoration: InputDecoration(
          labelText: 'Motivo obrigatório',
          errorText: _error,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final reason = _controller.text.trim();
            if (reason.isEmpty) {
              setState(() => _error = 'Informe um motivo.');
              return;
            }
            Navigator.of(context).pop(reason);
          },
          child: const Text('Continuar'),
        ),
      ],
    );
  }
}

Future<_SyncActionInput?> _showSyncWriteDialog({
  required BuildContext context,
  required String title,
  required String warning,
  required String expectedConfirmation,
  bool includeNote = false,
}) async {
  return showDialog<_SyncActionInput>(
    context: context,
    builder: (dialogContext) => _SyncWriteDialog(
      title: title,
      warning: warning,
      expectedConfirmation: expectedConfirmation,
      includeNote: includeNote,
    ),
  );
}

class _SyncWriteDialog extends StatefulWidget {
  const _SyncWriteDialog({
    required this.title,
    required this.warning,
    required this.expectedConfirmation,
    required this.includeNote,
  });

  final String title;
  final String warning;
  final String expectedConfirmation;
  final bool includeNote;

  @override
  State<_SyncWriteDialog> createState() => _SyncWriteDialogState();
}

class _SyncWriteDialogState extends State<_SyncWriteDialog> {
  late final TextEditingController _reasonController;
  late final TextEditingController _confirmationController;
  late final TextEditingController _noteController;

  @override
  void initState() {
    super.initState();
    _reasonController = TextEditingController();
    _confirmationController = TextEditingController();
    _noteController = TextEditingController();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _confirmationController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reason = _reasonController.text.trim();
    final confirmation = _confirmationController.text.trim();
    final canSubmit =
        reason.isNotEmpty && confirmation == widget.expectedConfirmation;

    return AlertDialog(
      title: Text(widget.title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.warning),
              const SizedBox(height: 16),
              TextField(
                controller: _reasonController,
                maxLines: 3,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Motivo obrigatório',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirmationController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Texto de confirmação',
                  hintText: widget.expectedConfirmation,
                ),
              ),
              if (widget.includeNote) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _noteController,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Nota opcional'),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: canSubmit
              ? () => Navigator.of(context).pop(
                  _SyncActionInput(
                    reason: reason,
                    confirmationText: confirmation,
                    note: _noteController.text.trim(),
                  ),
                )
              : null,
          child: const Text('Confirmar'),
        ),
      ],
    );
  }
}

class _SyncActionInput {
  const _SyncActionInput({
    required this.reason,
    required this.confirmationText,
    required this.note,
  });

  final String reason;
  final String confirmationText;
  final String note;
}
