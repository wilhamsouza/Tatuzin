import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/session/session_provider.dart';
import '../../../../app/core/widgets/app_button.dart';
import '../../../../app/core/widgets/app_main_drawer.dart';
import '../../../../app/core/widgets/app_page_header.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import '../../../../app/routes/route_names.dart';

class CompanyPage extends ConsumerWidget {
  const CompanyPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(appSessionProvider);
    final company = session.company;

    return Scaffold(
      appBar: AppBar(title: const Text('Empresa')),
      drawer: const AppMainDrawer(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          const AppPageHeader(
            title: 'Empresa',
            subtitle: 'Dados da loja, plano atual e acesso à assinatura.',
            badgeLabel: 'Sistema',
            badgeIcon: Icons.storefront_rounded,
            emphasized: true,
          ),
          const SizedBox(height: 18),
          AppSectionCard(
            title: 'Dados da empresa',
            child: Column(
              children: [
                _InfoRow(label: 'Nome', value: company.displayName),
                _InfoRow(label: 'Razão social', value: company.legalName),
                _InfoRow(
                  label: 'Documento',
                  value: company.documentNumber?.trim().isNotEmpty == true
                      ? company.documentNumber!.trim()
                      : 'Não informado',
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          AppSectionCard(
            title: 'Plano e acesso',
            subtitle:
                'O plano atual define quais recursos ficam disponíveis no app.',
            child: Column(
              children: [
                _InfoRow(label: 'Plano', value: company.licensePlanLabel),
                _InfoRow(label: 'Status', value: company.licenseStatusLabel),
                _InfoRow(
                  label: 'Validade',
                  value: company.licenseExpiresAt == null
                      ? 'Não informada'
                      : AppFormatters.shortDate(company.licenseExpiresAt!),
                ),
                _InfoRow(
                  label: 'Dispositivos',
                  value: '${company.limits.maxDevices}',
                ),
                _InfoRow(
                  label: 'Funcionários',
                  value: '${company.limits.maxEmployees}',
                ),
                const SizedBox(height: 10),
                AppButton.primary(
                  label: 'Assinatura e planos',
                  icon: Icons.workspace_premium_outlined,
                  onPressed: () => context.goNamed(AppRouteNames.subscription),
                  expand: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
