import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/admin_providers.dart';
import '../utils/admin_formatters.dart';

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
      label: 'Dashboard Admin',
    ),
    _AdminNavItem(
      route: '/companies',
      icon: Icons.apartment_rounded,
      label: 'Empresas',
    ),
    _AdminNavItem(
      route: '/licenses',
      icon: Icons.workspace_premium_rounded,
      label: 'Licencas',
    ),
    _AdminNavItem(
      route: '/sync-health',
      icon: Icons.cloud_done_rounded,
      label: 'Saude da Sync',
    ),
    _AdminNavItem(
      route: '/audit',
      icon: Icons.fact_check_rounded,
      label: 'Auditoria',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(adminAuthControllerProvider);
    final isCompact = MediaQuery.sizeOf(context).width < 1080;

    if (isCompact) {
      return Scaffold(
        appBar: AppBar(
          title: Text(title),
          actions: [
            IconButton(
              tooltip: 'Sair',
              onPressed: () async {
                await ref.read(adminAuthControllerProvider).logout();
              },
              icon: const Icon(Icons.logout_rounded),
            ),
            const SizedBox(width: 8),
          ],
        ),
        drawer: Drawer(
          child: _Sidebar(
            currentLocation: currentLocation,
            sessionName: auth.session?.user.name ?? 'Administrador',
            sessionEmail: auth.session?.user.email ?? 'sem sessao',
            companyName: auth.session?.company.name ?? 'Tatuzin Cloud',
            licenseStatus: auth.session?.company.license?.status,
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          _Sidebar(
            currentLocation: currentLocation,
            sessionName: auth.session?.user.name ?? 'Administrador',
            sessionEmail: auth.session?.user.email ?? 'sem sessao',
            companyName: auth.session?.company.name ?? 'Tatuzin Cloud',
            licenseStatus: auth.session?.company.license?.status,
          ),
          Expanded(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(32, 24, 32, 20),
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
                            Text(
                              title,
                              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Operacao cloud, licencas e suporte da plataforma Tatuzin.',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 24),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              auth.session?.user.name ?? 'Administrador',
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              auth.session?.user.email ?? 'sem sessao',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.tonalIcon(
                        onPressed: () async {
                          await ref.read(adminAuthControllerProvider).logout();
                        },
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
    required this.companyName,
    required this.licenseStatus,
  });

  final String currentLocation;
  final String sessionName;
  final String sessionEmail;
  final String companyName;
  final String? licenseStatus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 288,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          right: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tatuzin Admin',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Painel da plataforma e suporte cloud',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sessionName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(sessionEmail, style: theme.textTheme.bodySmall),
                    const SizedBox(height: 12),
                    Text(
                      companyName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Chip(
                      label: Text(AdminFormatters.formatLicenseStatus(licenseStatus)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: ListView.separated(
                  itemCount: AdminShellScaffold._items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = AdminShellScaffold._items[index];
                    final selected = _isSelected(item.route, currentLocation);
                    return ListTile(
                      selected: selected,
                      leading: Icon(item.icon),
                      title: Text(item.label),
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
    return location == route || location.startsWith('$route/');
  }
}

class _AdminNavItem {
  const _AdminNavItem({
    required this.route,
    required this.icon,
    required this.label,
  });

  final String route;
  final IconData icon;
  final String label;
}
