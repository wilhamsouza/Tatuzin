import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/admin_providers.dart';
import '../../../core/models/admin_models.dart';
import '../../../core/models/admin_sync_center_models.dart';
import '../../../core/utils/admin_formatters.dart';
import '../../../core/widgets/admin_surface.dart';

const _remoteActionsNotice =
    'Comandos de suporte sao enviados ao app, executados localmente com dry-run, confirmacao explicita e auditoria.';

const _supportCommands = <_SupportCommandOption>[
  _SupportCommandOption(
    command: 'REFRESH_SYNC_STATUS',
    label: 'Recalcular status',
    expectedConfirmationText: 'RECALCULAR',
  ),
  _SupportCommandOption(
    command: 'FORCE_SYNC_PULL',
    label: 'Forcar pull da nuvem',
    expectedConfirmationText: 'ATUALIZAR',
  ),
  _SupportCommandOption(
    command: 'CLEAR_RESOLVED_CONFLICT_CACHE',
    label: 'Limpar conflitos resolvidos',
    expectedConfirmationText: 'LIMPAR',
  ),
  _SupportCommandOption(
    command: 'REPAIR_OPERATIONAL_ORDER_ITEM_TOTAL_CENTS',
    label: 'Reparar eventos recuperaveis',
    expectedConfirmationText: 'REPARAR',
  ),
  _SupportCommandOption(
    command: 'RETRY_FAILED_SYNC_EVENTS',
    label: 'Reprocessar falhas locais',
    expectedConfirmationText: 'REPROCESSAR',
  ),
];

class _SupportCommandOption {
  const _SupportCommandOption({
    required this.command,
    required this.label,
    required this.expectedConfirmationText,
  });

  final String command;
  final String label;
  final String expectedConfirmationText;
}

class AdminCompanySyncCenterPage extends ConsumerStatefulWidget {
  const AdminCompanySyncCenterPage({super.key, required this.companyId});

  final String companyId;

  @override
  ConsumerState<AdminCompanySyncCenterPage> createState() =>
      _AdminCompanySyncCenterPageState();
}

class _AdminCompanySyncCenterPageState
    extends ConsumerState<AdminCompanySyncCenterPage> {
  int _eventsPage = 1;
  int _openConflictsPage = 1;
  int _historyConflictsPage = 1;
  int _incidentsPage = 1;
  DateTime? _lastRefresh;

  @override
  Widget build(BuildContext context) {
    final healthAsync = ref.watch(
      adminCompanySyncHealthProvider(widget.companyId),
    );
    final devicesAsync = ref.watch(
      adminSyncSupportDevicesProvider(widget.companyId),
    );
    final companyAsync = ref.watch(
      adminCompanyDetailProvider(widget.companyId),
    );

    final eventsQuery = AdminCompanySyncEventsQuery(
      companyId: widget.companyId,
      page: _eventsPage,
      limit: 20,
    );
    final openConflictsQuery = AdminCompanySyncConflictsQuery(
      companyId: widget.companyId,
      page: _openConflictsPage,
      limit: 20,
      status: 'open',
    );
    final historyConflictsQuery = AdminCompanySyncConflictsQuery(
      companyId: widget.companyId,
      page: _historyConflictsPage,
      limit: 20,
    );
    final incidentsQuery = AdminCompanySyncIncidentsQuery(
      companyId: widget.companyId,
      page: _incidentsPage,
      limit: 20,
    );

    final eventsAsync = ref.watch(adminCompanySyncEventsProvider(eventsQuery));
    final openConflictsAsync = ref.watch(
      adminCompanySyncConflictsProvider(openConflictsQuery),
    );
    final historyConflictsAsync = ref.watch(
      adminCompanySyncConflictsProvider(historyConflictsQuery),
    );
    final incidentsAsync = ref.watch(
      adminCompanySyncIncidentsProvider(incidentsQuery),
    );

    return healthAsync.when(
      data: (health) => RefreshIndicator(
        onRefresh: () async => _refresh(
          eventsQuery: eventsQuery,
          openConflictsQuery: openConflictsQuery,
          historyConflictsQuery: historyConflictsQuery,
          incidentsQuery: incidentsQuery,
        ),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Header(
                health: health,
                companyId: widget.companyId,
                lastRefresh: _lastRefresh,
                onBack: () => context.go('/companies/${widget.companyId}'),
                onRefresh: () => _refresh(
                  eventsQuery: eventsQuery,
                  openConflictsQuery: openConflictsQuery,
                  historyConflictsQuery: historyConflictsQuery,
                  incidentsQuery: incidentsQuery,
                ),
              ),
              const SizedBox(height: 16),
              DefaultTabController(
                length: 6,
                child: AdminSurface(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const TabBar(
                        isScrollable: true,
                        tabs: [
                          Tab(text: 'Resumo'),
                          Tab(text: 'Eventos'),
                          Tab(text: 'Conflitos'),
                          Tab(text: 'Incidentes'),
                          Tab(text: 'Dispositivos'),
                          Tab(text: 'Auditoria'),
                        ],
                      ),
                      SizedBox(
                        height: 640,
                        child: TabBarView(
                          children: [
                            _SummaryTab(
                              health: health,
                              eventsAsync: eventsAsync,
                              incidentsAsync: incidentsAsync,
                              devicesAsync: devicesAsync,
                            ),
                            _EventsTab(
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
                              openConflictsAsync: openConflictsAsync,
                              historyConflictsAsync: historyConflictsAsync,
                              onOpenPrevious:
                                  openConflictsAsync
                                          .value
                                          ?.pagination
                                          .hasPrevious ==
                                      true
                                  ? () => setState(() => _openConflictsPage--)
                                  : null,
                              onOpenNext:
                                  openConflictsAsync
                                          .value
                                          ?.pagination
                                          .hasNext ==
                                      true
                                  ? () => setState(() => _openConflictsPage++)
                                  : null,
                              onHistoryPrevious:
                                  historyConflictsAsync
                                          .value
                                          ?.pagination
                                          .hasPrevious ==
                                      true
                                  ? () =>
                                        setState(() => _historyConflictsPage--)
                                  : null,
                              onHistoryNext:
                                  historyConflictsAsync
                                          .value
                                          ?.pagination
                                          .hasNext ==
                                      true
                                  ? () =>
                                        setState(() => _historyConflictsPage++)
                                  : null,
                            ),
                            _IncidentsTab(
                              incidentsAsync: incidentsAsync,
                              onPrevious:
                                  incidentsAsync
                                          .value
                                          ?.pagination
                                          .hasPrevious ==
                                      true
                                  ? () => setState(() => _incidentsPage--)
                                  : null,
                              onNext:
                                  incidentsAsync.value?.pagination.hasNext ==
                                      true
                                  ? () => setState(() => _incidentsPage++)
                                  : null,
                            ),
                            _DevicesTab(
                              companyId: widget.companyId,
                              devicesAsync: devicesAsync,
                              companyAsync: companyAsync,
                            ),
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
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ErrorSurface(
        title: 'Nao foi possivel carregar o console de sync',
        error: error,
        onRetry: () =>
            ref.invalidate(adminCompanySyncHealthProvider(widget.companyId)),
      ),
    );
  }

  Future<void> _refresh({
    required AdminCompanySyncEventsQuery eventsQuery,
    required AdminCompanySyncConflictsQuery openConflictsQuery,
    required AdminCompanySyncConflictsQuery historyConflictsQuery,
    required AdminCompanySyncIncidentsQuery incidentsQuery,
  }) async {
    ref.invalidate(adminCompanySyncHealthProvider(widget.companyId));
    ref.invalidate(adminSyncSupportDevicesProvider(widget.companyId));
    ref.invalidate(adminCompanyDetailProvider(widget.companyId));
    ref.invalidate(adminCompanySyncEventsProvider(eventsQuery));
    ref.invalidate(adminCompanySyncConflictsProvider(openConflictsQuery));
    ref.invalidate(adminCompanySyncConflictsProvider(historyConflictsQuery));
    ref.invalidate(adminCompanySyncIncidentsProvider(incidentsQuery));
    if (mounted) {
      setState(() => _lastRefresh = DateTime.now());
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.health,
    required this.companyId,
    required this.lastRefresh,
    required this.onBack,
    required this.onRefresh,
  });

  final AdminCompanySyncHealth health;
  final String companyId;
  final DateTime? lastRefresh;
  final VoidCallback onBack;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return AdminSurface(
      title: health.companyName,
      subtitle:
          'ID ${_maskId(companyId)} - ${_syncStatusLabel(health.status)} - Ultimo refresh: ${lastRefresh == null ? 'Nao executado nesta tela' : AdminFormatters.formatDateTime(lastRefresh)}',
      trailing: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.business_rounded),
            label: const Text('Voltar para empresa 360'),
          ),
          OutlinedButton.icon(
            onPressed: () =>
                context.go('/audit?companyId=$companyId&category=sync'),
            icon: const Icon(Icons.fact_check_rounded),
            label: const Text('Ver auditoria global filtrada'),
          ),
          FilledButton.tonalIcon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Atualizar'),
          ),
        ],
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          Chip(label: Text(_syncStatusLabel(health.status))),
          Chip(label: Text('Conflitos OPEN: ${health.openConflictsCount}')),
          Chip(label: Text('Eventos: ${health.events.total}')),
          Chip(label: Text('Dispositivos: ${health.devices.total}')),
          const Chip(label: Text('Modo seguro com dry-run')),
        ],
      ),
    );
  }
}

class _SummaryTab extends StatelessWidget {
  const _SummaryTab({
    required this.health,
    required this.eventsAsync,
    required this.incidentsAsync,
    required this.devicesAsync,
  });

  final AdminCompanySyncHealth health;
  final AsyncValue<AdminPaginatedResult<AdminSyncEventDiagnostic>> eventsAsync;
  final AsyncValue<AdminPaginatedResult<AdminSyncIncidentDiagnostic>>
  incidentsAsync;
  final AsyncValue<List<AdminSyncSupportDevice>> devicesAsync;

  @override
  Widget build(BuildContext context) {
    final historyConflicts = health.events.conflict - health.openConflictsCount;
    final recentEvents = eventsAsync.value?.items.length;
    final recentIncidents = incidentsAsync.value?.items.length;
    final mobileDevices = devicesAsync.value?.length;
    return ListView(
      padding: const EdgeInsets.only(top: 16),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _MetricCard(
              label: 'Status geral',
              value: _syncStatusLabel(health.status),
            ),
            _MetricCard(
              label: 'Eventos recentes',
              value: recentEvents == null ? 'Sem dados' : '$recentEvents',
            ),
            _MetricCard(label: 'Aceitos', value: '${health.events.accepted}'),
            _MetricCard(
              label: 'Rejeitados',
              value: '${health.events.rejected}',
            ),
            _MetricCard(
              label: 'Conflitos OPEN',
              value: '${health.openConflictsCount}',
              danger: health.openConflictsCount > 0,
            ),
            _MetricCard(
              label: 'Historico RESOLVED/IGNORED',
              value: historyConflicts < 0 ? 'Sem dados' : '$historyConflicts',
            ),
            _MetricCard(
              label: 'Incidentes recentes',
              value: recentIncidents == null ? 'Sem dados' : '$recentIncidents',
            ),
            _MetricCard(
              label: 'Dispositivos MOBILE_APP',
              value: mobileDevices == null
                  ? '${health.devices.total}'
                  : '$mobileDevices',
            ),
          ],
        ),
        const SizedBox(height: 16),
        _DetailGrid(
          rows: {
            'Ultimo sync': AdminFormatters.formatDateTime(health.lastSyncAt),
            'Ultimo materializado': AdminFormatters.formatDateTime(
              health.lastMaterializedAt,
            ),
            'Versao servidor': health.currentServerVersion,
            'Snapshot server-first': health.serverFirstSnapshotVersion,
            'Ultimo incidente': health.lastIncident?.message ?? 'Sem dados',
          },
        ),
        const SizedBox(height: 16),
        const _RemoteActionsNotice(),
      ],
    );
  }
}

class _EventsTab extends StatelessWidget {
  const _EventsTab({
    required this.eventsAsync,
    required this.onPrevious,
    required this.onNext,
  });

  final AsyncValue<AdminPaginatedResult<AdminSyncEventDiagnostic>> eventsAsync;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return eventsAsync.when(
      data: (result) {
        if (result.items.isEmpty) {
          return const _EmptyState(message: 'Nenhum evento encontrado.');
        }
        return ListView(
          padding: const EdgeInsets.only(top: 16),
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 20,
                horizontalMargin: 12,
                columns: const [
                  DataColumn(label: Text('Data/hora')),
                  DataColumn(label: Text('Entidade')),
                  DataColumn(label: Text('Operacao')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Rejection code')),
                  DataColumn(label: Text('Mensagem')),
                  DataColumn(label: Text('Dispositivo')),
                  DataColumn(label: Text('Detalhes')),
                ],
                rows: result.items
                    .map((event) {
                      return DataRow(
                        cells: [
                          DataCell(
                            Text(
                              AdminFormatters.formatDateTime(event.createdAt),
                            ),
                          ),
                          DataCell(Text(event.entity)),
                          DataCell(Text(event.operation)),
                          DataCell(
                            _StatusChip(label: _eventStatusLabel(event.status)),
                          ),
                          DataCell(Text(event.errorCode ?? 'Sem dados')),
                          DataCell(
                            SizedBox(
                              width: 180,
                              child: Text(event.errorMessage ?? 'Sem dados'),
                            ),
                          ),
                          DataCell(
                            Text(_maskId(event.device.clientInstanceId)),
                          ),
                          DataCell(
                            TextButton(
                              onPressed: () => _showEventDetail(context, event),
                              child: const Text('Detalhes'),
                            ),
                          ),
                        ],
                      );
                    })
                    .toList(growable: false),
              ),
            ),
            _PaginationBar(
              pagination: result.pagination,
              label: 'eventos',
              onPrevious: onPrevious,
              onNext: onNext,
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _InlineError(error: error),
    );
  }
}

class _ConflictsTab extends StatelessWidget {
  const _ConflictsTab({
    required this.openConflictsAsync,
    required this.historyConflictsAsync,
    required this.onOpenPrevious,
    required this.onOpenNext,
    required this.onHistoryPrevious,
    required this.onHistoryNext,
  });

  final AsyncValue<AdminPaginatedResult<AdminSyncConflictDiagnostic>>
  openConflictsAsync;
  final AsyncValue<AdminPaginatedResult<AdminSyncConflictDiagnostic>>
  historyConflictsAsync;
  final VoidCallback? onOpenPrevious;
  final VoidCallback? onOpenNext;
  final VoidCallback? onHistoryPrevious;
  final VoidCallback? onHistoryNext;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(top: 16),
      children: [
        Text(
          'Ativos: OPEN',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        openConflictsAsync.when(
          data: (result) {
            final active = result.items.where(_isOpenConflict).toList();
            if (active.isEmpty) {
              return const _EmptyState(message: 'Nenhum conflito OPEN.');
            }
            return Column(
              children: [
                _ConflictTable(conflicts: active),
                _PaginationBar(
                  pagination: result.pagination,
                  label: 'conflitos ativos',
                  onPrevious: onOpenPrevious,
                  onNext: onOpenNext,
                ),
              ],
            );
          },
          loading: () => const LinearProgressIndicator(),
          error: (error, _) => _InlineError(error: error),
        ),
        const SizedBox(height: 20),
        Text(
          'Historico: RESOLVED e IGNORED',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        historyConflictsAsync.when(
          data: (result) {
            final history = result.items
                .where((conflict) => !_isOpenConflict(conflict))
                .toList();
            if (history.isEmpty) {
              return const _EmptyState(message: 'Nenhum historico retornado.');
            }
            return Column(
              children: [
                _ConflictTable(conflicts: history),
                _PaginationBar(
                  pagination: result.pagination,
                  label: 'conflitos historicos',
                  onPrevious: onHistoryPrevious,
                  onNext: onHistoryNext,
                ),
              ],
            );
          },
          loading: () => const LinearProgressIndicator(),
          error: (error, _) => _InlineError(error: error),
        ),
      ],
    );
  }
}

class _ConflictTable extends StatelessWidget {
  const _ConflictTable({required this.conflicts});

  final List<AdminSyncConflictDiagnostic> conflicts;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Entidade')),
          DataColumn(label: Text('Codigo')),
          DataColumn(label: Text('Mensagem')),
          DataColumn(label: Text('Criado em')),
          DataColumn(label: Text('Atualizado em')),
          DataColumn(label: Text('Evento relacionado')),
          DataColumn(label: Text('Detalhes')),
        ],
        rows: conflicts
            .map((conflict) {
              return DataRow(
                cells: [
                  DataCell(
                    _StatusChip(label: _conflictStatusLabel(conflict.status)),
                  ),
                  DataCell(Text(conflict.entity)),
                  DataCell(Text(conflict.code)),
                  DataCell(SizedBox(width: 260, child: Text(conflict.message))),
                  DataCell(
                    Text(AdminFormatters.formatDateTime(conflict.createdAt)),
                  ),
                  const DataCell(Text('Nao disponivel nesta versao')),
                  DataCell(Text(conflict.event.eventId)),
                  DataCell(
                    TextButton(
                      onPressed: () => _showConflictDetail(context, conflict),
                      child: const Text('Detalhes'),
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

class _IncidentsTab extends StatelessWidget {
  const _IncidentsTab({
    required this.incidentsAsync,
    required this.onPrevious,
    required this.onNext,
  });

  final AsyncValue<AdminPaginatedResult<AdminSyncIncidentDiagnostic>>
  incidentsAsync;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return incidentsAsync.when(
      data: (result) {
        if (result.items.isEmpty) {
          return const _EmptyState(message: 'Nenhum incidente encontrado.');
        }
        return ListView(
          padding: const EdgeInsets.only(top: 16),
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Severidade')),
                  DataColumn(label: Text('Codigo')),
                  DataColumn(label: Text('Mensagem')),
                  DataColumn(label: Text('Entidade')),
                  DataColumn(label: Text('Criado em')),
                  DataColumn(label: Text('Atualizado em')),
                  DataColumn(label: Text('Evento/conflito')),
                  DataColumn(label: Text('Detalhes')),
                ],
                rows: result.items
                    .map((incident) {
                      return DataRow(
                        cells: [
                          const DataCell(Text('Registrado')),
                          DataCell(
                            _StatusChip(label: incident.severity.toUpperCase()),
                          ),
                          DataCell(Text(incident.code)),
                          DataCell(
                            SizedBox(width: 260, child: Text(incident.message)),
                          ),
                          DataCell(Text(incident.event?.entity ?? 'Sem dados')),
                          DataCell(
                            Text(
                              AdminFormatters.formatDateTime(
                                incident.createdAt,
                              ),
                            ),
                          ),
                          const DataCell(Text('Nao disponivel nesta versao')),
                          DataCell(
                            Text(incident.event?.eventId ?? 'Sem dados'),
                          ),
                          DataCell(
                            TextButton(
                              onPressed: () =>
                                  _showIncidentDetail(context, incident),
                              child: const Text('Detalhes'),
                            ),
                          ),
                        ],
                      );
                    })
                    .toList(growable: false),
              ),
            ),
            _PaginationBar(
              pagination: result.pagination,
              label: 'incidentes',
              onPrevious: onPrevious,
              onNext: onNext,
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _InlineError(error: error),
    );
  }
}

class _DevicesTab extends StatelessWidget {
  const _DevicesTab({
    required this.companyId,
    required this.devicesAsync,
    required this.companyAsync,
  });

  final String companyId;
  final AsyncValue<List<AdminSyncSupportDevice>> devicesAsync;
  final AsyncValue<AdminCompanyDetail> companyAsync;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(top: 16),
      children: [
        const _RemoteActionsNotice(),
        const SizedBox(height: 12),
        devicesAsync.when(
          data: (devices) {
            final sessions = companyAsync.value?.sessions ?? const [];
            final rows = <_DeviceRow>[
              ...devices.map(_DeviceRow.fromSupportDevice),
              ...sessions
                  .where(
                    (session) =>
                        session.clientType.toUpperCase() != 'MOBILE_APP',
                  )
                  .map(_DeviceRow.fromSession),
            ];
            if (rows.isEmpty) {
              return const _EmptyState(
                message: 'Nenhum dispositivo retornado.',
              );
            }
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                showCheckboxColumn: false,
                columns: const [
                  DataColumn(label: Text('Nome/label')),
                  DataColumn(label: Text('Tipo')),
                  DataColumn(label: Text('Usuario')),
                  DataColumn(label: Text('Ultimo diagnostico')),
                  DataColumn(label: Text('Pendentes locais')),
                  DataColumn(label: Text('Falhas locais')),
                  DataColumn(label: Text('Conflitos OPEN')),
                  DataColumn(label: Text('Ultimo erro local')),
                  DataColumn(label: Text('App version')),
                  DataColumn(label: Text('Platform')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Acoes')),
                ],
                rows: rows
                    .map((row) {
                      return DataRow(
                        onSelectChanged: (_) => _showDeviceDetail(
                          context,
                          companyId: companyId,
                          row: row,
                        ),
                        cells: [
                          DataCell(Text(row.label)),
                          DataCell(Text(row.clientType)),
                          DataCell(Text(row.user)),
                          DataCell(
                            Text(
                              row.diagnostic == null
                                  ? 'Nao definido'
                                  : AdminFormatters.formatDateTime(
                                      row.diagnostic?.reportedAt,
                                    ),
                            ),
                          ),
                          DataCell(
                            Text('${row.diagnostic?.pendingCount ?? 0}'),
                          ),
                          DataCell(Text('${row.diagnostic?.failedCount ?? 0}')),
                          DataCell(
                            Text('${row.diagnostic?.openConflictCount ?? 0}'),
                          ),
                          DataCell(
                            SizedBox(
                              width: 220,
                              child: Text(
                                row.diagnostic?.lastLocalError ?? 'Sem dados',
                              ),
                            ),
                          ),
                          DataCell(Text(row.appVersion ?? 'Sem dados')),
                          DataCell(Text(row.platform ?? 'Sem dados')),
                          DataCell(_StatusChip(label: row.status)),
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextButton(
                                  onPressed: () => _showDeviceDetail(
                                    context,
                                    companyId: companyId,
                                    row: row,
                                  ),
                                  child: const Text('Detalhes'),
                                ),
                                const SizedBox(width: 8),
                                FilledButton.tonal(
                                  onPressed: row.isSupportDevice
                                      ? () => _showDeviceDetail(
                                          context,
                                          companyId: companyId,
                                          row: row,
                                        )
                                      : null,
                                  child: const Text('Suporte'),
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
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _InlineError(error: error),
        ),
      ],
    );
  }
}

class _AuditTab extends StatelessWidget {
  const _AuditTab();

  @override
  Widget build(BuildContext context) {
    return const _EmptyState(
      message: 'Historico de acoes administrativas de sync sera exibido aqui.',
    );
  }
}

class _DeviceRow {
  const _DeviceRow({
    required this.id,
    required this.label,
    required this.clientType,
    required this.user,
    required this.clientInstanceId,
    required this.platform,
    required this.appVersion,
    required this.lastSeenAt,
    required this.status,
    required this.diagnostic,
    required this.isSupportDevice,
  });

  final String id;
  final String label;
  final String clientType;
  final String user;
  final String clientInstanceId;
  final String? platform;
  final String? appVersion;
  final DateTime? lastSeenAt;
  final String status;
  final AdminSyncSupportDiagnosticSummary? diagnostic;
  final bool isSupportDevice;

  factory _DeviceRow.fromSupportDevice(AdminSyncSupportDevice device) {
    return _DeviceRow(
      id: device.id,
      label: device.title,
      clientType: 'MOBILE_APP',
      user: device.user?.name ?? 'Sem usuario',
      clientInstanceId: device.clientInstanceId,
      platform: device.platform,
      appVersion: device.appVersion,
      lastSeenAt: device.lastSeenAt,
      status: _deviceStatusLabel(device),
      diagnostic: device.diagnostic,
      isSupportDevice: true,
    );
  }

  factory _DeviceRow.fromSession(AdminDeviceSession session) {
    return _DeviceRow(
      id: session.id,
      label: session.deviceLabel ?? _maskId(session.id),
      clientType: session.clientType.toUpperCase(),
      user: session.userName,
      clientInstanceId: session.clientInstanceId,
      platform: session.platform,
      appVersion: session.appVersion,
      lastSeenAt: session.lastSeenAt,
      status: session.status,
      diagnostic: null,
      isSupportDevice: false,
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    this.danger = false,
  });

  final String label;
  final String value;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 220,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: danger ? scheme.error : scheme.onSurface,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(label),
            ],
          ),
        ),
      ),
    );
  }
}

class _RemoteActionsNotice extends StatelessWidget {
  const _RemoteActionsNotice();

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
        _remoteActionsNotice,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: scheme.onSecondaryContainer,
          fontWeight: FontWeight.w800,
        ),
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
            );
          })
          .toList(growable: false),
    );
  }
}

class _SupportCommandsPanel extends ConsumerWidget {
  const _SupportCommandsPanel({
    required this.companyId,
    required this.deviceId,
    required this.commands,
  });

  final String companyId;
  final String deviceId;
  final List<AdminSyncSupportCommand> commands;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Comandos de suporte',
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _supportCommands
              .map(
                (option) => FilledButton.tonal(
                  onPressed: () => _showSupportCommandDialog(
                    context,
                    companyId: companyId,
                    deviceId: deviceId,
                    option: option,
                  ),
                  child: Text(option.label),
                ),
              )
              .toList(growable: false),
        ),
        const SizedBox(height: 12),
        Text(
          'Historico de comandos',
          style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        if (commands.isEmpty)
          const _EmptyState(message: 'Nenhum comando enviado para este device.')
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Comando')),
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('Solicitado em')),
                DataColumn(label: Text('Retirado em')),
                DataColumn(label: Text('Concluido em')),
                DataColumn(label: Text('Expira em')),
                DataColumn(label: Text('Motivo')),
                DataColumn(label: Text('Nota')),
                DataColumn(label: Text('Resultado/erro')),
              ],
              rows: commands
                  .map(
                    (command) => DataRow(
                      cells: [
                        DataCell(Text(command.command)),
                        DataCell(_StatusChip(label: command.status)),
                        DataCell(
                          Text(
                            AdminFormatters.formatDateTime(command.requestedAt),
                          ),
                        ),
                        DataCell(
                          Text(
                            AdminFormatters.formatDateTime(command.pickedUpAt),
                          ),
                        ),
                        DataCell(
                          Text(
                            AdminFormatters.formatDateTime(command.completedAt),
                          ),
                        ),
                        DataCell(
                          Text(
                            AdminFormatters.formatDateTime(command.expiresAt),
                          ),
                        ),
                        DataCell(
                          SizedBox(width: 180, child: Text(command.reason)),
                        ),
                        DataCell(
                          SizedBox(
                            width: 180,
                            child: Text(_formatCommandNote(command)),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: 240,
                            child: Text(
                              command.errorMessage ??
                                  _formatSafeDetails(command.result),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
      ],
    );
  }
}

void _showSupportCommandDialog(
  BuildContext context, {
  required String companyId,
  required String deviceId,
  required _SupportCommandOption option,
}) {
  showDialog<void>(
    context: context,
    builder: (_) => _SupportCommandDialog(
      companyId: companyId,
      deviceId: deviceId,
      option: option,
    ),
  );
}

class _SupportCommandDialog extends ConsumerStatefulWidget {
  const _SupportCommandDialog({
    required this.companyId,
    required this.deviceId,
    required this.option,
  });

  final String companyId;
  final String deviceId;
  final _SupportCommandOption option;

  @override
  ConsumerState<_SupportCommandDialog> createState() =>
      _SupportCommandDialogState();
}

class _SupportCommandDialogState extends ConsumerState<_SupportCommandDialog> {
  final _reasonController = TextEditingController();
  final _noteController = TextEditingController();
  final _confirmationController = TextEditingController();
  AdminSyncSupportDryRunResult? _dryRun;
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _reasonController.dispose();
    _noteController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dryRun = _dryRun;
    final expected =
        dryRun?.expectedConfirmationText ??
        widget.option.expectedConfirmationText;
    final canConfirm =
        dryRun?.allowed == true &&
        _reasonController.text.trim().isNotEmpty &&
        _confirmationController.text.trim() == expected &&
        !_loading;
    return AlertDialog(
      title: Text(widget.option.label),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Comando: ${widget.option.command}'),
              const SizedBox(height: 12),
              TextField(
                controller: _reasonController,
                onChanged: (_) => setState(() {}),
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Motivo obrigatorio',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _noteController,
                minLines: 1,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Nota opcional',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: _loading ? null : _runDryRun,
                icon: const Icon(Icons.fact_check_rounded),
                label: const Text('Executar dry-run'),
              ),
              if (dryRun != null) ...[
                const SizedBox(height: 16),
                _DryRunSummary(result: dryRun),
                const SizedBox(height: 12),
                TextField(
                  controller: _confirmationController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Texto de confirmacao',
                    helperText: 'Digite $expected para liberar a confirmacao.',
                    border: const OutlineInputBorder(),
                  ),
                ),
                if (_confirmationController.text.trim().isNotEmpty &&
                    _confirmationController.text.trim() != expected)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Digite $expected para liberar a confirmacao.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (_loading) const LinearProgressIndicator(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: canConfirm ? _createCommand : null,
          child: const Text('Enviar comando'),
        ),
      ],
    );
  }

  Future<void> _runDryRun() async {
    setState(() {
      _loading = true;
      _error = null;
      _dryRun = null;
      _confirmationController.clear();
    });
    try {
      final result = await ref
          .read(adminApiServiceProvider)
          .dryRunSyncSupportAction(
            companyId: widget.companyId,
            deviceId: widget.deviceId,
            command: widget.option.command,
            reason: _reasonController.text,
          );
      if (mounted) {
        setState(() => _dryRun = result);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = _safeError(error));
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _createCommand() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(adminApiServiceProvider)
          .createSyncSupportAction(
            companyId: widget.companyId,
            deviceId: widget.deviceId,
            command: widget.option.command,
            reason: _reasonController.text,
            confirmationText: _confirmationController.text,
            note: _noteController.text,
          );
      ref.invalidate(
        adminSyncSupportDeviceDetailProvider(
          AdminSyncCenterDetailKey(
            companyId: widget.companyId,
            targetId: widget.deviceId,
          ),
        ),
      );
      ref.invalidate(adminSyncSupportDevicesProvider(widget.companyId));
      ref.invalidate(adminCompanySyncHealthProvider(widget.companyId));
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(
          SnackBar(
            content: Text(result.message ?? 'Comando criado como PENDING.'),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = _safeError(error));
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }
}

class _DryRunSummary extends StatelessWidget {
  const _DryRunSummary({required this.result});

  final AdminSyncSupportDryRunResult result;

  @override
  Widget build(BuildContext context) {
    return _DetailGrid(
      rows: {
        'Dry-run': result.allowed ? 'Liberado' : 'Bloqueado',
        'Resumo': result.summary,
        'Confirmacao esperada': result.expectedConfirmationText,
        'Riscos': result.risks.isEmpty ? 'Sem dados' : result.risks.join('; '),
        'Bloqueios': result.blockers.isEmpty
            ? 'Sem bloqueios'
            : result.blockers.join('; '),
      },
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

class _InlineError extends StatelessWidget {
  const _InlineError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return _EmptyState(message: _safeError(error));
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

void _showEventDetail(BuildContext context, AdminSyncEventDiagnostic event) {
  _showDetails(
    context,
    title: 'Evento ${event.eventId}',
    rows: {
      'Status': _eventStatusLabel(event.status),
      'Rejection reason': event.errorMessage ?? 'Sem dados',
      'Rejection code': event.errorCode ?? 'Sem dados',
      'Payload preview':
          event.payloadSummary ?? 'Sem preview seguro disponivel',
      'Conflito relacionado': 'Nao disponivel nesta versao',
      'Incidente relacionado': 'Nao disponivel nesta versao',
    },
  );
}

void _showConflictDetail(
  BuildContext context,
  AdminSyncConflictDiagnostic conflict,
) {
  _showDetails(
    context,
    title: 'Conflito ${conflict.code}',
    rows: {
      'Status': _conflictStatusLabel(conflict.status),
      'Payload sanitizado':
          conflict.payloadSummary ?? 'Sem preview seguro disponivel',
      'Resolucao': conflict.resolutionSummary ?? 'Sem dados',
      'Resolved at': AdminFormatters.formatDateTime(conflict.resolvedAt),
      'Resolved by': conflict.resolvedBy?.id ?? 'Sem dados',
      'Evento relacionado': conflict.event.eventId,
    },
  );
}

void _showIncidentDetail(
  BuildContext context,
  AdminSyncIncidentDiagnostic incident,
) {
  _showDetails(
    context,
    title: 'Incidente ${incident.code}',
    rows: {
      'Diagnostico seguro':
          incident.detailsSummary ?? 'Sem diagnostico seguro disponivel',
      'Mensagem': incident.message,
      'Recomendacao': 'Nao disponivel nesta versao',
      'Evento relacionado': incident.event?.eventId ?? 'Sem dados',
    },
  );
}

void _showDeviceDetail(
  BuildContext context, {
  required String companyId,
  required _DeviceRow row,
}) {
  if (!row.isSupportDevice) {
    _showDetails(
      context,
      title: 'Dispositivo ${row.label}',
      rows: {
        'Tipo': row.clientType,
        'ID': _maskId(row.id),
        'Client instance': _maskId(row.clientInstanceId),
        'Usuario': row.user,
        'Status': row.status,
        'Diagnostico local do app':
            'Este dispositivo ainda nao reportou diagnostico local recente.',
        'Acoes remotas': _remoteActionsNotice,
      },
    );
    return;
  }

  showDialog<void>(
    context: context,
    builder: (context) {
      final key = AdminSyncCenterDetailKey(
        companyId: companyId,
        targetId: row.id,
      );
      return AlertDialog(
        title: Text('Dispositivo ${row.label}'),
        content: SizedBox(
          width: 760,
          child: Consumer(
            builder: (context, ref, _) {
              final detailAsync = ref.watch(
                adminSyncSupportDeviceDetailProvider(key),
              );
              return detailAsync.when(
                data: (detail) => SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _DetailGrid(
                        rows: _deviceDetailRows(row, detail.diagnostic),
                      ),
                      const SizedBox(height: 16),
                      _SupportCommandsPanel(
                        companyId: companyId,
                        deviceId: row.id,
                        commands: detail.commands,
                      ),
                    ],
                  ),
                ),
                loading: () => const Padding(
                  padding: EdgeInsets.all(20),
                  child: LinearProgressIndicator(),
                ),
                error: (error, _) => _InlineError(error: error),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fechar'),
          ),
        ],
      );
    },
  );
}

Map<String, String> _deviceDetailRows(
  _DeviceRow row,
  AdminSyncSupportDiagnostic? diagnostic,
) {
  if (diagnostic == null) {
    return {
      'Tipo': row.clientType,
      'ID': _maskId(row.id),
      'Client instance': _maskId(row.clientInstanceId),
      'Usuario': row.user,
      'App version': row.appVersion ?? 'Sem dados',
      'Platform': row.platform ?? 'Sem dados',
      'Diagnostico local do app':
          'Este dispositivo ainda nao reportou diagnostico local recente.',
      'Status do diagnostico':
          'Este dispositivo ainda nao reportou diagnostico local recente.',
      'Acoes remotas': _remoteActionsNotice,
    };
  }
  return {
    'Estado': _diagnosticState(diagnostic),
    'Pendentes locais': '${diagnostic.pendingCount}',
    'Falhas locais': '${diagnostic.failedCount}',
    'Conflitos OPEN': '${diagnostic.openConflictCount}',
    'Conflitos RESOLVED': '${diagnostic.resolvedConflictCount}',
    'Conflitos IGNORED': '${diagnostic.ignoredConflictCount}',
    'Ultimo erro local': diagnostic.lastLocalError ?? 'Sem dados',
    'Codigo do erro': diagnostic.lastLocalErrorCode ?? 'Sem dados',
    'Entidade do erro': diagnostic.lastLocalErrorEntity ?? 'Sem dados',
    'Ultimo push': AdminFormatters.formatDateTime(diagnostic.lastPushAt),
    'Ultimo pull': AdminFormatters.formatDateTime(diagnostic.lastPullAt),
    'Ultimo sync com sucesso': AdminFormatters.formatDateTime(
      diagnostic.lastSuccessfulSyncAt,
    ),
    'Reportado em': AdminFormatters.formatDateTime(diagnostic.reportedAt),
    'App version': diagnostic.appVersion ?? row.appVersion ?? 'Sem dados',
    'Platform': diagnostic.platform ?? row.platform ?? 'Sem dados',
    'Schema local': diagnostic.localSchemaVersion ?? 'Sem dados',
    'Detalhes seguros': _formatSafeDetails(diagnostic.safeDetails),
    'Acoes remotas': _remoteActionsNotice,
  };
}

void _showDetails(
  BuildContext context, {
  required String title,
  required Map<String, String> rows,
}) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(child: _DetailGrid(rows: rows)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fechar'),
        ),
      ],
    ),
  );
}

bool _isOpenConflict(AdminSyncConflictDiagnostic conflict) =>
    conflict.status.toLowerCase() == 'open';

String _deviceStatusLabel(AdminSyncSupportDevice device) {
  final diagnostic = device.diagnostic;
  if (diagnostic == null) {
    return 'Sem diagnostico';
  }
  if (diagnostic.failedCount > 0 && device.openConflictCount == 0) {
    return 'Falhas locais';
  }
  if (diagnostic.openConflictCount > 0) {
    return 'Conflitos locais';
  }
  if (_isDiagnosticStale(diagnostic.reportedAt)) {
    return 'Diagnostico desatualizado';
  }
  return 'Sem falhas locais';
}

String _diagnosticState(AdminSyncSupportDiagnostic diagnostic) {
  if (_isDiagnosticStale(diagnostic.reportedAt)) {
    return 'Diagnostico desatualizado.';
  }
  if (diagnostic.failedCount > 0 && diagnostic.openConflictCount == 0) {
    return 'Nuvem em dia no backend, mas app reporta falhas locais.';
  }
  if (diagnostic.failedCount == 0 && diagnostic.openConflictCount == 0) {
    return 'Sem falhas locais reportadas.';
  }
  return 'App reporta pendencias locais ativas.';
}

bool _isDiagnosticStale(DateTime? reportedAt) {
  if (reportedAt == null) {
    return true;
  }
  return DateTime.now().difference(reportedAt) > const Duration(hours: 24);
}

String _formatSafeDetails(Map<String, dynamic> details) {
  if (details.isEmpty) {
    return 'Sem dados';
  }
  final text = details.entries
      .map((entry) => '${entry.key}: ${entry.value}')
      .join(', ');
  return text.length <= 500 ? text : '${text.substring(0, 500)}...';
}

String _formatCommandNote(AdminSyncSupportCommand command) {
  final note = command.payload['note'];
  if (note is! String || note.trim().isEmpty) {
    return 'Sem nota';
  }
  final trimmed = note.trim();
  return trimmed.length <= 240 ? trimmed : '${trimmed.substring(0, 240)}...';
}

String _maskId(String value) {
  final trimmed = value.trim();
  if (trimmed.length <= 8) {
    return trimmed;
  }
  return '${trimmed.substring(0, 4)}...${trimmed.substring(trimmed.length - 4)}';
}

String _syncStatusLabel(String status) {
  switch (status.toLowerCase()) {
    case 'healthy':
      return 'Saudavel';
    case 'attention':
    case 'warning':
      return 'Atencao';
    case 'critical':
      return 'Critico';
    case 'disabled':
      return 'Sync desativada';
    default:
      return status;
  }
}

String _eventStatusLabel(String status) {
  switch (status.toLowerCase()) {
    case 'accepted':
      return 'Aceito';
    case 'rejected':
      return 'Rejeitado';
    case 'conflict':
      return 'Com conflito';
    case 'failed':
      return 'Falhou';
    case 'pending':
      return 'Pendente';
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
