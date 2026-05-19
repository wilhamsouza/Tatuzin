import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/widgets/app_main_drawer.dart';
import '../../../../app/core/widgets/app_page_header.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import '../../../../app/routes/route_names.dart';
import '../providers/account_cloud_providers.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final internalAccess = ref.watch(internalMobileSurfaceAccessProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      drawer: const AppMainDrawer(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          const AppPageHeader(
            title: 'Configurações',
            subtitle: 'Preferências do aplicativo e do sistema.',
            badgeLabel: 'Sistema',
            badgeIcon: Icons.settings_rounded,
            emphasized: true,
          ),
          const SizedBox(height: 18),
          AppSectionCard(
            title: 'Empresa e comprovante',
            subtitle: 'Dados comerciais usados nos recibos de venda.',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.storefront_rounded),
              title: const Text('Empresa e comprovante'),
              subtitle: const Text('Nome, contato e dados exibidos no recibo'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.goNamed(AppRouteNames.company),
            ),
          ),
          const SizedBox(height: 18),
          const AppSectionCard(
            title: 'Aplicativo',
            subtitle: 'Ajustes locais aparecem aqui conforme forem liberados.',
            child: Text(
              'Conta, assinatura e nuvem agora ficam em Conta. Dados da loja ficam em Empresa.',
            ),
          ),
          if (internalAccess.canOpenTechnicalSystem) ...[
            const SizedBox(height: 18),
            AppSectionCard(
              title: 'Avançado',
              subtitle: 'Diagnósticos e suporte interno.',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.build_circle_outlined),
                title: const Text('Ferramentas internas'),
                subtitle: const Text(
                  'Acompanhamento técnico e diagnósticos do app.',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.goNamed(AppRouteNames.technicalSystem),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
