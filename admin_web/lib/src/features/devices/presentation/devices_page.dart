import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/admin_providers.dart';
import '../../../core/models/admin_models.dart';
import '../../../core/utils/admin_formatters.dart';
import '../../../core/widgets/admin_surface.dart';

class DevicesPage extends ConsumerStatefulWidget {
  const DevicesPage({super.key, this.companyId, this.showSessions = true});

  final String? companyId;
  final bool showSessions;

  @override
  ConsumerState<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends ConsumerState<DevicesPage> {
  late final TextEditingController _searchController;
  int _page = 1;
  String _clientType = 'all';
  bool _attentionOnly = false;

  AdminDevicesQuery _buildQuery() {
    return AdminDevicesQuery(
      page: _page,
      pageSize: 20,
      companyId: widget.companyId,
      search: _searchController.text,
      clientType: _clientType,
      attention: _attentionOnly ? true : null,
    );
  }

  void _refresh(AdminDevicesQuery query) {
    ref.invalidate(adminDevicesProvider(query));
    if (widget.companyId != null && widget.showSessions) {
      ref.invalidate(adminCompanySessionsProvider(widget.companyId!));
    }
  }

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
    final query = _buildQuery();
    final devicesAsync = ref.watch(adminDevicesProvider(query));
    final sessionsAsync = widget.companyId == null || !widget.showSessions
        ? const AsyncValue<List<AdminDeviceSession>>.data(<AdminDeviceSession>[])
        : ref.watch(adminCompanySessionsProvider(widget.companyId!));

    return devicesAsync.when(
      data: (result) => SingleChildScrollView(
        child: AdminSurface(
          title: widget.companyId == null
              ? 'Dispositivos e sessoes'
              : 'Dispositivos e sessoes da empresa',
          subtitle:
              'Visao read-only de aparelhos, sessoes recentes e diagnostico local. Revogar sessao e forcar logout ficam para fase posterior.',
          trailing: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (widget.companyId != null)
                OutlinedButton.icon(
                  onPressed: () =>
                      context.go('/audit?companyId=${widget.companyId}&category=session'),
                  icon: const Icon(Icons.fact_check_rounded),
                  label: const Text('Ver auditoria filtrada'),
                ),
              OutlinedButton.icon(
                onPressed: () => _refresh(query),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Atualizar'),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _ReadOnlyNotice(),
              const SizedBox(height: 16),
              _DeviceMetrics(devices: result.items, total: result.pagination.total),
              const SizedBox(height: 16),
              _Filters(
                controller: _searchController,
                clientType: _clientType,
                attentionOnly: _attentionOnly,
                onClientTypeChanged: (value) =>
                    setState(() => _clientType = value),
                onAttentionChanged: (value) =>
                    setState(() => _attentionOnly = value),
                onSearch: () => setState(() => _page = 1),
              ),
              const SizedBox(height: 16),
              if (result.items.isEmpty)
                const _EmptyState(
                  message: 'Nenhum dispositivo encontrado para os filtros.',
                )
              else
                _DevicesTable(
                  devices: result.items,
                  onOpenCompany: (companyId) =>
                      context.go('/companies/$companyId/devices'),
                ),
              const SizedBox(height: 16),
              _Pagination(
                page: result.pagination.page,
                hasPrevious: result.pagination.hasPrevious,
                hasNext: result.pagination.hasNext,
                onPrevious: () => setState(() => _page -= 1),
                onNext: () => setState(() => _page += 1),
              ),
              if (widget.companyId != null && widget.showSessions) ...[
                const SizedBox(height: 24),
                sessionsAsync.when(
                  data: (sessions) => _SessionsSection(sessions: sessions),
                  loading: () => const LinearProgressIndicator(),
                  error: (error, _) => _InlineError(error: error),
                ),
              ],
            ],
          ),
        ),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => AdminSurface(
        title: 'Nao foi possivel carregar dispositivos',
        subtitle: _safeError(error),
        child: FilledButton.tonalIcon(
          onPressed: () => _refresh(query),
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Tentar novamente'),
        ),
      ),
    );
  }
}

class _ReadOnlyNotice extends StatelessWidget {
  const _ReadOnlyNotice();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Padding(
        padding: EdgeInsets.all(12),
        child: Text(
          'Somente leitura. Acoes de revogar sessao e forcar logout serao implementadas em fase posterior com dry-run, confirmacao explicita e auditoria.',
        ),
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({
    required this.controller,
    required this.clientType,
    required this.attentionOnly,
    required this.onClientTypeChanged,
    required this.onAttentionChanged,
    required this.onSearch,
  });

  final TextEditingController controller;
  final String clientType;
  final bool attentionOnly;
  final ValueChanged<String> onClientTypeChanged;
  final ValueChanged<bool> onAttentionChanged;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 300,
          child: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Buscar empresa, usuario ou dispositivo',
              prefixIcon: Icon(Icons.search_rounded),
            ),
            onSubmitted: (_) => onSearch(),
          ),
        ),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'all', label: Text('Todos')),
            ButtonSegment(value: 'MOBILE_APP', label: Text('MOBILE_APP')),
            ButtonSegment(value: 'ADMIN_WEB', label: Text('ADMIN_WEB')),
            ButtonSegment(value: 'OWNER_WEB', label: Text('OWNER_WEB')),
            ButtonSegment(value: 'UNKNOWN', label: Text('unknown')),
          ],
          selected: {clientType},
          onSelectionChanged: (values) {
            onClientTypeChanged(values.first);
            onSearch();
          },
        ),
        FilterChip(
          selected: attentionOnly,
          onSelected: (value) {
            onAttentionChanged(value);
            onSearch();
          },
          label: const Text('Com falha local'),
        ),
        FilledButton.tonalIcon(
          onPressed: onSearch,
          icon: const Icon(Icons.search_rounded),
          label: const Text('Aplicar'),
        ),
      ],
    );
  }
}

class _DevicesTable extends StatelessWidget {
  const _DevicesTable({required this.devices, required this.onOpenCompany});

  final List<AdminDeviceInventoryItem> devices;
  final ValueChanged<String> onOpenCompany;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Empresa')),
          DataColumn(label: Text('Dispositivo')),
          DataColumn(label: Text('Usuario')),
          DataColumn(label: Text('Tipo')),
          DataColumn(label: Text('Plataforma')),
          DataColumn(label: Text('Versao')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Ultimo acesso')),
          DataColumn(label: Text('Diagnostico')),
          DataColumn(label: Text('Acao')),
        ],
        rows: devices
            .map(
              (device) => DataRow(
                cells: [
                  DataCell(Text(device.companyName)),
                  DataCell(Text(device.displayName)),
                  DataCell(Text(device.userName)),
                  DataCell(Text(_clientTypeLabel(device.clientType))),
                  DataCell(Text(device.platform ?? 'Nao disponivel')),
                  DataCell(Text(device.appVersion ?? 'Nao disponivel')),
                  DataCell(Text(_deviceStatusLabel(device.status))),
                  DataCell(
                    Text(AdminFormatters.formatDateTime(device.lastSeenAt)),
                  ),
                  DataCell(_DiagnosticSummary(device: device)),
                  DataCell(
                    TextButton.icon(
                      onPressed: () => _showDeviceDetail(context, device),
                      icon: const Icon(Icons.info_outline_rounded),
                      label: const Text('Detalhes'),
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

class _DeviceMetrics extends StatelessWidget {
  const _DeviceMetrics({required this.devices, required this.total});

  final List<AdminDeviceInventoryItem> devices;
  final int total;

  @override
  Widget build(BuildContext context) {
    final mobile = devices
        .where((device) => device.clientType.toUpperCase() == 'MOBILE_APP')
        .length;
    final adminWeb = devices
        .where((device) => device.clientType.toUpperCase() == 'ADMIN_WEB')
        .length;
    final attention = devices.where((device) => device.hasLocalAttention).length;
    final sessions = devices.where((device) => device.session != null).length;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _MetricTile(label: 'Dispositivos', value: '$total'),
        _MetricTile(label: 'MOBILE_APP', value: '$mobile'),
        _MetricTile(label: 'ADMIN_WEB', value: '$adminWeb'),
        _MetricTile(label: 'Sessoes recentes', value: '$sessions'),
        _MetricTile(label: 'Com falha local', value: '$attention'),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 170,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }
}

class _DiagnosticSummary extends StatelessWidget {
  const _DiagnosticSummary({required this.device});

  final AdminDeviceInventoryItem device;

  @override
  Widget build(BuildContext context) {
    final diagnostic = device.diagnostic;
    if (diagnostic == null) {
      return const Text('Sem diagnostico');
    }
    return Text(
      'Pendentes ${diagnostic.pendingCount} / Falhas ${diagnostic.failedCount} / OPEN ${diagnostic.openConflictCount}',
    );
  }
}

class _SessionsSection extends StatelessWidget {
  const _SessionsSection({required this.sessions});

  final List<AdminDeviceSession> sessions;

  @override
  Widget build(BuildContext context) {
    if (sessions.isEmpty) {
      return const AdminSurface(
        title: 'Sessoes',
        child: _EmptyState(message: 'Nenhuma sessao registrada.'),
      );
    }
    return AdminSurface(
      title: 'Sessoes',
      subtitle: 'Sessao e autenticacao recente. Sem acao de revogacao nesta fase.',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Usuario')),
            DataColumn(label: Text('Dispositivo')),
            DataColumn(label: Text('Tipo')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Criada em')),
            DataColumn(label: Text('Ultimo uso')),
            DataColumn(label: Text('Expira em')),
          ],
          rows: sessions
              .map(
                (session) => DataRow(
                  cells: [
                    DataCell(Text(session.userName)),
                    DataCell(
                      Text(
                        session.deviceLabel ??
                            _maskIdentifier(session.clientInstanceId),
                      ),
                    ),
                    DataCell(Text(_clientTypeLabel(session.clientType))),
                    DataCell(Text(_sessionStatusLabel(session.status))),
                    DataCell(
                      Text(AdminFormatters.formatDateTime(session.createdAt)),
                    ),
                    DataCell(
                      Text(AdminFormatters.formatDateTime(session.lastSeenAt)),
                    ),
                    DataCell(
                      Text(
                        AdminFormatters.formatDateTime(
                          session.refreshTokenExpiresAt,
                        ),
                      ),
                    ),
                  ],
                ),
              )
              .toList(growable: false),
        ),
      ),
    );
  }
}

class _Pagination extends StatelessWidget {
  const _Pagination({
    required this.page,
    required this.hasPrevious,
    required this.hasNext,
    required this.onPrevious,
    required this.onNext,
  });

  final int page;
  final bool hasPrevious;
  final bool hasNext;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton.icon(
          onPressed: hasPrevious ? onPrevious : null,
          icon: const Icon(Icons.chevron_left_rounded),
          label: const Text('Anterior'),
        ),
        Text('Pagina $page'),
        OutlinedButton.icon(
          onPressed: hasNext ? onNext : null,
          icon: const Icon(Icons.chevron_right_rounded),
          label: const Text('Proxima'),
        ),
      ],
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Text('Sessoes indisponiveis: ${_safeError(error)}');
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

void _showDeviceDetail(BuildContext context, AdminDeviceInventoryItem device) {
  showDialog<void>(
    context: context,
    builder: (context) {
      final diagnostic = device.diagnostic;
      final session = device.session;
      return AlertDialog(
        title: Text(device.displayName),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _DetailLine('Empresa', device.companyName),
                _DetailLine('Usuario', '${device.userName} (${device.userEmail})'),
                _DetailLine('Device ID', device.maskedDeviceId),
                _DetailLine('Client instance', device.clientInstanceId),
                _DetailLine('Tipo', _clientTypeLabel(device.clientType)),
                _DetailLine('Plataforma', device.platform ?? 'Nao disponivel'),
                _DetailLine('Versao', device.appVersion ?? 'Nao disponivel'),
                _DetailLine('Status', _deviceStatusLabel(device.status)),
                _DetailLine(
                  'Ultimo acesso',
                  AdminFormatters.formatDateTime(device.lastSeenAt),
                ),
                const Divider(),
                Text(
                  'Diagnostico local',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (diagnostic == null)
                  const Text('Dispositivo ainda nao reportou diagnostico.')
                else ...[
                  _DetailLine('Pendentes locais', '${diagnostic.pendingCount}'),
                  _DetailLine('Falhas locais', '${diagnostic.failedCount}'),
                  _DetailLine('Conflitos OPEN', '${diagnostic.openConflictCount}'),
                  _DetailLine(
                    'Ultimo erro local',
                    diagnostic.lastLocalError ?? 'Sem erro reportado',
                  ),
                  _DetailLine(
                    'Reportado em',
                    AdminFormatters.formatDateTime(diagnostic.reportedAt),
                  ),
                ],
                const Divider(),
                Text('Sessao', style: Theme.of(context).textTheme.titleSmall),
                if (session == null)
                  const Text('Nenhuma sessao vinculada encontrada.')
                else ...[
                  _DetailLine('Sessao', session.id),
                  _DetailLine('Status', _sessionStatusLabel(session.status)),
                  _DetailLine(
                    'Expira em',
                    AdminFormatters.formatDateTime(session.expiresAt),
                  ),
                ],
                const SizedBox(height: 12),
                const Text(
                  'Acoes de revogar sessao e forcar logout serao implementadas em fase posterior com dry-run, confirmacao explicita e auditoria.',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fechar'),
          ),
          TextButton.icon(
            onPressed: () => context.go(
              '/audit?companyId=${device.companyId}&category=session',
            ),
            icon: const Icon(Icons.fact_check_rounded),
            label: const Text('Auditoria'),
          ),
        ],
      );
    },
  );
}

class _DetailLine extends StatelessWidget {
  const _DetailLine(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

String _clientTypeLabel(String value) {
  switch (value.toUpperCase()) {
    case 'MOBILE_APP':
      return 'MOBILE_APP';
    case 'ADMIN_WEB':
      return 'ADMIN_WEB';
    case 'OWNER_WEB':
      return 'OWNER_WEB';
    default:
      return 'unknown';
  }
}

String _deviceStatusLabel(String value) {
  switch (value.toLowerCase()) {
    case 'active':
      return 'Ativo';
    case 'pending':
      return 'Pendente';
    case 'blocked':
      return 'Bloqueado';
    case 'revoked':
      return 'Revogado';
    default:
      return 'Desconhecido';
  }
}

String _sessionStatusLabel(String value) {
  switch (value.toLowerCase()) {
    case 'active':
      return 'Ativa';
    case 'expired':
      return 'Expirada';
    case 'revoked':
      return 'Revogada';
    default:
      return 'Desconhecida';
  }
}

String _maskIdentifier(String value) {
  final normalized = value.trim();
  if (normalized.length <= 10) {
    return normalized;
  }
  return '${normalized.substring(0, 4)}...${normalized.substring(normalized.length - 4)}';
}

String _safeError(Object error) {
  final message = error.toString();
  if (message.contains('Exception:')) {
    return message.split('Exception:').last.trim();
  }
  return message;
}
