import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/owner_providers.dart';
import '../../../core/widgets/owner_async_view.dart';
import '../../../core/widgets/owner_formatters.dart';

class OwnerDashboardPage extends ConsumerWidget {
  const OwnerDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(ownerDashboardProvider);
    return OwnerAsyncView(
      value: dashboard,
      onRetry: () => ref.invalidate(ownerDashboardProvider),
      builder: (data) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _MetricCard(
                  title: 'Plano atual',
                  value: data.billing.plan,
                  detail: OwnerFormatters.status(data.billing.status),
                  icon: Icons.workspace_premium_rounded,
                ),
                _MetricCard(
                  title: 'Funcionários',
                  value: '${data.employees.active}',
                  detail: data.employees.available
                      ? '${data.employees.invited} convidados'
                      : 'Visualização futura',
                  icon: Icons.badge_rounded,
                ),
                _MetricCard(
                  title: 'Dispositivos',
                  value: '${data.devices.active}/${data.devices.maxDevices}',
                  detail: '${data.devices.pending} pendentes',
                  icon: Icons.devices_rounded,
                ),
                _MetricCard(
                  title: 'Sync',
                  value: data.sync == null
                      ? 'Indisponível'
                      : '${data.sync!.pendingEvents}',
                  detail: data.sync == null
                      ? 'Sem fonte segura agora'
                      : 'eventos pendentes',
                  icon: Icons.cloud_done_rounded,
                ),
              ],
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.company.name,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      data.billing.cancelAtPeriodEnd
                          ? 'Cancelamento agendado. O acesso permanece conforme o período vigente.'
                          : 'Assinatura acompanhada em modo leitura.',
                    ),
                    if (data.billing.pendingPlan != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Troca pendente: ${data.billing.pendingPlan}. Ela não altera recursos antes da confirmação backend.',
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.detail,
    required this.icon,
  });

  final String title;
  final String value;
  final String detail;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              Text(title, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 6),
              Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                detail,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
