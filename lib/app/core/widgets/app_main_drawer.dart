import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../modules/account/presentation/providers/account_cloud_providers.dart';
import '../../routes/route_names.dart';
import '../theme/app_design_tokens.dart';
import '../constants/app_constants.dart';
import '../entitlements/plan_entitlements.dart';
import '../session/auth_provider.dart';
import '../session/session_provider.dart';
import 'app_status_badge.dart';
import 'tatuzin_brand.dart';

class AppMainDrawer extends ConsumerWidget {
  const AppMainDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final colors = context.appColors;
    final layout = context.appLayout;
    final authState = ref.watch(authControllerProvider);
    final authStatus = ref.watch(authStatusProvider);
    final companyContext = ref.watch(currentCompanyContextProvider);
    final accountCloud = ref.watch(accountCloudStatusProvider);
    final internalAccess = ref.watch(internalMobileSurfaceAccessProvider);
    final currentPath = GoRouterState.of(context).uri.path;
    final accountModeLabel = accountCloud.accountModeLabel;
    final cloudLabel = accountCloud.statusLabel;

    bool selected(String path) {
      if (path == AppRoutePaths.dashboard) {
        return currentPath == path;
      }
      return currentPath == path || currentPath.startsWith('$path/');
    }

    bool can(FeatureKey feature) => companyContext.hasFeature(feature);

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(
                layout.space8,
                layout.space8,
                layout.space8,
                layout.space7,
              ),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF0F7B5C), Color(0xFF17A878)],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(layout.radiusLg),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.22),
                          ),
                        ),
                        child: const Center(
                          child: TatuzinMascotBadge(size: 36),
                        ),
                      ),
                      SizedBox(width: layout.space6),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              AppConstants.appName,
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0,
                              ),
                            ),
                            SizedBox(height: layout.space2),
                            Text(
                              AppConstants.appSlogan,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.white.withValues(alpha: 0.74),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: layout.space8),
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(layout.space6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(layout.radiusLg),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.18),
                      ),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: Colors.white.withValues(alpha: 0.2),
                          foregroundColor: Colors.white,
                          child: Text(
                            _initial(authStatus.userLabel),
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        SizedBox(width: layout.space5),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                authStatus.userLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              SizedBox(height: layout.space2),
                              Text(
                                authStatus.companyLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.78),
                                ),
                              ),
                            ],
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
                padding: EdgeInsets.fromLTRB(
                  layout.space6,
                  layout.space6,
                  layout.space6,
                  layout.space6,
                ),
                children: [
                  _DrawerGroup(
                    label: 'OPERAÇÃO',
                    children: [
                      _DrawerItem(
                        label: 'Dashboard',
                        icon: Icons.space_dashboard_rounded,
                        isSelected: selected(AppRoutePaths.dashboard),
                        onTap: () => _navigateTo(
                          context,
                          currentPath: currentPath,
                          path: AppRoutePaths.dashboard,
                          routeName: AppRouteNames.dashboard,
                        ),
                      ),
                      _DrawerItem(
                        label: 'PDV / Vendas',
                        icon: Icons.point_of_sale_rounded,
                        isSelected:
                            selected(AppRoutePaths.sales) ||
                            selected(AppRoutePaths.cart) ||
                            selected(AppRoutePaths.checkout),
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
                        isSelected: selected(AppRoutePaths.cash),
                        onTap: () => _navigateTo(
                          context,
                          currentPath: currentPath,
                          path: AppRoutePaths.cash,
                          routeName: AppRouteNames.cash,
                        ),
                      ),
                      _DrawerItem(
                        label: 'Pedidos',
                        icon: Icons.receipt_long_rounded,
                        isSelected: selected(AppRoutePaths.orders),
                        onTap: () => _navigateTo(
                          context,
                          currentPath: currentPath,
                          path: AppRoutePaths.orders,
                          routeName: AppRouteNames.orders,
                        ),
                      ),
                      _DrawerItem(
                        label: 'Clientes',
                        icon: Icons.people_alt_rounded,
                        isSelected: selected(AppRoutePaths.clients),
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
                        isSelected:
                            selected(AppRoutePaths.products) ||
                            (selected(AppRoutePaths.inventory) &&
                                !selected(AppRoutePaths.inventoryCounts)),
                        onTap: () => _navigateTo(
                          context,
                          currentPath: currentPath,
                          path: AppRoutePaths.products,
                          routeName: AppRouteNames.products,
                        ),
                      ),
                      if (can(FeatureKey.inventoryAdvanced))
                        _DrawerItem(
                          label: 'Inventário físico',
                          icon: Icons.fact_check_rounded,
                          isSelected: selected(AppRoutePaths.inventoryCounts),
                          onTap: () => _navigateTo(
                            context,
                            currentPath: currentPath,
                            path: AppRoutePaths.inventoryCounts,
                            routeName: AppRouteNames.inventoryCounts,
                          ),
                        ),
                      if (can(FeatureKey.purchases))
                        _DrawerItem(
                          label: 'Compras',
                          icon: Icons.shopping_bag_outlined,
                          isSelected: selected(AppRoutePaths.purchases),
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
                    label: 'FINANCEIRO',
                    children: [
                      if (can(FeatureKey.costs))
                        _DrawerItem(
                          label: 'Custos e lançamentos',
                          icon: Icons.account_balance_rounded,
                          isSelected: selected(AppRoutePaths.costs),
                          onTap: () => _navigateTo(
                            context,
                            currentPath: currentPath,
                            path: AppRoutePaths.costs,
                            routeName: AppRouteNames.costs,
                          ),
                        ),
                      if (can(FeatureKey.fiadoManagement))
                        _DrawerItem(
                          label: 'Fiado',
                          icon: Icons.receipt_long_rounded,
                          isSelected: selected(AppRoutePaths.fiado),
                          onTap: () => _navigateTo(
                            context,
                            currentPath: currentPath,
                            path: AppRoutePaths.fiado,
                            routeName: AppRouteNames.fiado,
                          ),
                        ),
                      _DrawerItem(
                        label: 'Relatórios',
                        icon: Icons.assessment_rounded,
                        isSelected: selected(AppRoutePaths.reports),
                        onTap: () => _navigateTo(
                          context,
                          currentPath: currentPath,
                          path: AppRoutePaths.reports,
                          routeName: AppRouteNames.reports,
                        ),
                      ),
                      _DrawerItem(
                        label: 'Histórico de vendas',
                        icon: Icons.history_rounded,
                        isSelected: selected(AppRoutePaths.salesHistory),
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
                    label: 'CADASTROS',
                    children: [
                      if (can(FeatureKey.suppliers))
                        _DrawerItem(
                          label: 'Fornecedores',
                          icon: Icons.local_shipping_outlined,
                          isSelected: selected(AppRoutePaths.suppliers),
                          onTap: () => _navigateTo(
                            context,
                            currentPath: currentPath,
                            path: AppRoutePaths.suppliers,
                            routeName: AppRouteNames.suppliers,
                          ),
                        ),
                      _DrawerItem(
                        label: 'Categorias',
                        icon: Icons.category_rounded,
                        isSelected: selected(AppRoutePaths.categories),
                        onTap: () => _navigateTo(
                          context,
                          currentPath: currentPath,
                          path: AppRoutePaths.categories,
                          routeName: AppRouteNames.categories,
                        ),
                      ),
                      if (can(FeatureKey.supplies))
                        _DrawerItem(
                          label: 'Insumos',
                          icon: Icons.scale_rounded,
                          isSelected: selected(AppRoutePaths.supplies),
                          onTap: () => _navigateTo(
                            context,
                            currentPath: currentPath,
                            path: AppRoutePaths.supplies,
                            routeName: AppRouteNames.supplies,
                          ),
                        ),
                      if (can(FeatureKey.employees))
                        _DrawerItem(
                          label: 'Funcionários',
                          icon: Icons.badge_outlined,
                          isSelected: selected(AppRoutePaths.employees),
                          onTap: () => _navigateTo(
                            context,
                            currentPath: currentPath,
                            path: AppRoutePaths.employees,
                            routeName: AppRouteNames.employees,
                          ),
                        ),
                    ],
                  ),
                  _DrawerGroup(
                    label: 'SISTEMA',
                    children: [
                      _DrawerItem(
                        label: 'Minha conta',
                        icon: Icons.person_outline_rounded,
                        isSelected: selected(AppRoutePaths.accountCloud),
                        onTap: () => _navigateTo(
                          context,
                          currentPath: currentPath,
                          path: AppRoutePaths.accountCloud,
                          routeName: AppRouteNames.accountCloud,
                        ),
                      ),
                      _DrawerItem(
                        label: 'Empresa',
                        icon: Icons.storefront_rounded,
                        isSelected: selected(AppRoutePaths.company),
                        onTap: () => _navigateTo(
                          context,
                          currentPath: currentPath,
                          path: AppRoutePaths.company,
                          routeName: AppRouteNames.company,
                        ),
                      ),
                      _DrawerItem(
                        label: 'Assinatura e planos',
                        icon: Icons.workspace_premium_outlined,
                        isSelected: selected(AppRoutePaths.subscription),
                        onTap: () => _navigateTo(
                          context,
                          currentPath: currentPath,
                          path: AppRoutePaths.subscription,
                          routeName: AppRouteNames.subscription,
                        ),
                      ),
                      _DrawerItem(
                        label: 'Configurações',
                        icon: Icons.settings_rounded,
                        isSelected: selected(AppRoutePaths.settings),
                        onTap: () => _navigateTo(
                          context,
                          currentPath: currentPath,
                          path: AppRoutePaths.settings,
                          routeName: AppRouteNames.settings,
                        ),
                      ),
                      _DrawerItem(
                        label: 'Backup',
                        icon: Icons.cloud_upload_outlined,
                        isSelected: selected(AppRoutePaths.backup),
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
              padding: EdgeInsets.fromLTRB(
                layout.space8,
                layout.space4,
                layout.space8,
                layout.space8,
              ),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onLongPress: internalAccess.hasAnyAccess
                    ? () => _showInternalAccessMenu(context, internalAccess)
                    : null,
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(layout.space7),
                  decoration: BoxDecoration(
                    color: colors.cardBackground,
                    borderRadius: BorderRadius.circular(layout.radiusLg),
                    border: Border.all(color: colors.outlineSoft),
                    boxShadow: [
                      BoxShadow(
                        color: colors.shadowSoft,
                        blurRadius: layout.shadowBlur,
                        offset: Offset(0, layout.shadowOffsetY / 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${AppConstants.appName} v${AppConstants.appVersion}',
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: layout.space4),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 220),
                          child: AppStatusBadge(
                            label: cloudLabel,
                            tone: accountCloud.tone,
                            icon: accountCloud.icon,
                          ),
                        ),
                      ),
                      SizedBox(height: layout.space5),
                      Text(
                        'Conta: $accountModeLabel',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: layout.space2),
                      Text(
                        'Nuvem: $cloudLabel',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (authStatus.isRemoteAuthenticated) ...[
                        SizedBox(height: layout.space2),
                        Text(
                          'Licença: ${authStatus.licensePlanLabel} - ${authStatus.licenseStatusLabel}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      SizedBox(height: layout.space6),
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

  String _initial(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return 'T';
    }
    return trimmed.substring(0, 1).toUpperCase();
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
            'Você saiu da conta. Entre novamente para acessar a empresa.',
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
    final layout = context.appLayout;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(bottom: layout.space6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              layout.space6,
              layout.space5,
              layout.space6,
              layout.space3,
            ),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
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
    final colors = context.appColors;
    final layout = context.appLayout;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: layout.space2 / 2),
      child: ListTile(
        selected: isSelected,
        selectedTileColor: colors.brand.surface,
        tileColor: isSelected ? colors.brand.surface : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(layout.radiusMd),
          side: BorderSide(
            color: isSelected ? colors.brand.border : Colors.transparent,
          ),
        ),
        leading: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: isSelected
                ? colors.cardBackground
                : colors.sectionBackground,
            borderRadius: BorderRadius.circular(layout.radiusSm),
          ),
          child: Icon(
            icon,
            size: layout.iconMd,
            color: isSelected
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant,
          ),
        ),
        title: Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: isSelected ? colorScheme.primary : colorScheme.onSurface,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
        trailing: isSelected
            ? Icon(
                Icons.chevron_right_rounded,
                color: colorScheme.primary,
                size: layout.iconMd,
              )
            : null,
        onTap: onTap,
      ),
    );
  }
}
