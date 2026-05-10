import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/owner_providers.dart';
import '../../../core/widgets/owner_async_view.dart';
import '../../../core/widgets/owner_formatters.dart';
import '../../../core/widgets/owner_management_widgets.dart';

class OwnerCompanyPage extends ConsumerWidget {
  const OwnerCompanyPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final company = ref.watch(ownerCompanyProvider);
    return OwnerAsyncView(
      value: company,
      onRetry: () => ref.invalidate(ownerCompanyProvider),
      builder: (data) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OwnerPageIntro(
              title: data.name,
              subtitle: 'Resumo da empresa e do acesso ao painel.',
              icon: Icons.storefront_rounded,
              trailing: Chip(
                label: Text('Plano ${ownerPlanLabel(data.license.plan)}'),
              ),
            ),
            const SizedBox(height: 18),
            OwnerSectionCard(
              title: 'Dados da empresa',
              subtitle: 'Informações disponíveis para consulta.',
              child: Wrap(
                spacing: 24,
                runSpacing: 14,
                children: [
                  _InfoItem(label: 'Nome', value: data.name),
                  _InfoItem(
                    label: 'Status',
                    value: OwnerFormatters.status(data.license.status),
                  ),
                  _InfoItem(
                    label: 'Próxima cobrança',
                    value: OwnerFormatters.date(data.license.nextPaymentDate),
                  ),
                  _InfoItem(
                    label: 'Criada em',
                    value: OwnerFormatters.date(data.createdAt),
                  ),
                  _InfoItem(
                    label: 'Funcionários no plano',
                    value: '${data.limits.maxEmployees}',
                  ),
                  _InfoItem(
                    label: 'Dispositivos no plano',
                    value: '${data.limits.maxDevices}',
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _InfoItem extends StatelessWidget {
  const _InfoItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}
