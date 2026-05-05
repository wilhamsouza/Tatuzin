import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../modules/account/presentation/providers/account_cloud_providers.dart';
import '../../routes/route_names.dart';
import '../constants/app_constants.dart';
import '../session/auth_provider.dart';
import 'tatuzin_brand.dart';

class AppMainDrawer extends ConsumerWidget {
  const AppMainDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final authState = ref.watch(authControllerProvider);
    final authStatus = ref.watch(authStatusProvider);
    final accountCloud = ref.watch(accountCloudStatusProvider);
    final internalAccess = ref.watch(internalMobileSurfaceAccessProvider);
    final currentPath = GoRouterState.of(context).uri.path;
    final accountModeLabel = accountCloud.accountModeLabel;
    final cloudLabel = accountCloud.statusLabel;

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                border: Border(
                  bottom: BorderSide(color: colorScheme.outlineVariant),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const TatuzinMascotBadge(size: 46),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppConstants.appName,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.4,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          authStatus.companyLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          authStatus.userLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '$accountModeLabel • $cloudLabel',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                children: [
                  _DrawerGroup(
                    label: 'Inicio',
                    children: [
                      _DrawerItem(
                        label: 'Inicio',
                        icon: Icons.space_dashboard_rounded,
                        isSelected: currentPath == AppRoutePaths.dashboard,
                        onTap: () => _navigateTo(
                          context,
                          currentPath: currentPath,
                          path: AppRoutePaths.dashboard,
                          routeName: AppRouteNames.dashboard,
                        ),
                      ),
                    ],
                  ),
                  _DrawerGroup(
                    label: 'Caixa',
                    children: [
                      _DrawerItem(
                        label: 'Nova venda',
                        icon: Icons.point_of_sale_rounded,
                        isSelected: currentPath == AppRoutePaths.sales,
                        onTap: () => _navigateTo(
                          context,
                          currentPath: currentPath,
                          path: AppRoutePaths.sales,
                          routeName: AppRouteNames.sales,
                        ),
                      ),
                      _DrawerItem(
                        label: 'Carrinho',
                        icon: Icons.shopping_cart_rounded,
                        isSelected: currentPath == AppRoutePaths.cart,
                        onTap: () => _navigateTo(
                          context,
                          currentPath: currentPath,
                          path: AppRoutePaths.cart,
                          routeName: AppRouteNames.cart,
                        ),
                      ),
                      _DrawerItem(
                        label: 'Receber pagamento',
                        icon: Icons.payments_rounded,
                        isSelected: currentPath == AppRoutePaths.checkout,
                        onTap: () => _navigateTo(
                          context,
                          currentPath: currentPath,
                          path: AppRoutePaths.checkout,
                          routeName: AppRouteNames.checkout,
                        ),
                      ),
                      _DrawerItem(
                        label: 'Caixa',
                        icon: Icons.account_balance_wallet_rounded,
                        isSelected: currentPath == AppRoutePaths.cash,
                        onTap: () => _navigateTo(
                          context,
                          currentPath: currentPath,
                          path: AppRoutePaths.cash,
                          routeName: AppRouteNames.cash,
                        ),
                      ),
                      _DrawerItem(
                        label: 'Vendas realizadas',
                        icon: Icons.history_rounded,
                        isSelected: currentPath == AppRoutePaths.salesHistory,
                        onTap: () => _navigateTo(
                          context,
                          currentPath: currentPath,
                          path: AppRoutePaths.salesHistory,
                          routeName: AppRouteNames.salesHistory,
                        ),
                      ),
                    ],
                  ),
                  _DrawerGroup(
                    label: 'Pedidos',
                    children: [
                      _DrawerItem(
                        label: 'Pedidos em aberto',
                        icon: Icons.receipt_long_rounded,
                        isSelected: currentPath == AppRoutePaths.orders,
                        onTap: () => _navigateTo(
                          context,
                          currentPath: currentPath,
                          path: AppRoutePaths.orders,
                          routeName: AppRouteNames.orders,
                        ),
                      ),
                      _DrawerItem(
                        label: 'Em separacao/preparo',
                        icon: Icons.room_service_rounded,
                        isSelected: currentPath == AppRoutePaths.orders,
                        onTap: () => _navigateTo(
                          context,
                          currentPath: currentPath,
                          path: AppRoutePaths.orders,
                          routeName: AppRouteNames.orders,
                        ),
                      ),
                      _DrawerItem(
                        label: 'Finalizados e cancelados',
                        icon: Icons.fact_check_rounded,
                        isSelected: currentPath == AppRoutePaths.orders,
                        onTap: () => _navigateTo(
                          context,
                          currentPath: currentPath,
                          path: AppRoutePaths.orders,
                          routeName: AppRouteNames.orders,
                        ),
                      ),
                    ],
                  ),
                  _DrawerGroup(
                    label: 'Produtos',
                    children: [
                      _DrawerItem(
                        label: 'Produtos',
                        icon: Icons.inventory_2_rounded,
                        isSelected: currentPath == AppRoutePaths.products,
                        onTap: () => _navigateTo(
                          context,
                          currentPath: currentPath,
                          path: AppRoutePaths.products,
                          routeName: AppRouteNames.products,
                        ),
                      ),
                      _DrawerItem(
                        label: 'Categorias',
                        icon: Icons.category_rounded,
                        isSelected: currentPath == AppRoutePaths.categories,
                        onTap: () => _navigateTo(
                          context,
                          currentPath: currentPath,
                          path: AppRoutePaths.categories,
                          routeName: AppRouteNames.categories,
                        ),
                      ),
                      _DrawerItem(
                        label: 'Variacoes',
                        icon: Icons.layers_outlined,
                        isSelected:
                            currentPath == AppRoutePaths.products ||
                            currentPath == AppRoutePaths.productForm,
                        onTap: () => _navigateTo(
                          context,
                          currentPath: currentPath,
                          path: AppRoutePaths.products,
                          routeName: AppRouteNames.products,
                        ),
                      ),
                      _DrawerItem(
                        label: 'Estoque do produto',
                        icon: Icons.inventory_2_outlined,
                        isSelected: currentPath == AppRoutePaths.inventory,
                        onTap: () => _navigateTo(
                          context,
                          currentPath: currentPath,
                          path: AppRoutePaths.inventory,
                          routeName: AppRouteNames.inventory,
                        ),
                      ),
                    ],
                  ),
                  _DrawerGroup(
                    label: 'Mais',
                    children: [
                      _DrawerItem(
                        label: 'Mais opcoes',
                        icon: Icons.apps_rounded,
                        isSelected: currentPath == AppRoutePaths.more,
                        onTap: () => _navigateTo(
                          context,
                          currentPath: currentPath,
                          path: AppRoutePaths.more,
                          routeName: AppRouteNames.more,
                        ),
                      ),
                      _DrawerItem(
                        label: 'Clientes',
                        icon: Icons.people_alt_rounded,
                        isSelected: currentPath == AppRoutePaths.clients,
                        onTap: () => _navigateTo(
                          context,
                          currentPath: currentPath,
                          path: AppRoutePaths.clients,
                          routeName: AppRouteNames.clients,
                        ),
                      ),
                      _DrawerItem(
                        label: 'Clientes devendo',
                        icon: Icons.receipt_long_rounded,
                        isSelected: currentPath == AppRoutePaths.fiado,
                        onTap: () => _navigateTo(
                          context,
                          currentPath: currentPath,
                          path: AppRoutePaths.fiado,
                          routeName: AppRouteNames.fiado,
                        ),
                      ),
                      _DrawerItem(
                        label: 'Relatorios',
                        icon: Icons.assessment_rounded,
                        isSelected: currentPath == AppRoutePaths.reports,
                        onTap: () => _navigateTo(
                          context,
                          currentPath: currentPath,
                          path: AppRoutePaths.reports,
                          routeName: AppRouteNames.reports,
                        ),
                      ),
                      _DrawerItem(
                        label: 'Configuracoes',
                        icon: Icons.settings_rounded,
                        isSelected:
                            currentPath == AppRoutePaths.accountCloud ||
                            currentPath == AppRoutePaths.backup,
                        onTap: () => _navigateTo(
                          context,
                          currentPath: currentPath,
                          path: AppRoutePaths.accountCloud,
                          routeName: AppRouteNames.accountCloud,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onLongPress: internalAccess.hasAnyAccess
                    ? () => _showInternalAccessMenu(context, internalAccess)
                    : null,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${AppConstants.appName} v${AppConstants.appVersion}',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Conta: $accountModeLabel',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Nuvem: $cloudLabel',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (authStatus.isRemoteAuthenticated) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Licença: ${authStatus.licensePlanLabel} • ${authStatus.licenseStatusLabel}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: authState.isLoading
                              ? null
                              : () => _handleSessionAction(context, ref),
                          icon: Icon(
                            authStatus.isAuthenticated
                                ? Icons.logout_rounded
                                : Icons.login_rounded,
                          ),
                          label: Text(
                            authStatus.isAuthenticated
                                ? 'Sair da conta'
                                : 'Entrar com conta',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateTo(
    BuildContext context, {
    required String currentPath,
    required String path,
    required String routeName,
  }) {
    final navigator = Navigator.of(context);
    final router = GoRouter.of(context);
    navigator.pop();
    if (currentPath == path) {
      return;
    }
    router.goNamed(routeName);
  }

  Future<void> _handleSessionAction(BuildContext context, WidgetRef ref) async {
    final authStatus = ref.read(authStatusProvider);
    final navigator = Navigator.of(context);
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    navigator.pop();

    if (!authStatus.isAuthenticated) {
      router.goNamed(AppRouteNames.login);
      return;
    }

    try {
      await ref.read(authControllerProvider.notifier).signOutCurrentSession();
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Voce saiu da conta. Entre novamente para acessar a empresa.',
          ),
        ),
      );
      router.goNamed(AppRouteNames.login);
    } catch (_) {
      if (!context.mounted) {
        return;
      }
    }
  }

  Future<void> _showInternalAccessMenu(
    BuildContext context,
    InternalMobileSurfaceAccess access,
  ) async {
    final navigator = Navigator.of(context);
    final router = GoRouter.of(context);
    final routeName = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text('Ferramentas internas'),
                subtitle: Text(
                  'Acesso reservado para suporte, homologação e evolução do produto. O admin web continua sendo a superfície administrativa principal.',
                ),
              ),
              if (access.canOpenTechnicalSystem)
                ListTile(
                  leading: const Icon(Icons.build_circle_outlined),
                  title: const Text('Ferramentas internas'),
                  subtitle: const Text(
                    'Diagnósticos, suporte técnico e acompanhamento interno.',
                  ),
                  onTap: () => Navigator.of(
                    sheetContext,
                  ).pop(AppRouteNames.technicalSystem),
                ),
              if (access.canOpenAdminCloud)
                ListTile(
                  leading: const Icon(Icons.admin_panel_settings_outlined),
                  title: const Text('Admin interno de apoio'),
                  subtitle: const Text(
                    'Consulta interna e provisória dentro do app. Use o admin web como superfície administrativa principal.',
                  ),
                  onTap: () =>
                      Navigator.of(sheetContext).pop(AppRouteNames.admin),
                ),
            ],
          ),
        );
      },
    );

    if (routeName == null || !context.mounted) {
      return;
    }

    navigator.pop();
    router.goNamed(routeName);
  }
}

class _DrawerGroup extends StatelessWidget {
  const _DrawerGroup({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: ListTile(
        selected: isSelected,
        selectedTileColor: colorScheme.primaryContainer.withValues(alpha: 0.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: Icon(
          icon,
          color: isSelected
              ? colorScheme.primary
              : colorScheme.onSurfaceVariant,
        ),
        title: Text(
          label,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}
