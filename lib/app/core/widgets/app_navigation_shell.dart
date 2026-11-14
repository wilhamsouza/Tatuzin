import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../routes/app_destinations.dart';
import '../../routes/route_names.dart';
import '../session/session_provider.dart';
import '../theme/dashboard_theme.dart';

class AppNavigationShell extends ConsumerWidget {
  const AppNavigationShell({
    super.key,
    required this.shell,
    required this.path,
  });
  final StatefulNavigationShell shell;
  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final destinations = destinationsFor(ref.watch(appSessionProvider));
    final selected = destinations.indexWhere(
      (destination) => destination.branch == shell.currentIndex,
    );
    final navigationTheme = shell.currentIndex == 0
        ? DashboardTheme.of(context)
        : Theme.of(context);
    final focused =
        path == AppRoutePaths.checkout ||
        path == AppRoutePaths.cart ||
        path.endsWith('/form') ||
        path.startsWith('/comprovantes/') ||
        path.startsWith('/interno/');
    return Scaffold(
      body: shell,
      bottomNavigationBar: focused
          ? null
          : Theme(
              data: navigationTheme,
              child: NavigationBar(
                height: 76,
                selectedIndex: selected < 0 ? 0 : selected,
                onDestinationSelected: (index) {
                  final branch = destinations[index].branch;
                  shell.goBranch(
                    branch,
                    initialLocation:
                        branch == 3 || branch == shell.currentIndex,
                  );
                },
                destinations: [
                  for (final destination in destinations)
                    NavigationDestination(
                      label: destination.label,
                      icon: destination.branch == 2
                          ? Container(
                              width: 48,
                              height: 36,
                              decoration: BoxDecoration(
                                color: navigationTheme.colorScheme.primary,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                destination.icon,
                                color: navigationTheme.colorScheme.onPrimary,
                              ),
                            )
                          : Icon(destination.icon),
                    ),
                ],
              ),
            ),
    );
  }
}
