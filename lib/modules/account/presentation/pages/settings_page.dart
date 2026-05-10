import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/widgets/app_list_tile_card.dart';
import '../../../../app/core/widgets/app_main_drawer.dart';
import '../../../../app/core/widgets/app_page_header.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import '../../../../app/routes/route_names.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      drawer: const AppMainDrawer(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          const AppPageHeader(
            title: 'Configurações',
            subtitle: 'Preferências do aplicativo e atalhos de manutenção.',
            badgeLabel: 'Sistema',
            badgeIcon: Icons.settings_rounded,
            emphasized: true,
          ),
          const SizedBox(height: 18),
          AppSectionCard(
            title: 'Conta e empresa',
            child: Column(
              children: [
                AppListTileCard(
                  title: 'Minha conta',
                  subtitle: 'Veja dados da conta e status da nuvem.',
                  leading: const Icon(Icons.account_circle_outlined),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.goNamed(AppRouteNames.accountCloud),
                ),
                const SizedBox(height: 10),
                AppListTileCard(
                  title: 'Empresa',
                  subtitle: 'Veja dados da loja, plano e assinatura.',
                  leading: const Icon(Icons.storefront_rounded),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.goNamed(AppRouteNames.company),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          AppSectionCard(
            title: 'Manutenção',
            child: Column(
              children: [
                AppListTileCard(
                  title: 'Backup',
                  subtitle: 'Salvar e restaurar dados deste dispositivo.',
                  leading: const Icon(Icons.backup_rounded),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.goNamed(AppRouteNames.backup),
                ),
                const SizedBox(height: 10),
                AppListTileCard(
                  title: 'Assinatura e planos',
                  subtitle: 'Ver plano atual e opções disponíveis.',
                  leading: const Icon(Icons.workspace_premium_outlined),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.goNamed(AppRouteNames.subscription),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
