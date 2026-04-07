import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../modules/account/presentation/providers/account_cloud_providers.dart';
import '../../routes/route_names.dart';
import '../constants/app_constants.dart';
import '../session/auth_provider.dart';

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
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [colorScheme.primary, colorScheme.secondary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: Text(
                        'T',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    AppConstants.appName,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    AppConstants.appSlogan,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    authStatus.companyLabel,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    authStatus.userLabel,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.92),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$accountModeLabel - $cloudLabel',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontWeight: FontWeight.w600,
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
                    label: 'Visao geral',
                    children: [
                      _DrawerItem(
                        label: 'Dashboard',
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
                    label: 'Operacao',
                    children: [
                      _DrawerItem(
                        label: 'Vendas',
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
                        label: 'Notas / Fiado',
                        icon: Icons.receipt_long_rounded,
                        isSelected: currentPath == AppRoutePaths.fiado,
                        onTap: () => _navigateTo(
                          context,
                          currentPath: currentPath,
                          path: AppRoutePaths.fiado,
                          routeName: AppRouteNames.fiado,
                        ),
                      ),
                    ],
                  ),
                  _DrawerGroup(
                    label: 'Cadastros',
                    children: [
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
                        label: 'Fornecedores',
                        icon: Icons.local_shipping_outlined,
                        isSelected: currentPath == AppRoutePaths.suppliers,
                        onTap: () => _navigateTo(
                          context,
                          currentPath: currentPath,
                          path: AppRoutePaths.suppliers,
                          routeName: AppRouteNames.suppliers,
                        ),
                      ),
                    ],
                  ),
                  _DrawerGroup(
                    label: 'Compras',
                    children: [
                      _DrawerItem(
                        label: 'Compras',
                        icon: Icons.shopping_bag_outlined,
                        isSelected: currentPath == AppRoutePaths.purchases,
                        onTap: () => _navigateTo(
                          context,
                          currentPath: currentPath,
                          path: AppRoutePaths.purchases,
                          routeName: AppRouteNames.purchases,
                        ),
                      ),
                    ],
                  ),
                  _DrawerGroup(
                    label: 'Gestao',
                    children: [
                      _DrawerItem(
                        label: 'Custos',
                        icon: Icons.request_quote_rounded,
                        isSelected: currentPath == AppRoutePaths.costs,
                        onTap: () => _navigateTo(
                          context,
                          currentPath: currentPath,
                          path: AppRoutePaths.costs,
                          routeName: AppRouteNames.costs,
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
                    ],
                  ),
                  _DrawerGroup(
                    label: 'Conta',
                    children: [
                      _DrawerItem(
                        label: 'Conta e nuvem',
                        icon: Icons.account_circle_outlined,
                        isSelected: currentPath == AppRoutePaths.accountCloud,
                        onTap: () => _navigateTo(
                          context,
                          currentPath: currentPath,
                          path: AppRoutePaths.accountCloud,
                          routeName: AppRouteNames.accountCloud,
                        ),
                      ),
                      _DrawerItem(
                        label: 'Backup e restore',
                        icon: Icons.backup_rounded,
                        isSelected: currentPath == AppRoutePaths.backup,
                        onTap: () => _navigateTo(
                          context,
                          currentPath: currentPath,
                          path: AppRoutePaths.backup,
                          routeName: AppRouteNames.backup,
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
                    color: colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(18),
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
                          'Licenca: ${authStatus.licensePlanLabel} - ${authStatus.licenseStatusLabel}',
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
          content: Text('Voce saiu da conta. O app continua no modo local.'),
        ),
      );
      router.goNamed(AppRouteNames.accountCloud);
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
                  'Acesso reservado para suporte, homologacao e evolucao do produto.',
                ),
              ),
              if (access.canOpenTechnicalSystem)
                ListTile(
                  leading: const Icon(Icons.build_circle_outlined),
                  title: const Text('Ferramentas internas'),
                  subtitle: const Text(
                    'Diagnosticos, suporte tecnico e acompanhamento interno.',
                  ),
                  onTap: () => Navigator.of(
                    sheetContext,
                  ).pop(AppRouteNames.technicalSystem),
                ),
              if (access.canOpenAdminCloud)
                ListTile(
                  leading: const Icon(Icons.admin_panel_settings_outlined),
                  title: const Text('Painel cloud interno'),
                  subtitle: const Text(
                    'Acompanhar a camada administrativa da plataforma.',
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
