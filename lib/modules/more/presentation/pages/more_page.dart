import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/theme/app_design_tokens.dart';
import '../../../../app/core/widgets/app_list_tile_card.dart';
import '../../../../app/core/widgets/app_main_drawer.dart';
import '../../../../app/core/widgets/app_page_header.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import '../../../../app/routes/route_names.dart';
import '../../../../app/routes/route_guards.dart';
import '../../../../app/core/session/session_provider.dart';
import '../../../../app/core/session/auth_provider.dart';
import '../../../../app/core/entitlements/plan_entitlements.dart';

class MorePage extends ConsumerWidget {
  const MorePage({super.key, this.title = 'Mais'});
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = context.appLayout;
    final session = ref.watch(appSessionProvider);
    final auth = ref.watch(authControllerProvider);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      drawer: const AppMainDrawer(),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          layout.pagePadding,
          layout.space5,
          layout.pagePadding,
          layout.space10,
        ),
        children: [
          AppPageHeader(
            title: title,
            subtitle: title == 'Perfil'
                ? '${session.user.displayName} · ${session.company.displayName}'
                : 'Acesse as outras areas da sua loja.',
            badgeLabel: 'Menu',
            badgeIcon: Icons.apps_rounded,
            emphasized: true,
          ),
          SizedBox(height: layout.sectionGap),
          const _MoreSection(
            title: 'Atendimento',
            items: [
              _MoreItem(
                title: 'Clientes',
                subtitle: 'Cadastro e historico de clientes',
                icon: Icons.people_alt_rounded,
                routeName: AppRouteNames.clients,
              ),
              _MoreItem(
                title: 'Fiado',
                subtitle: 'Clientes devendo e recebimentos',
                icon: Icons.receipt_long_rounded,
                routeName: AppRouteNames.fiado,
              ),
            ],
          ),
          SizedBox(height: layout.sectionGap),
          const _MoreSection(
            title: 'Controle',
            items: [
              _MoreItem(
                title: 'Estoque',
                subtitle: 'Saldos, ajustes e conferencias',
                icon: Icons.inventory_2_outlined,
                routeName: AppRouteNames.inventory,
              ),
              _MoreItem(
                title: 'Compras',
                subtitle: 'Entrada de mercadorias',
                icon: Icons.shopping_bag_outlined,
                routeName: AppRouteNames.purchases,
              ),
              _MoreItem(
                title: 'Fornecedores',
                subtitle: 'Cadastro e acompanhamento',
                icon: Icons.local_shipping_outlined,
                routeName: AppRouteNames.suppliers,
              ),
            ],
          ),
          SizedBox(height: layout.sectionGap),
          const _MoreSection(
            title: 'Financeiro',
            items: [
              _MoreItem(
                title: 'Caixa',
                subtitle: 'Abertura, movimentacoes e fechamento',
                icon: Icons.account_balance_wallet_rounded,
                routeName: AppRouteNames.cash,
              ),
              _MoreItem(
                title: 'Custos e lancamentos',
                subtitle: 'Despesas, entradas e movimentacoes financeiras',
                icon: Icons.request_quote_rounded,
                routeName: AppRouteNames.costs,
              ),
              _MoreItem(
                title: 'Relatorios',
                subtitle: 'Vendas, caixa, estoque e clientes',
                icon: Icons.assessment_rounded,
                routeName: AppRouteNames.reports,
              ),
            ],
          ),
          SizedBox(height: layout.sectionGap),
          const _MoreSection(
            title: 'Sistema',
            items: [
              _MoreItem(
                title: 'Conta',
                subtitle: 'Acesso, assinatura e nuvem',
                icon: Icons.account_circle_outlined,
                routeName: AppRouteNames.accountCloud,
              ),
              _MoreItem(
                title: 'Empresa',
                subtitle: 'Dados da loja e plano',
                icon: Icons.storefront_rounded,
                routeName: AppRouteNames.company,
              ),
              _MoreItem(
                title: 'Configurações',
                subtitle: 'Preferências do aplicativo',
                icon: Icons.settings_rounded,
                routeName: AppRouteNames.settings,
              ),
            ],
          ),
          if (title == 'Perfil') ...[
            SizedBox(height: layout.sectionGap),
            OutlinedButton.icon(
              onPressed: auth.isLoading
                  ? null
                  : () async {
                      try {
                        await ref
                            .read(authControllerProvider.notifier)
                            .signOutCurrentSession();
                      } catch (_) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Não foi possível concluir a saída. Tente novamente.',
                            ),
                          ),
                        );
                      }
                    },
              icon: const Icon(Icons.logout),
              label: const Text('Sair da conta'),
            ),
          ],
        ],
      ),
    );
  }
}

class _MoreSection extends ConsumerWidget {
  const _MoreSection({required this.title, required this.items});

  final String title;
  final List<_MoreItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = context.appLayout;
    final session = ref.watch(appSessionProvider);
    final visible = items
        .where((item) {
          final path = _profilePaths[item.routeName]!;
          final feature = _profileFeatures[item.routeName];
          return canAccessNavigationPath(session, path) &&
              (feature == null || session.hasFeature(feature));
        })
        .toList(growable: false);
    if (visible.isEmpty) return const SizedBox.shrink();

    return AppSectionCard(
      title: title,
      child: Column(
        children: [
          for (var index = 0; index < visible.length; index++) ...[
            visible[index],
            if (index < visible.length - 1) SizedBox(height: layout.blockGap),
          ],
        ],
      ),
    );
  }
}

const _profilePaths = {
  AppRouteNames.clients: AppRoutePaths.clients,
  AppRouteNames.fiado: AppRoutePaths.fiado,
  AppRouteNames.inventory: AppRoutePaths.inventory,
  AppRouteNames.purchases: AppRoutePaths.purchases,
  AppRouteNames.suppliers: AppRoutePaths.suppliers,
  AppRouteNames.cash: AppRoutePaths.cash,
  AppRouteNames.costs: AppRoutePaths.costs,
  AppRouteNames.reports: AppRoutePaths.reports,
  AppRouteNames.accountCloud: AppRoutePaths.accountCloud,
  AppRouteNames.company: AppRoutePaths.company,
  AppRouteNames.settings: AppRoutePaths.settings,
};
const _profileFeatures = {
  AppRouteNames.fiado: FeatureKey.fiadoManagement,
  AppRouteNames.purchases: FeatureKey.purchases,
  AppRouteNames.suppliers: FeatureKey.suppliers,
  AppRouteNames.costs: FeatureKey.costs,
};

class _MoreItem extends StatelessWidget {
  const _MoreItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.routeName,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String routeName;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final colors = context.appColors;

    return AppListTileCard(
      title: title,
      subtitle: subtitle,
      leading: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.brand.surface,
          borderRadius: BorderRadius.circular(layout.radiusMd),
        ),
        child: Padding(
          padding: EdgeInsets.all(layout.space4),
          child: Icon(icon, color: colors.brand.base, size: layout.iconMd),
        ),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      onTap: () => context.pushNamed(routeName),
    );
  }
}
