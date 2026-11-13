import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tatuzin/app/core/session/app_session.dart';
import 'package:tatuzin/app/core/session/session_provider.dart';
import 'package:tatuzin/app/core/widgets/app_navigation_shell.dart';
import 'package:tatuzin/app/routes/app_destinations.dart';
import 'test_tenant_session.dart';

void main() {
  testWidgets(
    'five destinations preserve a product search across tab switches',
    (tester) async {
      final container = ProviderContainer();
      setTestTenantSession(container);
      final session = container.read(appSessionProvider);
      container
          .read(appSessionProvider.notifier)
          .setAuthenticatedSession(
            scope: session.scope,
            user: session.user,
            company: session.company,
            clientInstanceId: session.clientInstanceId,
            membership: const AppMembershipContext(
              role: 'OWNER',
              permissions: {},
            ),
          );
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (context, state, shell) =>
                AppNavigationShell(shell: shell, path: state.uri.path),
            branches: [
              for (final destination in appDestinations)
                StatefulShellBranch(
                  routes: [
                    GoRoute(
                      path: destination.path,
                      builder: (context, state) => Scaffold(
                        body: destination.branch == 1
                            ? const TextField(key: Key('product-search'))
                            : Text('Content ${destination.label}'),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(NavigationDestination), findsNWidgets(5));
      await tester.tap(find.text('Produtos'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('product-search')),
        'Camiseta',
      );
      await tester.tap(find.text('Perfil'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Produtos'));
      await tester.pumpAndSettle();
      expect(find.text('Camiseta'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
      container.dispose();
    },
  );

  test('navigation excludes destinations without permission', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    setTestTenantSession(container);
    final session = container
        .read(appSessionProvider)
        .copyWith(
          membership: const AppMembershipContext(
            role: 'MEMBER',
            permissions: {'sales.create'},
          ),
        );
    expect(destinationsFor(session).map((destination) => destination.label), [
      'Início',
      'Vender',
      'Atividade',
      'Perfil',
    ]);
    expect(
      destinationsFor(
        session.copyWith(
          membership: const AppMembershipContext(
            role: 'MEMBER',
            permissions: {},
          ),
        ),
      ).map((destination) => destination.label),
      ['Início', 'Perfil'],
    );
  });
}
