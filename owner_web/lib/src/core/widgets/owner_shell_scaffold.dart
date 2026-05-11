import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/owner_providers.dart';
import 'owner_management_widgets.dart';

class OwnerShellScaffold extends ConsumerWidget {
  const OwnerShellScaffold({
    super.key,
    required this.currentLocation,
    required this.title,
    required this.child,
  });

  final String currentLocation;
  final String title;
  final Widget child;

  static const _items = <_OwnerNavItem>[
    _OwnerNavItem(
      route: '/dashboard',
      icon: Icons.space_dashboard_rounded,
      label: 'Dashboard',
    ),
    _OwnerNavItem(
      route: '/sales',
      icon: Icons.point_of_sale_rounded,
      label: 'Vendas',
    ),
    _OwnerNavItem(
      route: '/clients',
      icon: Icons.people_alt_rounded,
      label: 'Clientes / CRM',
    ),
    _OwnerNavItem(
      route: '/finance',
      icon: Icons.account_balance_wallet_rounded,
      label: 'Fiado',
    ),
    _OwnerNavItem(
      route: '/products',
      icon: Icons.inventory_2_rounded,
      label: 'Produtos e estoque',
    ),
    _OwnerNavItem(
      route: '/employees',
      icon: Icons.badge_rounded,
      label: 'Funcionários',
    ),
    _OwnerNavItem(
      route: '/reports',
      icon: Icons.assessment_rounded,
      label: 'Relatórios',
    ),
    _OwnerNavItem(
      route: '/billing',
      icon: Icons.receipt_long_rounded,
      label: 'Assinatura',
    ),
    _OwnerNavItem(
      route: '/settings',
      icon: Icons.settings_rounded,
      label: 'Configurações',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(ownerAuthControllerProvider);
    final session = auth.session;
    final companyName = session?.company.name ?? 'Tatuzin';
    final plan = session?.company.license?.plan ?? 'Plano';
    final isCompact = MediaQuery.sizeOf(context).width < 980;

    if (isCompact) {
      return Scaffold(
        appBar: AppBar(
          title: Text(title),
          actions: [
            IconButton(
              tooltip: 'Sair',
              onPressed: () => ref.read(ownerAuthControllerProvider).logout(),
              icon: const Icon(Icons.logout_rounded),
            ),
          ],
        ),
        drawer: Drawer(
          child: _Sidebar(
            currentLocation: currentLocation,
            companyName: companyName,
            plan: plan,
          ),
        ),
        body: SingleChildScrollView(
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
            companyName: companyName,
            plan: plan,
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
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Consulta gerencial de indicadores, relatórios e operação da empresa.',
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
                      const SizedBox(width: 16),
                      _CompanyPill(companyName: companyName, plan: plan),
                      const SizedBox(width: 12),
                      FilledButton.tonalIcon(
                        onPressed: () =>
                            ref.read(ownerAuthControllerProvider).logout(),
                        icon: const Icon(Icons.logout_rounded),
                        label: const Text('Sair'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
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
    required this.companyName,
    required this.plan,
  });

  final String currentLocation;
  final String companyName;
  final String plan;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tatuzin',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Painel da empresa',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              _CompanyPill(companyName: companyName, plan: plan),
              const SizedBox(height: 24),
              for (final item in OwnerShellScaffold._items) ...[
                _NavButton(
                  item: item,
                  selected:
                      currentLocation == item.route ||
                      currentLocation.startsWith('${item.route}/'),
                ),
                const SizedBox(height: 6),
              ],
              const Spacer(),
              Text(
                'Consulta gerencial',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompanyPill extends StatelessWidget {
  const _CompanyPill({required this.companyName, required this.plan});

  final String companyName;
  final String plan;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(companyName, style: Theme.of(context).textTheme.titleSmall),
          Text(
            'Plano ${ownerPlanLabel(plan)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.item, required this.selected});

  final _OwnerNavItem item;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? Theme.of(context).colorScheme.primaryContainer
          : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => context.go(item.route),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(
                item.icon,
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OwnerNavItem {
  const _OwnerNavItem({
    required this.route,
    required this.icon,
    required this.label,
  });

  final String route;
  final IconData icon;
  final String label;
}
