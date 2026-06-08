import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/admin_providers.dart';
import 'admin_breadcrumbs.dart';

class AdminShellScaffold extends ConsumerWidget {
  const AdminShellScaffold({
    super.key,
    required this.currentLocation,
    required this.title,
    required this.child,
  });

  final String currentLocation;
  final String title;
  final Widget child;

  static const _items = <_AdminNavItem>[
    _AdminNavItem(
      route: '/dashboard',
      icon: Icons.space_dashboard_rounded,
      label: 'Dashboard',
    ),
    _AdminNavItem(
      route: '/companies',
      icon: Icons.apartment_rounded,
      label: 'Empresas',
    ),
    _AdminNavItem(
      route: '/sync',
      icon: Icons.sync_problem_rounded,
      label: 'Sync Center',
    ),
    _AdminNavItem(
      route: '/devices',
      icon: Icons.devices_rounded,
      label: 'Dispositivos',
    ),
    _AdminNavItem(
      route: '/licenses',
      icon: Icons.workspace_premium_rounded,
      label: 'Licencas',
    ),
    _AdminNavItem(
      route: '/plans',
      icon: Icons.table_chart_rounded,
      label: 'Planos',
    ),
    _AdminNavItem(
      route: '/permissions',
      icon: Icons.admin_panel_settings_rounded,
      label: 'Permissoes',
    ),
    _AdminNavItem(
      route: '/tenant-deletion',
      icon: Icons.privacy_tip_rounded,
      label: 'Exclusao tenant',
      badge: 'Dry-run',
    ),
    _AdminNavItem(
      route: '/audit',
      icon: Icons.fact_check_rounded,
      label: 'Auditoria',
    ),
    _AdminNavItem(
      route: '/billing',
      icon: Icons.admin_panel_settings_rounded,
      label: 'Billing',
      badge: 'Restrito',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(adminAuthControllerProvider);
    final isCompact = MediaQuery.sizeOf(context).width < 980;
    final sessionName = auth.session?.user.name ?? 'Administrador';
    final sessionEmail = auth.session?.user.email ?? 'sem sessao';
    final isAdvancedBilling = currentLocation.startsWith('/billing');
    final hasSyncSupportActions =
        currentLocation.startsWith('/sync') ||
        (currentLocation.startsWith('/companies/') &&
            currentLocation.endsWith('/sync'));

    if (isCompact) {
      return Scaffold(
        appBar: AppBar(
          title: Text(title),
          actions: [
            IconButton(
              tooltip: 'Sair',
              onPressed: () => ref.read(adminAuthControllerProvider).logout(),
              icon: const Icon(Icons.logout_rounded),
            ),
            const SizedBox(width: 8),
          ],
        ),
        drawer: Drawer(
          child: _Sidebar(
            currentLocation: currentLocation,
            sessionName: sessionName,
            sessionEmail: sessionEmail,
            isAdvancedBilling: isAdvancedBilling,
            hasSyncSupportActions: hasSyncSupportActions,
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AdminBreadcrumbs(location: currentLocation),
              const SizedBox(height: 12),
              Expanded(child: child),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      body: Row(
        children: [
          _Sidebar(
            currentLocation: currentLocation,
            sessionName: sessionName,
            sessionEmail: sessionEmail,
            isAdvancedBilling: isAdvancedBilling,
            hasSyncSupportActions: hasSyncSupportActions,
          ),
          Expanded(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(28, 20, 28, 18),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    border: Border(
                      bottom: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AdminBreadcrumbs(location: currentLocation),
                            const SizedBox(height: 8),
                            Text(
                              title,
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isAdvancedBilling
                                  ? 'Console interno restrito para operacao auditada de billing da plataforma.'
                                  : _supportDescription(currentLocation),
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 20),
                      _SessionPill(name: sessionName, email: sessionEmail),
                      const SizedBox(width: 10),
                      FilledButton.tonalIcon(
                        onPressed: () =>
                            ref.read(adminAuthControllerProvider).logout(),
                        icon: const Icon(Icons.logout_rounded),
                        label: const Text('Sair'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: child,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.currentLocation,
    required this.sessionName,
    required this.sessionEmail,
    required this.isAdvancedBilling,
    required this.hasSyncSupportActions,
  });

  final String currentLocation;
  final String sessionName;
  final String sessionEmail;
  final bool isAdvancedBilling;
  final bool hasSyncSupportActions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 272,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          right: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.admin_panel_settings_rounded,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tatuzin Admin',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'Plataforma',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _SessionCard(name: sessionName, email: sessionEmail),
              const SizedBox(height: 18),
              Text(
                'Navegacao',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.separated(
                  itemCount: AdminShellScaffold._items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final item = AdminShellScaffold._items[index];
                    final selected = _isSelected(item.route, currentLocation);
                    return ListTile(
                      dense: true,
                      selected: selected,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      leading: Icon(item.icon),
                      title: item.badge == null
                          ? Text(item.label)
                          : _NavTitle(item: item),
                      onTap: () {
                        if (!selected) {
                          context.go(item.route);
                        } else if (Navigator.of(context).canPop()) {
                          Navigator.of(context).pop();
                        }
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              _ReadOnlyBadge(
                isAdvancedBilling: isAdvancedBilling,
                hasSyncSupportActions: hasSyncSupportActions,
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _isSelected(String route, String location) {
    if (route == '/dashboard') {
      return location == '/dashboard' || location == '/';
    }
    if (route == '/companies') {
      return location == '/companies' ||
          (location.startsWith('/companies/') &&
              !location.endsWith('/sync') &&
              !location.endsWith('/license'));
    }
    if (route == '/sync') {
      return location == '/sync' ||
          location.startsWith('/sync/') ||
          (location.startsWith('/companies/') && location.endsWith('/sync'));
    }
    if (route == '/licenses') {
      return location.startsWith('/licenses') ||
          (location.startsWith('/companies/') && location.endsWith('/license'));
    }
    return location == route || location.startsWith('$route/');
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.name, required this.email});

  final String name;
  final String email;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(email, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _NavTitle extends StatelessWidget {
  const _NavTitle({required this.item});

  final _AdminNavItem item;

  @override
  Widget build(BuildContext context) {
    if (item.badge == null) {
      return Text(item.label);
    }
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(child: Text(item.label)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: scheme.errorContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            item.badge!,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onErrorContainer,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _SessionPill extends StatelessWidget {
  const _SessionPill({required this.name, required this.email});

  final String name;
  final String email;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(email, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _ReadOnlyBadge extends StatelessWidget {
  const _ReadOnlyBadge({
    required this.isAdvancedBilling,
    required this.hasSyncSupportActions,
  });

  final bool isAdvancedBilling;
  final bool hasSyncSupportActions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isAdvancedBilling
            ? scheme.errorContainer
            : scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        isAdvancedBilling
            ? 'Billing restrito: esta rota preserva acoes administrativas reais.'
            : hasSyncSupportActions
            ? 'Modo seguro: acoes sensiveis exigem dry-run, confirmacao e auditoria.'
            : 'Modo seguro/read-only: sem alteracoes reais nesta area.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: isAdvancedBilling
              ? scheme.onErrorContainer
              : scheme.onSecondaryContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

String _supportDescription(String location) {
  if (location.startsWith('/companies')) {
    return 'Suporte interno para empresas, usuarios, funcionarios, dispositivos, sessoes e licencas.';
  }
  if (location.startsWith('/sync-health')) {
    return 'Monitoramento interno da saude do sync da plataforma.';
  }
  if (location.startsWith('/sync')) {
    return 'Triagem interna de sync, conflitos e eventos por empresa.';
  }
  if (location.startsWith('/devices')) {
    return 'Inventario interno de dispositivos e sessoes da plataforma.';
  }
  if (location.startsWith('/licenses')) {
    return 'Consulta interna read-only de licencas e assinaturas.';
  }
  if (location.startsWith('/permissions') ||
      location.startsWith('/admin/permissions')) {
    return 'Consulta read-only de permissoes administrativas persistidas.';
  }
  if (location.startsWith('/tenant-deletion')) {
    return 'Fundacao auditada para solicitacoes de exclusao de tenant, somente dry-run.';
  }
  if (location.startsWith('/audit')) {
    return 'Auditoria interna de acoes administrativas da plataforma.';
  }
  return 'Console interno para operacao, suporte e auditoria da plataforma.';
}

class _AdminNavItem {
  const _AdminNavItem({
    required this.route,
    required this.icon,
    required this.label,
    this.badge,
  });

  final String route;
  final IconData icon;
  final String label;
  final String? badge;
}
