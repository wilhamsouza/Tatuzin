import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/admin_providers.dart';
import '../../../core/models/admin_models.dart';
import '../../../core/utils/admin_formatters.dart';
import '../../../core/utils/admin_safe_display.dart';
import '../../../core/widgets/admin_operational_status.dart';
import '../../../core/widgets/admin_surface.dart';

class CompanySessionsPage extends ConsumerWidget {
  const CompanySessionsPage({super.key, required this.companyId});

  final String companyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(adminCompanySessionsProvider(companyId));

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminSurface(
            title: 'Sessoes da empresa',
            subtitle:
                'Console read-only para diagnosticar autenticacao, app version e atividade recente sem executar comandos reais.',
            trailing: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => context.go('/companies/$companyId/support'),
                  icon: const Icon(Icons.support_agent_rounded),
                  label: const Text('Central de suporte'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () =>
                      ref.invalidate(adminCompanySessionsProvider(companyId)),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Atualizar'),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SessionsSafetyNotice(),
                const SizedBox(height: 16),
                _SessionShortcuts(companyId: companyId),
              ],
            ),
          ),
          const SizedBox(height: 24),
          sessionsAsync.when(
            data: (sessions) =>
                _SessionsContent(companyId: companyId, sessions: sessions),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => AdminSurface(
              title: 'Sessoes indisponiveis',
              subtitle: _safeError(error),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Nao foi possivel carregar as sessoes desta empresa. Nenhum dado sensivel foi exibido.',
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: () =>
                        ref.invalidate(adminCompanySessionsProvider(companyId)),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Tentar novamente'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionsSafetyNotice extends StatelessWidget {
  const _SessionsSafetyNotice();

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
          avatar: Icon(Icons.science_rounded, size: 18),
          label: Text('Dry-run disponivel na Central de suporte'),
        ),
        Chip(
          avatar: Icon(Icons.lock_clock_rounded, size: 18),
          label: Text('Execucao real indisponivel'),
        ),
        Chip(
          avatar: Icon(Icons.verified_user_outlined, size: 18),
          label: Text('Gate operacional em observacao'),
        ),
      ],
    );
  }
}

class _SessionShortcuts extends StatelessWidget {
  const _SessionShortcuts({required this.companyId});

  final String companyId;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        OutlinedButton.icon(
          onPressed: () => context.go('/companies/$companyId/devices'),
          icon: const Icon(Icons.devices_rounded),
          label: const Text('Dispositivos'),
        ),
        OutlinedButton.icon(
          onPressed: () => context.go('/companies/$companyId/users'),
          icon: const Icon(Icons.people_alt_rounded),
          label: const Text('Usuarios'),
        ),
        OutlinedButton.icon(
          onPressed: () =>
              context.go('/audit?companyId=$companyId&category=session'),
          icon: const Icon(Icons.fact_check_rounded),
          label: const Text('Auditoria'),
        ),
        OutlinedButton.icon(
          onPressed: () => context.go('/permissions'),
          icon: const Icon(Icons.admin_panel_settings_rounded),
          label: const Text('Permissoes'),
        ),
      ],
    );
  }
}

class _SessionsContent extends StatelessWidget {
  const _SessionsContent({required this.companyId, required this.sessions});

  final String companyId;
  final List<AdminDeviceSession> sessions;

  @override
  Widget build(BuildContext context) {
    if (sessions.isEmpty) {
      return const AdminSurface(
        title: 'Nenhuma sessao registrada',
        subtitle:
            'A empresa ainda nao possui sessoes recentes retornadas pelo backend.',
        child: _EmptyState(
          message:
              'Quando usuarios acessarem o app ou o Admin Web, as sessoes aparecerao aqui com usuario, dispositivo, status, datas e vinculo com empresa.',
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminSurface(
          title: 'Resumo operacional de sessoes',
          subtitle:
              'Indicadores derivados dos dados ja disponiveis no admin_web.',
          child: _SessionsSummary(sessions: sessions),
        ),
        const SizedBox(height: 24),
        AdminSurface(
          title: 'Lista de sessoes',
          subtitle:
              'IDs sao exibidos de forma segura; detalhes sensiveis permanecem omitidos.',
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('sessionId')),
                DataColumn(label: Text('Usuario')),
                DataColumn(label: Text('Dispositivo')),
                DataColumn(label: Text('Empresa')),
                DataColumn(label: Text('Cliente')),
                DataColumn(label: Text('Versao app')),
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('Criada em')),
                DataColumn(label: Text('Ultima atividade')),
                DataColumn(label: Text('Expira em')),
                DataColumn(label: Text('Revogada em')),
                DataColumn(label: Text('Atalhos')),
              ],
              rows: sessions
                  .map(
                    (session) => DataRow(
                      cells: [
                        DataCell(
                          SelectableText(maskAdminIdentifier(session.id)),
                        ),
                        DataCell(Text(_userLabel(session))),
                        DataCell(Text(_deviceLabel(session))),
                        DataCell(Text(_companyLabel(session, companyId))),
                        DataCell(Text(_clientTypeLabel(session.clientType))),
                        DataCell(Text(_fallback(session.appVersion))),
                        DataCell(
                          AdminOperationalStatus(
                            label: _sessionStatusLabel(session),
                            tone: _sessionTone(session),
                            compact: true,
                          ),
                        ),
                        DataCell(Text(_formatDate(session.createdAt))),
                        DataCell(Text(_formatDate(session.lastSeenAt))),
                        DataCell(
                          Text(_formatDate(session.refreshTokenExpiresAt)),
                        ),
                        DataCell(Text(_formatDate(session.revokedAt))),
                        DataCell(
                          Wrap(
                            spacing: 8,
                            children: [
                              TextButton(
                                onPressed: () => context.go(
                                  '/audit?companyId=$companyId&search=${Uri.encodeComponent(session.id)}',
                                ),
                                child: const Text('Auditoria'),
                              ),
                              TextButton(
                                onPressed: () =>
                                    context.go('/companies/$companyId/support'),
                                child: const Text('Suporte'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        ),
      ],
    );
  }
}

class _SessionsSummary extends StatelessWidget {
  const _SessionsSummary({required this.sessions});

  final List<AdminDeviceSession> sessions;

  @override
  Widget build(BuildContext context) {
    final active = sessions.where((session) => _statusKey(session) == 'active');
    final expired = sessions.where(
      (session) => _statusKey(session) == 'expired',
    );
    final revoked = sessions.where(
      (session) => _statusKey(session) == 'revoked',
    );
    final noData = sessions.where(
      (session) => _statusKey(session) == 'unknown',
    );
    final mobile = sessions.where(
      (session) => session.clientType.toUpperCase() == 'MOBILE_APP',
    );
    final admin = sessions.where(
      (session) => session.clientType.toUpperCase() == 'ADMIN_WEB',
    );

    return Wrap(
      spacing: 14,
      runSpacing: 14,
      children: [
        _MetricTile(title: 'Total', value: '${sessions.length}'),
        _MetricTile(title: 'Ativas', value: '${active.length}'),
        _MetricTile(title: 'Expiradas', value: '${expired.length}'),
        _MetricTile(title: 'Revogadas', value: '${revoked.length}'),
        _MetricTile(title: 'Sem dados', value: '${noData.length}'),
        _MetricTile(title: 'MOBILE_APP', value: '${mobile.length}'),
        _MetricTile(title: 'ADMIN_WEB', value: '${admin.length}'),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 150, maxWidth: 220),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
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
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        children: [
          const Icon(Icons.login_rounded),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

String _statusKey(AdminDeviceSession session) {
  final raw = session.status.trim().toLowerCase();
  if (session.revokedAt != null || raw == 'revoked') {
    return 'revoked';
  }
  final expiresAt = session.refreshTokenExpiresAt;
  if (raw == 'expired' ||
      (expiresAt != null && expiresAt.isBefore(DateTime.now()))) {
    return 'expired';
  }
  if (raw == 'active' || raw == 'valid') {
    return 'active';
  }
  if (raw.isEmpty || raw == 'unknown') {
    return 'unknown';
  }
  return raw;
}

String _sessionStatusLabel(AdminDeviceSession session) {
  return switch (_statusKey(session)) {
    'active' => 'Ativa',
    'expired' => 'Expirada',
    'revoked' => 'Revogada',
    'unknown' => 'Sem dados',
    _ => _fallback(session.status),
  };
}

AdminOperationalTone _sessionTone(AdminDeviceSession session) {
  return switch (_statusKey(session)) {
    'active' => AdminOperationalTone.ok,
    'expired' => AdminOperationalTone.attention,
    'revoked' => AdminOperationalTone.critical,
    _ => AdminOperationalTone.noData,
  };
}

String _userLabel(AdminDeviceSession session) {
  final name = session.userName.trim();
  if (name.isNotEmpty) {
    return name;
  }
  final email = session.userEmail.trim();
  if (email.isNotEmpty) {
    return maskAdminEmail(email);
  }
  final id = session.userId.trim();
  if (id.isNotEmpty) {
    return maskAdminIdentifier(id);
  }
  return 'Sessao sem usuario vinculado';
}

String _deviceLabel(AdminDeviceSession session) {
  final label = session.deviceLabel?.trim();
  if (label != null && label.isNotEmpty) {
    return label;
  }
  final instanceId = session.clientInstanceId.trim();
  if (instanceId.isNotEmpty) {
    return maskAdminIdentifier(instanceId);
  }
  return 'Sessao sem dispositivo vinculado';
}

String _companyLabel(AdminDeviceSession session, String fallbackCompanyId) {
  final name = session.companyName.trim();
  if (name.isNotEmpty) {
    return name;
  }
  final id = session.companyId.trim();
  if (id.isNotEmpty) {
    return maskAdminIdentifier(id);
  }
  return maskAdminIdentifier(fallbackCompanyId);
}

String _clientTypeLabel(String value) {
  switch (value.toUpperCase()) {
    case 'MOBILE_APP':
      return 'Mobile app';
    case 'ADMIN_WEB':
      return 'Admin Web';
    case 'OWNER_WEB':
      return 'Owner Web';
    default:
      return _fallback(value);
  }
}

String _formatDate(DateTime? value) {
  if (value == null) {
    return 'Indisponivel';
  }
  return AdminFormatters.formatDateTime(value);
}

String _fallback(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return 'Indisponivel';
  }
  return safeAdminSensitiveText(trimmed, fallback: 'Indisponivel');
}

String _safeError(Object error) {
  final message = error.toString();
  if (message.contains('Exception:')) {
    return message.split('Exception:').last.trim();
  }
  return safeAdminSensitiveText(message, fallback: 'Erro indisponivel');
}
