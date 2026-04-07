import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/admin_providers.dart';
import '../../../core/utils/admin_formatters.dart';
import '../../../core/widgets/admin_surface.dart';

class AuditPage extends ConsumerWidget {
  const AuditPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audit = ref.watch(adminAuditSummaryProvider);
    return audit.when(
      data: (summary) => SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AdminSurface(
              title: 'Resumo da auditoria administrativa',
              subtitle: 'Mudancas de licenca e eventos do painel cloud.',
              child: Wrap(
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
            ),
            const SizedBox(height: 24),
            AdminSurface(
              title: 'Eventos recentes',
              subtitle: 'Historico administrativo mais recente da plataforma.',
              child: Column(
                children: summary.recentEvents.map((event) {
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
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
            ),
          ],
        ),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => AdminSurface(
        title: 'Nao foi possivel carregar a auditoria',
        subtitle: error.toString(),
        child: const SizedBox.shrink(),
      ),
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
