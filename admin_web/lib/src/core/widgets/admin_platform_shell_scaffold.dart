import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../auth/admin_providers.dart';
import '../../features/platform/data/platform_api.dart';
import '../../features/platform/presentation/platform_pages.dart';
import 'admin_shell_scaffold.dart' show LegacyAdminShellScaffold;

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
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(adminAuthControllerProvider).isRestoring) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (ref.watch(adminAuthControllerProvider).session == null) {
      return LegacyAdminShellScaffold(
        currentLocation: currentLocation,
        title: title,
        child: child,
      );
    }
    final state = ref.watch(platformCapabilitiesProvider);
    if (state.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final capabilities = state.asData?.value;
    if (capabilities?['experienceEnabled'] != true) {
      return LegacyAdminShellScaffold(
        currentLocation: currentLocation,
        title: title,
        child: child,
      );
    }
    return _PlatformShell(
      location: currentLocation,
      title: title,
      capabilities: capabilities!,
      child: child,
    );
  }
}

class _SearchIntent extends Intent {
  const _SearchIntent();
}

class _PlatformShell extends ConsumerWidget {
  const _PlatformShell({
    required this.location,
    required this.title,
    required this.capabilities,
    required this.child,
  });
  final String location;
  final String title;
  final PlatformMap capabilities;
  final Widget child;
  static const destinations = <(String, String, String, IconData)>[
    ('/dashboard', 'Visão geral', 'overview', Icons.dashboard_outlined),
    ('/companies', 'Empresas', 'companies', Icons.apartment_outlined),
    ('/support', 'Suporte', 'support', Icons.support_agent_outlined),
    ('/sync', 'Sincronização', 'sync', Icons.sync_outlined),
    (
      '/commercial',
      'Assinaturas e cobranças',
      'billing',
      Icons.receipt_long_outlined,
    ),
    ('/devices', 'Dispositivos e acessos', 'devices', Icons.devices_outlined),
    ('/usage', 'Uso da plataforma', 'usage', Icons.insights_outlined),
    ('/audit', 'Auditoria', 'audit', Icons.history_outlined),
    (
      '/administration',
      'Administração',
      'administration',
      Icons.admin_panel_settings_outlined,
    ),
  ];
  String selected() {
    if (location.startsWith('/companies/')) return '/companies';
    if (location.startsWith('/licenses') ||
        location.startsWith('/billing') ||
        location.startsWith('/plans')) {
      return '/commercial';
    }
    if (location.startsWith('/permissions') ||
        location.startsWith('/tenant-deletion')) {
      return '/administration';
    }
    return destinations
            .where((d) => location.startsWith(d.$1))
            .map((d) => d.$1)
            .firstOrNull ??
        '/dashboard';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.sizeOf(context).width;
    final expanded = width >= 1200;
    final mobile = width < 768;
    final allowed = destinations
        .where((d) => platformAllowsSection(capabilities, d.$3))
        .toList();
    final index = allowed.indexWhere((d) => d.$1 == selected());
    void navigate(String route) => context.go(route);
    Widget side() => SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Icon(
                  Icons.admin_panel_settings_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                if (expanded || mobile) ...[
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Tatuzin Admin',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                for (final d in allowed)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    child: ListTile(
                      selected: selected() == d.$1,
                      leading: Icon(d.$4),
                      title: Text(d.$2),
                      selectedTileColor: Theme.of(
                        context,
                      ).colorScheme.primaryContainer,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      onTap: () {
                        if (mobile) Navigator.of(context).pop();
                        navigate(d.$1);
                      },
                    ),
                  ),
              ],
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Sair'),
            onTap: () => ref.read(adminAuthControllerProvider).logout(),
          ),
        ],
      ),
    );
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Theme.of(context).colorScheme.surface,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  if (mobile)
                    Builder(
                      builder: (context) => IconButton(
                        tooltip: 'Abrir menu',
                        onPressed: () => Scaffold.of(context).openDrawer(),
                        icon: const Icon(Icons.menu),
                      ),
                    ),
                  Expanded(
                    child: Text(
                      location == '/dashboard' ? 'Visão geral' : title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Buscar na plataforma (Ctrl/Cmd+K)',
                    onPressed: () => showPlatformSearch(context),
                    icon: const Icon(Icons.search),
                  ),
                  if (!mobile) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        ref
                                .watch(adminAuthControllerProvider)
                                .session
                                ?.user
                                .name ??
                            'Administrador',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Padding(
            padding: EdgeInsets.all(mobile ? 12 : 24),
            child: child,
          ),
        ),
      ],
    );
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyK, control: true):
            _SearchIntent(),
        SingleActivator(LogicalKeyboardKey.keyK, meta: true): _SearchIntent(),
      },
      child: Actions(
        actions: {
          _SearchIntent: CallbackAction<_SearchIntent>(
            onInvoke: (_) {
              showPlatformSearch(context);
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            drawer: mobile ? Drawer(child: side()) : null,
            body: Row(
              children: [
                if (!mobile && expanded)
                  SizedBox(
                    width: 266,
                    child: Material(
                      color: Theme.of(context).colorScheme.surface,
                      child: side(),
                    ),
                  ),
                if (!mobile && !expanded)
                  SafeArea(
                    child: NavigationRail(
                      selectedIndex: index < 0 ? null : index,
                      onDestinationSelected: (i) => navigate(allowed[i].$1),
                      labelType: NavigationRailLabelType.none,
                      destinations: [
                        for (final d in allowed)
                          NavigationRailDestination(
                            icon: Tooltip(message: d.$2, child: Icon(d.$4)),
                            label: Text(d.$2),
                          ),
                      ],
                    ),
                  ),
                Expanded(child: content),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AdminPlatformExperience extends ConsumerWidget {
  const AdminPlatformExperience({
    super.key,
    required this.modern,
    required this.legacy,
  });
  final Widget modern;
  final Widget legacy;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(adminAuthControllerProvider).session == null) return legacy;
    if (ref.watch(adminAuthControllerProvider).isRestoring) {
      return const Center(child: CircularProgressIndicator());
    }
    final state = ref.watch(platformCapabilitiesProvider);
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return state.asData?.value['experienceEnabled'] == true ? modern : legacy;
  }
}
