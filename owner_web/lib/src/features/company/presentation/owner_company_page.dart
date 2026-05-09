import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/owner_providers.dart';
import '../../../core/widgets/owner_async_view.dart';
import '../../../core/widgets/owner_formatters.dart';

class OwnerCompanyPage extends ConsumerWidget {
  const OwnerCompanyPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final company = ref.watch(ownerCompanyProvider);
    return OwnerAsyncView(
      value: company,
      onRetry: () => ref.invalidate(ownerCompanyProvider),
      builder: (data) {
        final enabledFeatures = data.features.entries
            .where((entry) => entry.value)
            .map((entry) => entry.key)
            .toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.name,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        Chip(label: Text('Plano ${data.license.plan}')),
                        Chip(
                          label: Text(
                            'Status ${OwnerFormatters.status(data.license.status)}',
                          ),
                        ),
                        Chip(label: Text('Perfil ${data.membershipRole}')),
                        Chip(
                          label: Text(
                            data.setupCompleted
                                ? 'Configuração concluída'
                                : 'Configuração pendente',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _InfoCard(
                  title: 'Dispositivos',
                  value: '${data.limits.maxDevices}',
                  detail: 'limite do plano',
                ),
                _InfoCard(
                  title: 'Funcionários',
                  value: '${data.limits.maxEmployees}',
                  detail: 'limite do plano',
                ),
                _InfoCard(
                  title: 'Relatórios',
                  value: data.limits.reportPeriods.isEmpty
                      ? 'Indisponível'
                      : data.limits.reportPeriods.join(', '),
                  detail: 'períodos liberados',
                ),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Recursos liberados',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final feature in enabledFeatures.take(24))
                          Chip(label: Text(feature)),
                      ],
                    ),
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

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.value,
    required this.detail,
  });

  final String title;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title),
              const SizedBox(height: 8),
              Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(detail),
            ],
          ),
        ),
      ),
    );
  }
}
