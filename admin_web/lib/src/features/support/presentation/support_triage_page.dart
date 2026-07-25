import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/admin_providers.dart';
import '../../../core/models/admin_support_models.dart';
import '../../../core/utils/admin_formatters.dart';
import '../../../core/widgets/admin_operational_status.dart';
import '../../../core/widgets/admin_surface.dart';

class SupportTriagePage extends ConsumerWidget {
  const SupportTriagePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final triageAsync = ref.watch(adminSupportTriageProvider);
    return triageAsync.when(
      data: (snapshot) => _SupportTriageContent(snapshot: snapshot),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => AdminSurface(
        title: 'Nao foi possivel carregar a triagem de suporte',
        subtitle: _safeError(error),
        trailing: FilledButton.tonalIcon(
          onPressed: () => ref.invalidate(adminSupportTriageProvider),
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Tentar novamente'),
        ),
        child: const Text('Nenhum payload sensivel foi exibido.'),
      ),
    );
  }
}

class _SupportTriageContent extends ConsumerWidget {
  const _SupportTriageContent({required this.snapshot});

  final AdminSupportTriageSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(adminSupportTriageProvider),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AdminSurface(
              title: 'Triagem global de suporte',
              subtitle:
                  'Fila priorizada por criticidade para orientar problema, causa provavel, evidencia e proxima acao segura.',
              trailing: FilledButton.tonalIcon(
                onPressed: () => ref.invalidate(adminSupportTriageProvider),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Atualizar'),
              ),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _MetricCard(
                    label: 'Empresas na fila',
                    value: '${snapshot.items.length}',
                    icon: Icons.apartment_rounded,
                  ),
                  _MetricCard(
                    label: 'Criticas',
                    value: '${snapshot.criticalCompanies}',
                    icon: Icons.priority_high_rounded,
                    tone: AdminOperationalTone.critical,
                  ),
                  _MetricCard(
                    label: 'Alta prioridade',
                    value: '${snapshot.highCompanies}',
                    icon: Icons.warning_amber_rounded,
                    tone: AdminOperationalTone.attention,
                  ),
                  _MetricCard(
                    label: 'Acionaveis',
                    value: '${snapshot.actionableCompanies}',
                    icon: Icons.support_agent_rounded,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (snapshot.usesFallback)
              _FallbackNotice(unavailableSignals: snapshot.unavailableSignals),
            if (snapshot.usesFallback) const SizedBox(height: 16),
            AdminSurface(
              title: 'Empresas priorizadas',
              subtitle:
                  'Ordenacao deterministica por score. Acoes criticas continuam exigindo dry-run, motivo, confirmacao e auditoria.',
              child: snapshot.items.isEmpty
                  ? const _EmptyState(
                      message:
                          'Nenhuma empresa retornada para triagem. Verifique contratos administrativos ou filtros futuros.',
                    )
                  : _TriageTable(items: snapshot.items),
            ),
            const SizedBox(height: 16),
            const _ObservabilityReadinessCard(),
          ],
        ),
      ),
    );
  }
}

class _TriageTable extends StatelessWidget {
  const _TriageTable({required this.items});

  final List<AdminSupportTriageItem> items;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Prioridade')),
          DataColumn(label: Text('Empresa')),
          DataColumn(label: Text('Score')),
          DataColumn(label: Text('Causa provavel')),
          DataColumn(label: Text('Sinais')),
          DataColumn(label: Text('Ultima atividade')),
          DataColumn(label: Text('Acao')),
        ],
        rows: items
            .map((item) {
              return DataRow(
                cells: [
                  DataCell(
                    AdminOperationalStatus(
                      label: item.severity.label,
                      tone: _toneForSeverity(item.severity),
                      compact: true,
                    ),
                  ),
                  DataCell(Text(item.companyName)),
                  DataCell(Text('${item.score}')),
                  DataCell(
                    SizedBox(
                      width: 280,
                      child: Text(
                        item.probableCauses.join('; '),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  DataCell(
                    SizedBox(
                      width: 320,
                      child: Text(
                        item.signals.isEmpty
                            ? 'Sem sinais criticos no fallback'
                            : item.signals
                                  .map(
                                    (signal) =>
                                        '${signal.label}: ${signal.value}',
                                  )
                                  .join('; '),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  DataCell(
                    Text(AdminFormatters.formatDateTime(item.lastActivityAt)),
                  ),
                  DataCell(
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: () =>
                              context.go(item.routeToCompanyWorkspace),
                          icon: const Icon(Icons.support_agent_rounded),
                          label: const Text('Workspace'),
                        ),
                        if (item.nextBestActions.isNotEmpty)
                          OutlinedButton.icon(
                            onPressed: () =>
                                context.go(item.nextBestActions.first.route),
                            icon: const Icon(Icons.playlist_add_check_rounded),
                            label: Text(item.nextBestActions.first.label),
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
  }
}

class _FallbackNotice extends StatelessWidget {
  const _FallbackNotice({required this.unavailableSignals});

  final List<String> unavailableSignals;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Fallback seguro ativo',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: scheme.onSecondaryContainer,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'A fila usa empresas, Sync Center e billing existentes. Sinais sem contrato agregado aparecem como nao disponiveis.',
            style: TextStyle(color: scheme.onSecondaryContainer),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: unavailableSignals
                .map((signal) => Chip(label: Text(signal)))
                .toList(growable: false),
          ),
        ],
      ),
    );
  }
}

class _ObservabilityReadinessCard extends StatelessWidget {
  const _ObservabilityReadinessCard();

  @override
  Widget build(BuildContext context) {
    return const AdminSurface(
      title: 'Observabilidade visivel',
      subtitle:
          'Indicadores abaixo ficam explicitos enquanto nao houver contrato real agregado.',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          Chip(label: Text('Latencia por endpoint: nao disponivel')),
          Chip(label: Text('Taxa de erro: nao disponivel')),
          Chip(label: Text('Falhas de webhook: parcial via billing')),
          Chip(label: Text('Comandos por status: disponivel por device')),
          Chip(label: Text('Empresas criticas: calculado no fallback')),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    this.tone,
  });

  final String label;
  final String value;
  final IconData icon;
  final AdminOperationalTone? tone;

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
                    if (tone == null)
                      Text(
                        value,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      )
                    else
                      AdminOperationalStatus(
                        label: value,
                        tone: tone!,
                        compact: true,
                      ),
                    const SizedBox(height: 4),
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

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.all(24), child: Text(message));
  }
}

AdminOperationalTone _toneForSeverity(AdminSupportSeverity severity) {
  return switch (severity) {
    AdminSupportSeverity.critical => AdminOperationalTone.critical,
    AdminSupportSeverity.high => AdminOperationalTone.attention,
    AdminSupportSeverity.medium => AdminOperationalTone.attention,
    AdminSupportSeverity.low => AdminOperationalTone.noData,
    AdminSupportSeverity.healthy => AdminOperationalTone.ok,
  };
}

String _safeError(Object error) {
  final message = error.toString();
  if (message.contains('Exception:')) {
    return message.split('Exception:').last.trim();
  }
  return message.length > 180 ? '${message.substring(0, 180)}...' : message;
}
