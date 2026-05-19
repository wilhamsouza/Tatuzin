import 'package:erp_pdv_app/app/core/theme/app_theme.dart';
import 'package:erp_pdv_app/app/routes/route_names.dart';
import 'package:erp_pdv_app/modules/more/presentation/pages/more_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('Mais organiza grupos e navega Sistema para destinos distintos', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(480, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: AppRoutePaths.more,
      routes: [
        GoRoute(
          path: AppRoutePaths.more,
          name: AppRouteNames.more,
          builder: (context, state) => const MorePage(),
        ),
        _destinationRoute(
          AppRoutePaths.accountCloud,
          AppRouteNames.accountCloud,
          'Conta destino',
        ),
        _destinationRoute(
          AppRoutePaths.company,
          AppRouteNames.company,
          'Empresa destino',
        ),
        _destinationRoute(
          AppRoutePaths.backup,
          AppRouteNames.backup,
          'Backup destino',
        ),
        _destinationRoute(
          AppRoutePaths.settings,
          AppRouteNames.settings,
          'Configurações destino',
        ),
        _destinationRoute(
          AppRoutePaths.subscription,
          AppRouteNames.subscription,
          'Assinatura e planos destino',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    );
    await tester.pumpAndSettle();

    final scrollable = find.byType(Scrollable).first;
    for (final label in ['Atendimento', 'Controle', 'Financeiro', 'Sistema']) {
      await tester.scrollUntilVisible(
        find.text(label),
        180,
        scrollable: scrollable,
      );
      expect(find.text(label), findsOneWidget);
    }

    final destinations = <String, String>{
      'Conta': 'Conta destino',
      'Empresa': 'Empresa destino',
      'Configurações': 'Configurações destino',
    };

    expect(find.text('Backup'), findsNothing);
    expect(find.text('Assinatura e planos'), findsNothing);

    for (final entry in destinations.entries) {
      router.go(AppRoutePaths.more);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text(entry.key),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text(entry.key));
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget);
    }
  });
}

GoRoute _destinationRoute(String path, String name, String title) {
  return GoRoute(
    path: path,
    name: name,
    builder: (context, state) => Scaffold(body: Center(child: Text(title))),
  );
}
