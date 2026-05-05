import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/admin_providers.dart';
import '../../../core/models/admin_models.dart';
import '../../../core/utils/admin_formatters.dart';
import '../../../core/widgets/admin_surface.dart';

class CompanySyncHealthTab extends ConsumerStatefulWidget {
  const CompanySyncHealthTab({super.key, required this.companyId});

  final String companyId;

  @override
  ConsumerState<CompanySyncHealthTab> createState() =>
      _CompanySyncHealthTabState();
}

class _CompanySyncHealthTabState extends ConsumerState<CompanySyncHealthTab> {
  late final TextEditingController _eventDeviceController;
  late final TextEditingController _eventEntityController;
  late final TextEditingController _eventFeatureController;
  late final TextEditingController _eventFromController;
  late final TextEditingController _eventToController;
  late final TextEditingController _incidentSeverityController;
  late final TextEditingController _incidentFromController;
  late final TextEditingController _incidentToController;

  String? _eventStatus;
  String? _conflictStatus;
  DateTime? _eventFrom;
  DateTime? _eventTo;
  DateTime? _incidentFrom;
  DateTime? _incidentTo;
  int _eventPage = 1;
  int _eventLimit = 20;
  int _conflictPage = 1;
  int _incidentPage = 1;

  @override
  void initState() {
    super.initState();
    _eventDeviceController = TextEditingController();
    _eventEntityController = TextEditingController();
    _eventFeatureController = TextEditingController();
    _eventFromController = TextEditingController();
    _eventToController = TextEditingController();
    _incidentSeverityController = TextEditingController();
    _incidentFromController = TextEditingController();
    _incidentToController = TextEditingController();
  }

  @override
  void dispose() {
    _eventDeviceController.dispose();
    _eventEntityController.dispose();
    _eventFeatureController.dispose();
    _eventFromController.dispose();
    _eventToController.dispose();
    _incidentSeverityController.dispose();
    _incidentFromController.dispose();
    _incidentToController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final healthAsync = ref.watch(
      adminCompanySyncHealthProvider(widget.companyId),
    );
    final devicesAsync = ref.watch(
      adminCompanySyncDevicesProvider(widget.companyId),
    );
    final eventsQuery = AdminCompanySyncEventsQuery(
      companyId: widget.companyId,
      page: _eventPage,
      limit: _eventLimit,
      deviceId: _eventDeviceController.text,
      status: _eventStatus,
      entity: _eventEntityController.text,
      feature: _eventFeatureController.text,
      from: _eventFrom,
      to: _eventTo,
    );
    final conflictsQuery = AdminCompanySyncConflictsQuery(
      companyId: widget.companyId,
      page: _conflictPage,
      limit: 20,
      status: _conflictStatus,
    );
    final incidentsQuery = AdminCompanySyncIncidentsQuery(
      companyId: widget.companyId,
      page: _incidentPage,
      limit: 20,
      severity: _incidentSeverityController.text,
      from: _incidentFrom,
      to: _incidentTo,
    );
    final eventsAsync = ref.watch(adminCompanySyncEventsProvider(eventsQuery));
    final conflictsAsync = ref.watch(
      adminCompanySyncConflictsProvider(conflictsQuery),
    );
    final incidentsAsync = ref.watch(
      adminCompanySyncIncidentsProvider(incidentsQuery),
    );

    return healthAsync.when(
      data: (health) => RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(adminCompanySyncHealthProvider(widget.companyId));
          ref.invalidate(adminCompanySyncDevicesProvider(widget.companyId));
          ref.invalidate(adminCompanySyncEventsProvider(eventsQuery));
          ref.invalidate(adminCompanySyncConflictsProvider(conflictsQuery));
          ref.invalidate(adminCompanySyncIncidentsProvider(incidentsQuery));
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HealthCards(health: health),
              const SizedBox(height: 24),
              _DevicesSection(
                devicesAsync: devicesAsync,
                syncStates: health.deviceSyncStates,
              ),
              const SizedBox(height: 24),
              _EventsSection(
                eventsAsync: eventsAsync,
                status: _eventStatus,
                limit: _eventLimit,
                deviceController: _eventDeviceController,
                entityController: _eventEntityController,
                featureController: _eventFeatureController,
                fromController: _eventFromController,
                toController: _eventToController,
                onStatusChanged: (value) => setState(() {
                  _eventStatus = value;
                  _eventPage = 1;
                }),
                onLimitChanged: (value) => setState(() {
                  _eventLimit = value;
                  _eventPage = 1;
                }),
                onApply: _applyEventFilters,
                onClear: _clearEventFilters,
                onPrevious: eventsAsync.value?.pagination.hasPrevious == true
                    ? () => setState(() => _eventPage--)
                    : null,
                onNext: eventsAsync.value?.pagination.hasNext == true
                    ? () => setState(() => _eventPage++)
                    : null,
              ),
              const SizedBox(height: 24),
              _ConflictsSection(
                conflictsAsync: conflictsAsync,
                status: _conflictStatus,
                onStatusChanged: (value) => setState(() {
                  _conflictStatus = value;
                  _conflictPage = 1;
                }),
                onPrevious: conflictsAsync.value?.pagination.hasPrevious == true
                    ? () => setState(() => _conflictPage--)
                    : null,
                onNext: conflictsAsync.value?.pagination.hasNext == true
                    ? () => setState(() => _conflictPage++)
                    : null,
              ),
              const SizedBox(height: 24),
              _IncidentsSection(
                incidentsAsync: incidentsAsync,
                severityController: _incidentSeverityController,
                fromController: _incidentFromController,
                toController: _incidentToController,
                onApply: _applyIncidentFilters,
                onClear: _clearIncidentFilters,
                onPrevious: incidentsAsync.value?.pagination.hasPrevious == true
                    ? () => setState(() => _incidentPage--)
                    : null,
                onNext: incidentsAsync.value?.pagination.hasNext == true
                    ? () => setState(() => _incidentPage++)
                    : null,
              ),
            ],
          ),
        ),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => AdminSurface(
        title: 'Nao foi possivel carregar o Sync Health',
        subtitle: error.toString(),
        child: FilledButton.tonalIcon(
          onPressed: () =>
              ref.invalidate(adminCompanySyncHealthProvider(widget.companyId)),
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Tentar novamente'),
        ),
      ),
    );
  }

  void _applyEventFilters() {
    final parsed = _parseDateRange(
      fromController: _eventFromController,
      toController: _eventToController,
    );
    if (parsed == null) {
      return;
    }

    setState(() {
      _eventFrom = parsed.$1;
      _eventTo = parsed.$2;
      _eventPage = 1;
    });
  }

  void _clearEventFilters() {
    _eventDeviceController.clear();
    _eventEntityController.clear();
    _eventFeatureController.clear();
    _eventFromController.clear();
    _eventToController.clear();
    setState(() {
      _eventStatus = null;
      _eventFrom = null;
      _eventTo = null;
      _eventPage = 1;
      _eventLimit = 20;
    });
  }

  void _applyIncidentFilters() {
    final parsed = _parseDateRange(
      fromController: _incidentFromController,
      toController: _incidentToController,
    );
    if (parsed == null) {
      return;
    }

    setState(() {
      _incidentFrom = parsed.$1;
      _incidentTo = parsed.$2;
      _incidentPage = 1;
    });
  }

  void _clearIncidentFilters() {
    _incidentSeverityController.clear();
    _incidentFromController.clear();
    _incidentToController.clear();
    setState(() {
      _incidentFrom = null;
      _incidentTo = null;
      _incidentPage = 1;
    });
  }

  (DateTime?, DateTime?)? _parseDateRange({
    required TextEditingController fromController,
    required TextEditingController toController,
  }) {
    final from = _parseDateField(fromController.text);
    final to = _parseDateField(toController.text);
    if (from == _invalidDate || to == _invalidDate) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Use datas no formato AAAA-MM-DD ou ISO completo.'),
        ),
      );
      return null;
    }
    return (from, to);
  }
}

final DateTime _invalidDate = DateTime.fromMillisecondsSinceEpoch(0);

DateTime? _parseDateField(String rawValue) {
  final value = rawValue.trim();
  if (value.isEmpty) {
    return null;
  }
  return DateTime.tryParse(value) ??
      DateTime.tryParse('${value}T00:00:00') ??
      _invalidDate;
}

class _HealthCards extends StatelessWidget {
  const _HealthCards({required this.health});

  final AdminCompanySyncHealth health;

  @override
  Widget build(BuildContext context) {
    final cards = <_MetricCardData>[
      _MetricCardData(
        title: 'Status geral',
        value: _formatHealthStatus(health.status),
        icon: _healthIcon(health.status),
        color: _healthColor(context, health.status),
      ),
      _MetricCardData(
        title: 'Ultima sincronizacao',
        value: AdminFormatters.formatDateTime(health.lastSyncAt),
        icon: Icons.sync_rounded,
        color: Theme.of(context).colorScheme.primary,
      ),
      _MetricCardData(
        title: 'Eventos aceitos',
        value: '${health.events.accepted}',
        icon: Icons.cloud_done_rounded,
        color: Colors.green.shade700,
      ),
      _MetricCardData(
        title: 'Conflitos abertos',
        value: '${health.openConflictsCount}',
        icon: Icons.merge_type_rounded,
        color: Colors.orange.shade800,
      ),
      _MetricCardData(
        title: 'Eventos rejeitados',
        value: '${health.events.rejected}',
        icon: Icons.do_not_disturb_alt_rounded,
        color: Colors.amber.shade900,
      ),
      _MetricCardData(
        title: 'Eventos failed',
        value: '${health.events.failed}',
        icon: Icons.error_outline_rounded,
        color: Theme.of(context).colorScheme.error,
      ),
      _MetricCardData(
        title: 'Dispositivos ativos',
        value: '${health.devices.active}',
        icon: Icons.devices_rounded,
        color: Theme.of(context).colorScheme.secondary,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminSurface(
          title: 'Sync Health',
          subtitle:
              '${health.companyName} - versao servidor ${health.currentServerVersion}',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusChip(label: _formatHealthStatus(health.status)),
              _StatusChip(
                label: health.syncEnabled ? 'Sync habilitada' : 'Pendente',
              ),
              _StatusChip(
                label:
                    'Licenca ${AdminFormatters.formatLicenseStatus(health.license?.status)}',
              ),
              if (health.lastIncident != null)
                _StatusChip(
                  label:
                      'Ultimo incidente ${health.lastIncident!.severity.toUpperCase()}',
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final crossAxisCount = constraints.maxWidth >= 1300
                ? 4
                : constraints.maxWidth >= 900
                ? 3
                : constraints.maxWidth >= 620
                ? 2
                : 1;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: cards.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                childAspectRatio: 2.15,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
              ),
              itemBuilder: (context, index) {
                return _MetricCard(data: cards[index]);
              },
            );
          },
        ),
      ],
    );
  }
}

class _DevicesSection extends StatelessWidget {
  const _DevicesSection({required this.devicesAsync, required this.syncStates});

  final AsyncValue<List<AdminCompanySyncDevice>> devicesAsync;
  final List<AdminCompanyDeviceSyncState> syncStates;

  @override
  Widget build(BuildContext context) {
    return AdminSurface(
      title: 'Dispositivos',
      subtitle:
          'Aparelhos vinculados a esta empresa no contexto operacional da plataforma.',
      child: devicesAsync.when(
        data: (devices) {
          if (devices.isEmpty) {
            return const _EmptyState(message: 'Nenhum dispositivo registrado.');
          }
          final syncByDevice = {
            for (final state in syncStates) state.deviceId: state,
          };
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Dispositivo')),
                DataColumn(label: Text('Plataforma')),
                DataColumn(label: Text('Versao')),
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('Ultima sincronizacao')),
                DataColumn(label: Text('Ultimo acesso')),
                DataColumn(label: Text('Usuario')),
                DataColumn(label: Text('Client instance')),
              ],
              rows: devices
                  .map((device) {
                    final state = syncByDevice[device.id];
                    return DataRow(
                      cells: [
                        DataCell(Text(device.deviceLabel ?? 'Sem rotulo')),
                        DataCell(Text(device.platform ?? 'Nao informado')),
                        DataCell(Text(device.appVersion ?? 'Nao informado')),
                        DataCell(Text(_formatDeviceStatus(device.status))),
                        DataCell(
                          Text(
                            AdminFormatters.formatDateTime(state?.lastSyncAt),
                          ),
                        ),
                        DataCell(
                          Text(
                            AdminFormatters.formatDateTime(device.lastSeenAt),
                          ),
                        ),
                        DataCell(Text(device.userName)),
                        DataCell(SelectableText(device.clientInstanceId)),
                      ],
                    );
                  })
                  .toList(growable: false),
            ),
          );
        },
        loading: () => const _LoadingLine(),
        error: (error, _) => _ErrorLine(message: error.toString()),
      ),
    );
  }
}

class _EventsSection extends StatelessWidget {
  const _EventsSection({
    required this.eventsAsync,
    required this.status,
    required this.limit,
    required this.deviceController,
    required this.entityController,
    required this.featureController,
    required this.fromController,
    required this.toController,
    required this.onStatusChanged,
    required this.onLimitChanged,
    required this.onApply,
    required this.onClear,
    required this.onPrevious,
    required this.onNext,
  });

  final AsyncValue<AdminPaginatedResult<AdminSyncEventDiagnostic>> eventsAsync;
  final String? status;
  final int limit;
  final TextEditingController deviceController;
  final TextEditingController entityController;
  final TextEditingController featureController;
  final TextEditingController fromController;
  final TextEditingController toController;
  final ValueChanged<String?> onStatusChanged;
  final ValueChanged<int> onLimitChanged;
  final VoidCallback onApply;
  final VoidCallback onClear;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return AdminSurface(
      title: 'Ultimos eventos',
      subtitle:
          'Use os filtros para diagnosticar por dispositivo, status, entidade, feature ou periodo.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _EventFilters(
            status: status,
            limit: limit,
            deviceController: deviceController,
            entityController: entityController,
            featureController: featureController,
            fromController: fromController,
            toController: toController,
            onStatusChanged: onStatusChanged,
            onLimitChanged: onLimitChanged,
            onApply: onApply,
            onClear: onClear,
          ),
          const SizedBox(height: 18),
          eventsAsync.when(
            data: (result) {
              if (result.items.isEmpty) {
                return const _EmptyState(
                  message: 'Nenhum evento encontrado para os filtros atuais.',
                );
              }
              return Column(
                children: [
                  ...result.items.map(
                    (event) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _EventTile(event: event),
                    ),
                  ),
                  _PaginationBar(
                    pagination: result.pagination,
                    unitLabel: 'eventos',
                    onPrevious: onPrevious,
                    onNext: onNext,
                  ),
                ],
              );
            },
            loading: () => const _LoadingLine(),
            error: (error, _) => _ErrorLine(message: error.toString()),
          ),
        ],
      ),
    );
  }
}

class _ConflictsSection extends StatelessWidget {
  const _ConflictsSection({
    required this.conflictsAsync,
    required this.status,
    required this.onStatusChanged,
    required this.onPrevious,
    required this.onNext,
  });

  final AsyncValue<AdminPaginatedResult<AdminSyncConflictDiagnostic>>
  conflictsAsync;
  final String? status;
  final ValueChanged<String?> onStatusChanged;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return AdminSurface(
      title: 'Conflitos',
      subtitle: 'Conflitos abertos e resolvidos, sem acoes destrutivas.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 220,
            child: DropdownButtonFormField<String?>(
              initialValue: status,
              decoration: const InputDecoration(labelText: 'Status'),
              items: const [
                DropdownMenuItem<String?>(value: null, child: Text('Todos')),
                DropdownMenuItem<String?>(
                  value: 'open',
                  child: Text('Abertos'),
                ),
                DropdownMenuItem<String?>(
                  value: 'resolved',
                  child: Text('Resolvidos'),
                ),
                DropdownMenuItem<String?>(
                  value: 'ignored',
                  child: Text('Ignorados'),
                ),
              ],
              onChanged: onStatusChanged,
            ),
          ),
          const SizedBox(height: 18),
          conflictsAsync.when(
            data: (result) {
              if (result.items.isEmpty) {
                return const _EmptyState(
                  message: 'Nenhum conflito encontrado.',
                );
              }
              return Column(
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Status')),
                        DataColumn(label: Text('Entidade')),
                        DataColumn(label: Text('Mensagem')),
                        DataColumn(label: Text('Dispositivo')),
                        DataColumn(label: Text('Evento')),
                        DataColumn(label: Text('Criado em')),
                      ],
                      rows: result.items
                          .map((conflict) {
                            return DataRow(
                              cells: [
                                DataCell(
                                  Text(_formatConflictStatus(conflict.status)),
                                ),
                                DataCell(Text(conflict.entity)),
                                DataCell(
                                  SizedBox(
                                    width: 320,
                                    child: Text(
                                      conflict.message,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    conflict.device.deviceLabel ??
                                        conflict.device.clientInstanceId,
                                  ),
                                ),
                                DataCell(
                                  SelectableText(conflict.event.eventId),
                                ),
                                DataCell(
                                  Text(
                                    AdminFormatters.formatDateTime(
                                      conflict.createdAt,
                                    ),
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
                    unitLabel: 'conflitos',
                    onPrevious: onPrevious,
                    onNext: onNext,
                  ),
                ],
              );
            },
            loading: () => const _LoadingLine(),
            error: (error, _) => _ErrorLine(message: error.toString()),
          ),
        ],
      ),
    );
  }
}

class _IncidentsSection extends StatelessWidget {
  const _IncidentsSection({
    required this.incidentsAsync,
    required this.severityController,
    required this.fromController,
    required this.toController,
    required this.onApply,
    required this.onClear,
    required this.onPrevious,
    required this.onNext,
  });

  final AsyncValue<AdminPaginatedResult<AdminSyncIncidentDiagnostic>>
  incidentsAsync;
  final TextEditingController severityController;
  final TextEditingController fromController;
  final TextEditingController toController;
  final VoidCallback onApply;
  final VoidCallback onClear;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return AdminSurface(
      title: 'Incidentes',
      subtitle: 'Ocorrencias registradas por severidade e data.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 180,
                child: TextField(
                  controller: severityController,
                  decoration: const InputDecoration(
                    labelText: 'Severidade',
                    hintText: 'warn, error',
                  ),
                  onSubmitted: (_) => onApply(),
                ),
              ),
              _DateField(controller: fromController, label: 'De'),
              _DateField(controller: toController, label: 'Ate'),
              FilledButton.icon(
                onPressed: onApply,
                icon: const Icon(Icons.filter_alt_rounded),
                label: const Text('Aplicar'),
              ),
              TextButton(onPressed: onClear, child: const Text('Limpar')),
            ],
          ),
          const SizedBox(height: 18),
          incidentsAsync.when(
            data: (result) {
              if (result.items.isEmpty) {
                return const _EmptyState(
                  message: 'Nenhum incidente encontrado.',
                );
              }
              return Column(
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Severidade')),
                        DataColumn(label: Text('Codigo')),
                        DataColumn(label: Text('Mensagem')),
                        DataColumn(label: Text('Dispositivo')),
                        DataColumn(label: Text('Evento')),
                        DataColumn(label: Text('Criado em')),
                      ],
                      rows: result.items
                          .map((incident) {
                            return DataRow(
                              cells: [
                                DataCell(Text(incident.severity.toUpperCase())),
                                DataCell(Text(incident.code)),
                                DataCell(
                                  SizedBox(
                                    width: 320,
                                    child: Text(
                                      incident.message,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    incident.device?.deviceLabel ??
                                        incident.device?.clientInstanceId ??
                                        'Nao informado',
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    incident.event?.eventId ?? 'Nao informado',
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    AdminFormatters.formatDateTime(
                                      incident.createdAt,
                                    ),
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
                    unitLabel: 'incidentes',
                    onPrevious: onPrevious,
                    onNext: onNext,
                  ),
                ],
              );
            },
            loading: () => const _LoadingLine(),
            error: (error, _) => _ErrorLine(message: error.toString()),
          ),
        ],
      ),
    );
  }
}

class _EventFilters extends StatelessWidget {
  const _EventFilters({
    required this.status,
    required this.limit,
    required this.deviceController,
    required this.entityController,
    required this.featureController,
    required this.fromController,
    required this.toController,
    required this.onStatusChanged,
    required this.onLimitChanged,
    required this.onApply,
    required this.onClear,
  });

  final String? status;
  final int limit;
  final TextEditingController deviceController;
  final TextEditingController entityController;
  final TextEditingController featureController;
  final TextEditingController fromController;
  final TextEditingController toController;
  final ValueChanged<String?> onStatusChanged;
  final ValueChanged<int> onLimitChanged;
  final VoidCallback onApply;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 220,
          child: TextField(
            controller: deviceController,
            decoration: const InputDecoration(labelText: 'Device ID'),
            onSubmitted: (_) => onApply(),
          ),
        ),
        SizedBox(
          width: 160,
          child: DropdownButtonFormField<String?>(
            initialValue: status,
            decoration: const InputDecoration(labelText: 'Status'),
            items: const [
              DropdownMenuItem<String?>(value: null, child: Text('Todos')),
              DropdownMenuItem<String?>(
                value: 'accepted',
                child: Text('Sincronizado'),
              ),
              DropdownMenuItem<String?>(
                value: 'pending',
                child: Text('Pendente'),
              ),
              DropdownMenuItem<String?>(
                value: 'conflict',
                child: Text('Com conflito'),
              ),
              DropdownMenuItem<String?>(
                value: 'rejected',
                child: Text('Rejeitado'),
              ),
              DropdownMenuItem<String?>(
                value: 'failed',
                child: Text('Com erro'),
              ),
            ],
            onChanged: onStatusChanged,
          ),
        ),
        SizedBox(
          width: 160,
          child: TextField(
            controller: entityController,
            decoration: const InputDecoration(labelText: 'Entity'),
            onSubmitted: (_) => onApply(),
          ),
        ),
        SizedBox(
          width: 160,
          child: TextField(
            controller: featureController,
            decoration: const InputDecoration(labelText: 'Feature'),
            onSubmitted: (_) => onApply(),
          ),
        ),
        _DateField(controller: fromController, label: 'De'),
        _DateField(controller: toController, label: 'Ate'),
        SizedBox(
          width: 120,
          child: DropdownButtonFormField<int>(
            initialValue: limit,
            decoration: const InputDecoration(labelText: 'Limite'),
            items: const [
              DropdownMenuItem(value: 10, child: Text('10')),
              DropdownMenuItem(value: 20, child: Text('20')),
              DropdownMenuItem(value: 50, child: Text('50')),
              DropdownMenuItem(value: 100, child: Text('100')),
            ],
            onChanged: (value) {
              if (value != null) {
                onLimitChanged(value);
              }
            },
          ),
        ),
        FilledButton.icon(
          onPressed: onApply,
          icon: const Icon(Icons.filter_alt_rounded),
          label: const Text('Aplicar'),
        ),
        TextButton(onPressed: onClear, child: const Text('Limpar')),
      ],
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event});

  final AdminSyncEventDiagnostic event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _StatusChip(label: _formatEventStatus(event.status)),
            Text(
              '${event.feature} / ${event.entity}',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(event.operation),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            '${event.device.deviceLabel ?? event.device.clientInstanceId} - ${AdminFormatters.formatDateTime(event.createdAt)}',
          ),
        ),
        children: [
          _DetailsWrap(
            items: [
              _DetailItem('eventId', event.eventId),
              _DetailItem('entity', event.entity),
              _DetailItem('operation', event.operation),
              _DetailItem('errorCode', event.errorCode ?? 'Nao informado'),
              _DetailItem('serverVersion', event.serverVersion ?? '0'),
              _DetailItem(
                'payload resumido',
                event.payloadSummary ?? 'Nao informado',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({required this.controller, required this.label});

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: TextField(
        controller: controller,
        decoration: InputDecoration(labelText: label, hintText: 'AAAA-MM-DD'),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.data});

  final _MetricCardData data;

  @override
  Widget build(BuildContext context) {
    return AdminSurface(
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: data.color.withValues(alpha: 0.12),
            child: Icon(data.icon, color: data.color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.title,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  data.value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCardData {
  const _MetricCardData({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text(label));
  }
}

class _DetailsWrap extends StatelessWidget {
  const _DetailsWrap({required this.items});

  final List<_DetailItem> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: items
          .map((item) {
            return Container(
              width: 260,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SelectableText(item.value),
                ],
              ),
            );
          })
          .toList(growable: false),
    );
  }
}

class _DetailItem {
  const _DetailItem(this.label, this.value);

  final String label;
  final String value;
}

class _PaginationBar extends StatelessWidget {
  const _PaginationBar({
    required this.pagination,
    required this.unitLabel,
    required this.onPrevious,
    required this.onNext,
  });

  final AdminPaginationMeta pagination;
  final String unitLabel;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'Pagina ${pagination.page} - ${pagination.count} de ${pagination.total} $unitLabel',
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
      ),
    );
  }
}

class _LoadingLine extends StatelessWidget {
  const _LoadingLine();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 18),
      child: LinearProgressIndicator(),
    );
  }
}

class _ErrorLine extends StatelessWidget {
  const _ErrorLine({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: Theme.of(context).colorScheme.error,
      ),
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

String _formatHealthStatus(String status) {
  switch (status) {
    case 'synced':
      return 'Sincronizado';
    case 'conflict':
      return 'Com conflito';
    case 'error':
      return 'Com erro';
    default:
      return 'Pendente';
  }
}

String _formatEventStatus(String status) {
  switch (status) {
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

String _formatConflictStatus(String status) {
  switch (status) {
    case 'open':
      return 'Com conflito';
    case 'resolved':
      return 'Resolvido';
    case 'ignored':
      return 'Ignorado';
    default:
      return status;
  }
}

String _formatDeviceStatus(String status) {
  switch (status) {
    case 'active':
      return 'Ativo';
    case 'blocked':
      return 'Dispositivo bloqueado';
    case 'revoked':
      return 'Revogado';
    case 'pending':
      return 'Pendente';
    default:
      return status;
  }
}

IconData _healthIcon(String status) {
  switch (status) {
    case 'synced':
      return Icons.check_circle_outline_rounded;
    case 'conflict':
      return Icons.merge_type_rounded;
    case 'error':
      return Icons.error_outline_rounded;
    default:
      return Icons.schedule_rounded;
  }
}

Color _healthColor(BuildContext context, String status) {
  switch (status) {
    case 'synced':
      return Colors.green.shade700;
    case 'conflict':
      return Colors.orange.shade800;
    case 'error':
      return Theme.of(context).colorScheme.error;
    default:
      return Theme.of(context).colorScheme.secondary;
  }
}
