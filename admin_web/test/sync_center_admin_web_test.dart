import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/testing.dart';
import 'package:tatuzin_admin_web/src/core/auth/admin_auth_storage.dart';
import 'package:tatuzin_admin_web/src/core/auth/admin_providers.dart';
import 'package:tatuzin_admin_web/src/core/models/admin_access_models.dart';
import 'package:tatuzin_admin_web/src/core/models/admin_billing_models.dart';
import 'package:tatuzin_admin_web/src/core/models/admin_models.dart';
import 'package:tatuzin_admin_web/src/core/models/admin_plan_models.dart';
import 'package:tatuzin_admin_web/src/core/models/admin_sync_center_models.dart';
import 'package:tatuzin_admin_web/src/core/network/admin_api_client.dart';
import 'package:tatuzin_admin_web/src/core/network/admin_api_service.dart';
import 'package:tatuzin_admin_web/src/core/widgets/admin_shell_scaffold.dart';
import 'package:tatuzin_admin_web/src/features/audit/presentation/audit_page.dart';
import 'package:tatuzin_admin_web/src/features/companies/presentation/companies_page.dart';
import 'package:tatuzin_admin_web/src/features/companies/presentation/company_detail_page.dart';
import 'package:tatuzin_admin_web/src/features/companies/presentation/company_users_page.dart';
import 'package:tatuzin_admin_web/src/features/dashboard/presentation/dashboard_page.dart';
import 'package:tatuzin_admin_web/src/features/devices/presentation/devices_page.dart';
import 'package:tatuzin_admin_web/src/features/licenses/presentation/licenses_page.dart';
import 'package:tatuzin_admin_web/src/features/plans/presentation/plans_page.dart';
import 'package:tatuzin_admin_web/src/features/sync_center/presentation/sync_center_pages.dart';

void main() {
  test('router registra arquitetura nova sem owner_web', () {
    final routerSource = File(
      'lib/src/app/admin_web_router.dart',
    ).readAsStringSync();
    final shellSource = File(
      'lib/src/core/widgets/admin_shell_scaffold.dart',
    ).readAsStringSync();

    for (final route in [
      "path: '/dashboard'",
      "path: '/companies'",
      "path: '/companies/:companyId'",
      "path: '/companies/:companyId/sync'",
      "path: '/companies/:companyId/license'",
      "path: '/companies/:companyId/users'",
      "path: '/companies/:companyId/employees'",
      "path: '/companies/:companyId/devices'",
      "path: '/companies/:companyId/sessions'",
      "path: '/sync'",
      "path: '/sync/:companyId'",
      "path: '/devices'",
      "path: '/licenses'",
      "path: '/licenses/:companyId'",
      "path: '/plans'",
      "path: '/audit'",
    ]) {
      expect(routerSource, contains(route));
    }
    for (final label in [
      'Dashboard',
      'Empresas',
      'Sync global',
      'Dispositivos',
      'Licencas',
      'Planos',
      'Auditoria',
      'Billing avancado',
      'Avancado',
    ]) {
      expect(shellSource, contains(label));
    }
    expect(routerSource, isNot(contains("path: '/owner'")));
  });

  testWidgets('renderiza nova navegacao', (tester) async {
    _setLargeViewport(tester);
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: AdminShellScaffold(
            currentLocation: '/dashboard',
            title: 'Dashboard',
            child: SizedBox.shrink(),
          ),
        ),
      ),
    );

    expect(find.text('Dashboard'), findsWidgets);
    expect(find.text('Empresas'), findsOneWidget);
    expect(find.text('Sync global'), findsOneWidget);
    expect(find.text('Dispositivos'), findsWidgets);
    expect(find.text('Licencas'), findsOneWidget);
    expect(find.text('Planos'), findsOneWidget);
    expect(find.text('Auditoria'), findsOneWidget);
    expect(find.text('Billing avancado'), findsOneWidget);
    expect(find.text('Avancado'), findsOneWidget);
  });

  testWidgets('menu lateral destaca apenas a secao ativa', (tester) async {
    _setLargeViewport(tester);
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: AdminShellScaffold(
            currentLocation: '/companies/company-1/license',
            title: 'Licenca da empresa',
            child: SizedBox.shrink(),
          ),
        ),
      ),
    );

    final selectedTiles = tester.widgetList<ListTile>(
      find.byWidgetPredicate((widget) => widget is ListTile && widget.selected),
    );
    expect(selectedTiles.length, 1);
    expect(selectedTiles.single.title, isA<Text>());
    expect((selectedTiles.single.title as Text).data, 'Licencas');
  });

  testWidgets('dashboard mostra KPIs e CTAs', (tester) async {
    _setLargeViewport(tester);
    await tester.pumpWidget(
      _adminTestApp(
        service: _FakeReadOnlyApiService(),
        child: const DashboardPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Empresas ativas'), findsOneWidget);
    expect(find.text('Sync com atencao'), findsOneWidget);
    expect(find.text('Licencas vencendo'), findsOneWidget);
    expect(find.text('Dispositivos online'), findsOneWidget);
    expect(find.text('Empresas com problemas ativos'), findsOneWidget);
    expect(find.text('Abrir empresa'), findsOneWidget);
    expect(find.text('Abrir Sync Center'), findsWidgets);
  });

  testWidgets('/companies renderiza listagem preservada', (tester) async {
    _setLargeViewport(tester);
    await tester.pumpWidget(
      _adminTestApp(
        service: _FakeReadOnlyApiService(),
        child: const CompaniesPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Empresas'), findsOneWidget);
    expect(find.text('Loja Moda Sul'), findsOneWidget);
    expect(find.text('Abrir'), findsOneWidget);
  });

  testWidgets('empresa abre visao 360', (tester) async {
    _setLargeViewport(tester);
    await tester.pumpWidget(
      _adminRouterTestApp(
        service: _FakeReadOnlyApiService(),
        initialLocation: '/companies/company-1',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Loja Moda Sul'), findsWidgets);
    expect(find.text('Resumo'), findsOneWidget);
    expect(find.text('Resumo de sync'), findsOneWidget);
    expect(find.text('Licenca e assinatura'), findsOneWidget);
    expect(find.text('Usuarios e funcionarios'), findsOneWidget);
    expect(find.text('Abrir console de sync'), findsWidgets);
    expect(find.text('Ver licenca e assinatura'), findsWidgets);
    expect(find.text('Ver usuarios e funcionarios'), findsWidgets);
    expect(find.text('Sync'), findsOneWidget);
    expect(find.text('Licenca'), findsOneWidget);
    expect(find.text('Dispositivos'), findsWidgets);
    expect(find.text('Funcionarios'), findsWidgets);
    expect(find.text('Auditoria'), findsOneWidget);
  });

  testWidgets('Usuarios e funcionarios renderiza abas read-only', (
    tester,
  ) async {
    _setLargeViewport(tester);
    await tester.pumpWidget(
      _adminRouterTestApp(
        service: _FakeReadOnlyApiService(),
        initialLocation: '/companies/company-1/users',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Usuarios'), findsWidgets);
    expect(find.text('Resumo'), findsOneWidget);
    expect(find.text('Usuarios'), findsWidgets);
    expect(find.text('Funcionarios'), findsWidgets);
    expect(find.text('Permissoes'), findsOneWidget);
    expect(find.text('Dispositivos'), findsOneWidget);
    expect(find.text('Auditoria'), findsOneWidget);
    expect(find.text('Usuario com perfil protegido'), findsOneWidget);
    expect(find.text('Plano atual nao libera Funcionarios PRO'), findsWidgets);
    expect(find.text('pendingPlan PRO nao libera recursos'), findsOneWidget);
  });

  testWidgets('/companies/:companyId/employees e alias de usuarios', (
    tester,
  ) async {
    _setLargeViewport(tester);
    await tester.pumpWidget(
      _adminRouterTestApp(
        service: _FakeReadOnlyApiService(),
        initialLocation: '/companies/company-1/employees',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Usuarios'), findsWidgets);
    expect(find.text('Usuarios'), findsWidgets);
    expect(find.text('Permissoes'), findsOneWidget);
  });

  testWidgets('Usuarios e funcionarios exibem dados seguros por aba', (
    tester,
  ) async {
    _setLargeViewport(tester);
    final service = _FakeReadOnlyApiService();
    await tester.pumpWidget(
      _adminRouterTestApp(
        service: service,
        initialLocation: '/companies/company-1/users',
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(Tab, 'Usuarios'));
    await tester.pumpAndSettle();
    expect(find.text('Dona Tatuzin'), findsWidgets);
    expect(find.text('Gerente Loja'), findsOneWidget);
    expect(find.text('Protegido'), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('Detalhes').first,
      500,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Detalhes').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Resetar senha'), findsOneWidget);
    expect(find.textContaining('Alterar permissoes'), findsOneWidget);
    await tester.tap(find.textContaining('Resetar senha'));
    await tester.pumpAndSettle();
    expect(service.mutableBillingCalls, 0);
    expect(service.supportDryRunCalls, 0);
    expect(service.supportCreateCalls, 0);
    expect(
      find.text(
        'Acao administrativa sera implementada em fase posterior com dry-run, confirmacao explicita e auditoria.',
      ),
      findsWidgets,
    );
    await tester.tap(find.text('Fechar'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Funcionarios').last);
    await tester.pumpAndSettle();
    expect(find.text('Operadora Convidada'), findsOneWidget);
    expect(find.text('Ex Operador'), findsOneWidget);
    expect(find.text('Bloqueadas'), findsOneWidget);
    expect(find.textContaining('inviteToken'), findsNothing);
    expect(find.textContaining('secret'), findsNothing);

    await tester.tap(find.text('Permissoes'));
    await tester.pumpAndSettle();
    expect(find.text('employees.manage'), findsOneWidget);
    expect(find.text('Nao reconhecida'), findsOneWidget);

    await tester.tap(find.text('Dispositivos'));
    await tester.pumpAndSettle();
    expect(find.text('MOBILE_APP'), findsOneWidget);
    expect(find.text('ADMIN_WEB'), findsOneWidget);
    expect(find.text('client-instance-secret-long-id'), findsNothing);

    await tester.tap(find.text('Auditoria'));
    await tester.pumpAndSettle();
    expect(find.text('Historico administrativo'), findsOneWidget);
    expect(find.text('Bloqueio de acesso operacional'), findsOneWidget);
    expect(find.text('Reativacao de acesso operacional'), findsOneWidget);
    expect(find.textContaining('Chamado 123'), findsOneWidget);
    expect(find.textContaining('Bearer secret'), findsNothing);

    await tester.tap(find.widgetWithText(TextButton, 'Detalhes').first);
    await tester.pumpAndSettle();
    expect(find.text('Antes'), findsOneWidget);
    expect(find.text('Depois'), findsOneWidget);
    expect(find.text('Metadata'), findsOneWidget);
    expect(find.textContaining('passwordHash'), findsNothing);
    expect(find.textContaining('Authorization'), findsNothing);
    await tester.tap(find.text('Fechar'));
    await tester.pumpAndSettle();
  });

  testWidgets('Bloquear acesso operacional exige dry-run e confirmacao correta', (
    tester,
  ) async {
    _setLargeViewport(tester);
    final service = _FakeReadOnlyApiService();
    await tester.pumpWidget(
      _adminRouterTestApp(
        service: service,
        initialLocation: '/companies/company-1/users',
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Usuarios').last);
    await tester.pumpAndSettle();
    final usersTableScroller = find
        .ancestor(
          of: find.byType(DataTable).first,
          matching: find.byType(SingleChildScrollView),
        )
        .first;
    await tester.drag(usersTableScroller, const Offset(-1600, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Detalhes').last);
    await tester.pumpAndSettle();
    expect(find.text('Gerente Loja'), findsWidgets);
    expect(find.text('Bloquear acesso operacional'), findsOneWidget);
    expect(find.text('Ultimas acoes administrativas'), findsOneWidget);
    expect(find.text('Bloqueio de acesso operacional'), findsOneWidget);
    expect(find.text('Motivo: Chamado 123'), findsOneWidget);

    await tester.tap(find.text('Bloquear acesso operacional'));
    await tester.pumpAndSettle();
    final blockDialog = find.byType(AlertDialog).last;
    expect(
      find.text(
        'Esta acao bloqueia ou reativa o acesso operacional desta empresa. Nao apaga dados, nao altera senha, nao remove o usuario e nao revoga sessoes nesta fase.',
      ),
      findsWidgets,
    );
    await tester.enterText(
      find.descendant(of: blockDialog, matching: find.byType(TextField)).first,
      'incidente de acesso',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: blockDialog, matching: find.text('Executar dry-run')),
    );
    await tester.pumpAndSettle();

    expect(service.accessDryRunCalls, 1);
    expect(service.accessApplyCalls, 0);
    expect(
      find.text('Bloqueio operacional pode ser aplicado com seguranca.'),
      findsOneWidget,
    );
    expect(find.textContaining('BLOQUEAR'), findsWidgets);

    await tester.enterText(
      find.descendant(of: blockDialog, matching: find.byType(TextField)).last,
      'ERRADO',
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Digite BLOQUEAR para liberar a confirmacao.'),
      findsWidgets,
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Confirmar'))
          .enabled,
      isFalse,
    );

    await tester.enterText(
      find.descendant(of: blockDialog, matching: find.byType(TextField)).last,
      'BLOQUEAR',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirmar'));
    await tester.pumpAndSettle();

    expect(service.accessApplyCalls, 1);
    expect(find.text('Acesso operacional bloqueado.'), findsOneWidget);
    expect(find.textContaining('passwordHash'), findsNothing);
  });

  testWidgets(
    'Reativar acesso operacional exige dry-run e confirmacao correta',
    (tester) async {
      _setLargeViewport(tester);
      final service = _FakeReadOnlyApiService();
      await tester.pumpWidget(
        _adminRouterTestApp(
          service: service,
          initialLocation: '/companies/company-1/users',
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(Tab, 'Funcionarios'));
      await tester.pumpAndSettle();
      final employeesTableScroller = find
          .ancestor(
            of: find.byType(DataTable).first,
            matching: find.byType(SingleChildScrollView),
          )
          .first;
      await tester.drag(employeesTableScroller, const Offset(-2200, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Detalhes').last);
      await tester.pumpAndSettle();
      expect(find.text('Ex Operador'), findsWidgets);
      expect(find.text('Reativar acesso operacional'), findsOneWidget);

      await tester.tap(find.text('Reativar acesso operacional'));
      await tester.pumpAndSettle();
      final reactivateDialog = find.byType(AlertDialog).last;
      await tester.enterText(
        find
            .descendant(of: reactivateDialog, matching: find.byType(TextField))
            .first,
        'retorno autorizado',
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: reactivateDialog,
          matching: find.text('Executar dry-run'),
        ),
      );
      await tester.pumpAndSettle();

      expect(service.accessDryRunCalls, 1);
      expect(
        find.text('Reativacao operacional pode ser aplicada com seguranca.'),
        findsOneWidget,
      );
      expect(find.textContaining('REATIVAR'), findsWidgets);

      await tester.enterText(
        find
            .descendant(of: reactivateDialog, matching: find.byType(TextField))
            .last,
        'REATIVAR',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Confirmar'));
      await tester.pumpAndSettle();

      expect(service.accessApplyCalls, 1);
      expect(find.text('Acesso operacional reativado.'), findsOneWidget);
    },
  );

  testWidgets('OWNER protegido mostra bloqueio de acao moderna', (
    tester,
  ) async {
    _setLargeViewport(tester);
    await tester.pumpWidget(
      _adminRouterTestApp(
        service: _FakeReadOnlyApiService(),
        initialLocation: '/companies/company-1/users',
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(Tab, 'Usuarios'));
    await tester.pumpAndSettle();
    final usersTableScroller = find
        .ancestor(
          of: find.byType(DataTable).first,
          matching: find.byType(SingleChildScrollView),
        )
        .first;
    await tester.drag(usersTableScroller, const Offset(-1600, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Detalhes').first);
    await tester.pumpAndSettle();

    expect(find.text('Dona Tatuzin'), findsWidgets);
    expect(find.text('Bloquear acesso operacional bloqueado'), findsOneWidget);
    expect(find.text('Reativar acesso operacional'), findsNothing);
  });

  testWidgets('Sync Center renderiza abas read-only', (tester) async {
    _setLargeViewport(tester);
    await tester.pumpWidget(
      _adminRouterTestApp(
        service: _FakeReadOnlyApiService(),
        initialLocation: '/companies/company-1/sync',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Resumo'), findsOneWidget);
    expect(find.text('Eventos'), findsOneWidget);
    expect(find.text('Conflitos'), findsOneWidget);
    expect(find.text('Incidentes'), findsOneWidget);
    expect(find.text('Dispositivos'), findsOneWidget);
    expect(find.text('Auditoria'), findsOneWidget);
    expect(find.textContaining('Modo seguro/read-only'), findsWidgets);
    expect(find.textContaining('Reprocessar'), findsNothing);
    expect(find.textContaining('Arquivar legado'), findsNothing);
  });

  testWidgets('/sync/:companyId e /companies/:companyId/sync sao aliases', (
    tester,
  ) async {
    _setLargeViewport(tester);
    await tester.pumpWidget(
      _adminRouterTestApp(
        service: _FakeReadOnlyApiService(),
        initialLocation: '/sync/company-1',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Loja Moda Sul'), findsWidgets);
    expect(find.text('Eventos'), findsOneWidget);
    expect(find.textContaining('Modo seguro/read-only'), findsWidgets);
  });

  testWidgets('Sync global aplica filtro all real', (tester) async {
    _setLargeViewport(tester);
    final service = _FakeReadOnlyApiService();
    await tester.pumpWidget(
      _adminTestApp(service: service, child: const SyncCenterPage()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Com atencao'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Todas').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();

    expect(service.lastCompaniesQuery?.status, 'all');
  });

  testWidgets('Dispositivos usa inventario global sem filtrar atencao', (
    tester,
  ) async {
    _setLargeViewport(tester);
    final service = _FakeReadOnlyApiService();
    await tester.pumpWidget(
      _adminTestApp(service: service, child: const DevicesPage()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dispositivos e sessoes'), findsOneWidget);
    expect(find.text('MOBILE_APP'), findsWidgets);
    expect(find.text('ADMIN_WEB'), findsWidgets);
    expect(find.text('Loja Moda Sul'), findsWidgets);
    expect(find.text('Pendentes 1 / Falhas 3 / OPEN 2'), findsOneWidget);
    expect(service.lastDevicesQuery?.attention, isNull);
    expect(find.textContaining('client-instance-secret-long-id'), findsNothing);
    expect(find.textContaining('refresh-token-secret'), findsNothing);
    expect(find.textContaining('hash-secret'), findsNothing);
  });

  testWidgets('Dispositivos por empresa mostra sessoes e aviso read-only', (
    tester,
  ) async {
    _setLargeViewport(tester);
    final service = _FakeReadOnlyApiService();
    await tester.pumpWidget(
      _adminRouterTestApp(
        service: service,
        initialLocation: '/companies/company-1/devices',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dispositivos e sessoes da empresa'), findsOneWidget);
    expect(service.lastDevicesQuery?.companyId, 'company-1');
    expect(service.companySessionsFetchCount, 1);
    expect(find.text('Sessoes'), findsOneWidget);
    expect(find.text('Ativa'), findsWidgets);
    expect(
      find.textContaining('Acoes de revogar sessao e forcar logout'),
      findsOneWidget,
    );
    expect(find.textContaining('client-instance-secret-long-id'), findsNothing);
    expect(find.textContaining('refresh-token-secret'), findsNothing);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Atualizar'));
    await tester.pumpAndSettle();
    expect(service.devicesFetchCount, greaterThanOrEqualTo(2));
    expect(service.companySessionsFetchCount, greaterThanOrEqualTo(2));
  });

  testWidgets('Empresa 360 mostra card de dispositivos e sessoes', (
    tester,
  ) async {
    _setLargeViewport(tester);
    await tester.pumpWidget(
      _adminRouterTestApp(
        service: _FakeReadOnlyApiService(),
        initialLocation: '/companies/company-1',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dispositivos e sessoes'), findsWidgets);
    expect(find.text('Ver dispositivos e sessoes'), findsWidgets);
    expect(find.text('Com falha local'), findsWidgets);
  });

  testWidgets('Conflitos RESOLVED nao aparecem como pendentes', (tester) async {
    _setLargeViewport(tester);
    await tester.pumpWidget(
      _adminRouterTestApp(
        service: _FakeReadOnlyApiService(),
        initialLocation: '/companies/company-1/sync',
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(Tab, 'Conflitos'));
    await tester.pumpAndSettle();

    final openSection = find.text('Ativos: OPEN');
    final historySection = find.text('Historico: RESOLVED e IGNORED');
    expect(openSection, findsOneWidget);
    expect(historySection, findsOneWidget);
    expect(
      find.text('RESOLVED'),
      findsOneWidget,
      reason: 'RESOLVED deve aparecer apenas no historico.',
    );
    expect(find.text('OPEN'), findsWidgets);
  });

  testWidgets('Eventos mostra lista e detalhe read-only', (tester) async {
    _setLargeViewport(tester);
    await tester.pumpWidget(
      _adminRouterTestApp(
        service: _FakeReadOnlyApiService(),
        initialLocation: '/companies/company-1/sync',
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(Tab, 'Eventos'));
    await tester.pumpAndSettle();

    expect(find.text('stockDeduction'), findsOneWidget);
    expect(find.text('STOCK_VARIANT_NOT_FOUND'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Detalhes').first);
    await tester.pumpAndSettle();

    expect(find.text('Evento client-event-1'), findsOneWidget);
    expect(find.text('Payload preview'), findsOneWidget);
    expect(find.textContaining('Variante nao encontrada'), findsWidgets);
    expect(find.textContaining('Reprocessar'), findsNothing);
  });

  testWidgets('Dispositivos diferencia MOBILE_APP de ADMIN_WEB', (
    tester,
  ) async {
    _setLargeViewport(tester);
    await tester.pumpWidget(
      _adminRouterTestApp(
        service: _FakeReadOnlyApiService(),
        initialLocation: '/companies/company-1/sync',
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(Tab, 'Dispositivos'));
    await tester.pumpAndSettle();

    expect(find.text('MOBILE_APP'), findsOneWidget);
    expect(find.text('ADMIN_WEB'), findsOneWidget);
    expect(find.text('Pendentes locais'), findsOneWidget);
    expect(find.text('Falhas locais'), findsWidgets);
    expect(find.text('totalCents antigo'), findsOneWidget);
    expect(
      find.textContaining('Comandos de suporte sao enviados ao app'),
      findsOneWidget,
    );

    final deviceTableScroller = find
        .ancestor(
          of: find.byType(DataTable).first,
          matching: find.byType(SingleChildScrollView),
        )
        .last;
    await tester.drag(deviceTableScroller, const Offset(-1800, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Detalhes').first);
    await tester.pumpAndSettle();

    expect(find.text('Pendentes locais'), findsWidgets);
    expect(find.text('Detalhes seguros'), findsOneWidget);
    expect(find.text('operationalOrderItem'), findsWidgets);
    expect(find.text('Comandos de suporte'), findsOneWidget);
    expect(find.text('Recalcular status'), findsOneWidget);
    expect(find.text('Forcar pull da nuvem'), findsOneWidget);
    expect(find.text('Limpar conflitos resolvidos'), findsOneWidget);
    expect(find.text('Reparar eventos recuperaveis'), findsOneWidget);
    expect(find.text('Reprocessar falhas locais'), findsOneWidget);
    expect(
      find.text('Nenhum comando enviado para este device.'),
      findsOneWidget,
    );
  });

  testWidgets('comandos de suporte exigem dry-run e confirmacao correta', (
    tester,
  ) async {
    _setLargeViewport(tester);
    final service = _FakeReadOnlyApiService();
    await tester.pumpWidget(
      _adminRouterTestApp(
        service: service,
        initialLocation: '/companies/company-1/sync',
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(Tab, 'Dispositivos'));
    await tester.pumpAndSettle();
    final deviceTableScroller = find
        .ancestor(
          of: find.byType(DataTable).first,
          matching: find.byType(SingleChildScrollView),
        )
        .last;
    await tester.drag(deviceTableScroller, const Offset(-1800, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Detalhes').first);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Reprocessar falhas locais'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reprocessar falhas locais'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'reprocessar fila');
    await tester.tap(find.text('Executar dry-run'));
    await tester.pumpAndSettle();

    expect(service.supportDryRunCalls, 1);
    expect(
      find.text('Comando pode ser enviado com seguranca.'),
      findsOneWidget,
    );
    expect(find.text('Confirmacao esperada'), findsOneWidget);
    expect(find.text('REPROCESSAR'), findsWidgets);

    await tester.enterText(find.byType(TextField).last, 'ERRADO');
    await tester.pumpAndSettle();
    expect(
      find.text('Digite REPROCESSAR para liberar a confirmacao.'),
      findsWidgets,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Enviar comando'),
          )
          .enabled,
      isFalse,
    );

    await tester.enterText(find.byType(TextField).last, 'REPROCESSAR');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Enviar comando'));
    await tester.pumpAndSettle();

    expect(service.supportCreateCalls, 1);
    expect(find.text('PENDING'), findsOneWidget);
    expect(find.text('reprocessar fila'), findsOneWidget);
  });

  testWidgets('refresh chama providers por empresa novamente', (tester) async {
    _setLargeViewport(tester);
    final service = _FakeReadOnlyApiService();
    await tester.pumpWidget(
      _adminRouterTestApp(
        service: service,
        initialLocation: '/companies/company-1/sync',
      ),
    );
    await tester.pumpAndSettle();
    final initialHealthFetches = service.companyHealthFetchCount;

    await tester.tap(find.widgetWithText(FilledButton, 'Atualizar'));
    await tester.pumpAndSettle();

    expect(service.companyHealthFetchCount, greaterThan(initialHealthFetches));
  });

  testWidgets('Sync Center por empresa exibe estados vazio e erro', (
    tester,
  ) async {
    _setLargeViewport(tester);
    await tester.pumpWidget(
      _adminRouterTestApp(
        service: _FakeReadOnlyApiService(emptyCompanySync: true),
        initialLocation: '/companies/company-1/sync',
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(Tab, 'Eventos'));
    await tester.pumpAndSettle();
    expect(find.text('Nenhum evento encontrado.'), findsOneWidget);

    await tester.pumpWidget(
      _adminRouterTestApp(
        service: _FakeReadOnlyApiService(throwCompanySync: true),
        initialLocation: '/companies/company-1/sync',
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Nao foi possivel carregar o console de sync'),
      findsOneWidget,
    );
    expect(find.textContaining('falha controlada'), findsOneWidget);
  });

  testWidgets('Licenca mostra acoes placeholder', (tester) async {
    _setLargeViewport(tester);
    final service = _FakeReadOnlyApiService();
    await tester.pumpWidget(
      _adminRouterTestApp(
        service: service,
        initialLocation: '/licenses/company-1',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Plano ativo'), findsWidgets);
    expect(find.text('Plano ativo: PRO'), findsOneWidget);
    expect(find.text('Plano ativo: BASIC'), findsNothing);
    expect(find.text('Mudanca pendente'), findsWidgets);
    expect(find.text('Cancelamento agendado'), findsWidgets);
    expect(find.text('pre_..._7890'), findsWidgets);
    expect(find.text('preapproval-secret-full-id'), findsNothing);
    expect(find.text('checkout-secret-reference-123456789'), findsNothing);
    expect(
      find.text(
        'Faturas administrativas serao exibidas aqui quando o endpoint estiver disponivel.',
      ),
      findsWidgets,
    );
    expect(find.text('Eventos de billing'), findsOneWidget);
    expect(find.text('payment.created'), findsOneWidget);
    expect(find.text('Sessoes de checkout'), findsOneWidget);
    expect(find.text('Tentativa pendente'), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, 'Extensao emergencial'),
      findsOneWidget,
    );
    expect(find.textContaining('Trocar plano'), findsOneWidget);
    expect(find.textContaining('Suspender'), findsOneWidget);
    expect(find.textContaining('Reativar'), findsOneWidget);
    expect(find.textContaining('Reconciliar Mercado Pago'), findsOneWidget);
    expect(find.text('Ver matriz de planos'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.textContaining('Trocar plano'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.textContaining('Trocar plano'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Acao administrativa sera implementada em fase posterior com dry-run, confirmacao explicita e auditoria.',
      ),
      findsOneWidget,
    );
    expect(service.mutableBillingCalls, 0);
  });

  test('preview seguro de billing remove chaves e valores sensiveis', () {
    final preview = formatSafeLicenseBillingDetails({
      'Authorization': 'Bearer secret',
      'headers': {'x-signature': 'abc'},
      'card': {'cvv': '123'},
      'public': 'ok',
    });

    expect(preview, contains('public'));
    expect(preview, contains('ok'));
    expect(preview, isNot(contains('Authorization')));
    expect(preview, isNot(contains('Bearer secret')));
    expect(preview, isNot(contains('headers')));
    expect(preview, isNot(contains('x-signature')));
    expect(preview, isNot(contains('cvv')));
  });

  testWidgets('/companies/:companyId/license abre o mesmo detalhe read-only', (
    tester,
  ) async {
    _setLargeViewport(tester);
    await tester.pumpWidget(
      _adminRouterTestApp(
        service: _FakeReadOnlyApiService(),
        initialLocation: '/companies/company-1/license',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Loja Moda Sul'), findsWidgets);
    expect(find.text('Plano ativo: PRO'), findsOneWidget);
    expect(find.text('Mudanca pendente: BASIC'), findsOneWidget);
    expect(find.text('preapproval-secret-full-id'), findsNothing);
    expect(find.textContaining('Reconciliar Mercado Pago'), findsOneWidget);
  });

  testWidgets('Licenca mostra estados vazios de historico billing', (
    tester,
  ) async {
    _setLargeViewport(tester);
    await tester.pumpWidget(
      _adminRouterTestApp(
        service: _FakeReadOnlyApiService(emptyBillingHistory: true),
        initialLocation: '/licenses/company-1',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nenhum evento de billing encontrado.'), findsOneWidget);
    expect(find.text('Nenhuma sessao de checkout encontrada.'), findsOneWidget);
    expect(
      find.text(
        'Faturas administrativas serao exibidas aqui quando o endpoint estiver disponivel.',
      ),
      findsWidgets,
    );
  });

  testWidgets('Planos mostra matriz', (tester) async {
    _setLargeViewport(tester);
    final service = _FakeReadOnlyApiService();
    await tester.pumpWidget(
      _adminRouterTestApp(service: service, initialLocation: '/plans'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Planos e recursos'), findsWidgets);
    expect(find.text('Matriz de features'), findsOneWidget);
    expect(find.text('FREE'), findsWidgets);
    expect(find.text('BASIC'), findsWidgets);
    expect(find.text('PRO'), findsWidgets);
    expect(find.textContaining('license.plan e a fonte real'), findsOneWidget);
    expect(
      find.textContaining('pendingPlan nao libera recursos'),
      findsOneWidget,
    );
    expect(find.text('employees'), findsOneWidget);
    expect(find.text('Funcionarios PRO'), findsOneWidget);
    expect(find.text('Owner web'), findsOneWidget);
    expect(find.text('Limites por plano'), findsOneWidget);
    expect(find.text('Empresas por plano'), findsOneWidget);
    expect(find.text('Como pendingPlan'), findsOneWidget);
    expect(find.textContaining('Editar preco'), findsOneWidget);
    expect(find.textContaining('Arquivar plano'), findsOneWidget);
    expect(find.textContaining('Duplicar plano'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('Editar preco'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.textContaining('Editar preco'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Acao administrativa sera implementada em fase posterior com dry-run, confirmacao explicita e auditoria.',
      ),
      findsWidgets,
    );
    expect(service.mutableBillingCalls, 0);
    expect(service.supportDryRunCalls, 0);
    expect(service.supportCreateCalls, 0);
  });

  testWidgets('Licenca navega para matriz de planos', (tester) async {
    _setLargeViewport(tester);
    await tester.pumpWidget(
      _adminRouterTestApp(
        service: _FakeReadOnlyApiService(),
        initialLocation: '/companies/company-1/license',
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ver matriz de planos'));
    await tester.pumpAndSettle();
    expect(find.text('Planos e recursos'), findsWidgets);
  });

  testWidgets('/audit renderiza auditoria global read-only', (tester) async {
    _setLargeViewport(tester);
    final service = _FakeReadOnlyApiService();
    await tester.pumpWidget(
      _adminRouterTestApp(
        service: service,
        initialLocation: '/audit?companyId=company-1',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Auditoria global'), findsOneWidget);
    expect(find.text('Empresa'), findsWidgets);
    expect(find.text('Ator'), findsWidgets);
    expect(find.text('Categoria'), findsWidgets);
    expect(find.text('Busca textual'), findsOneWidget);
    expect(find.text('Extensao emergencial'), findsOneWidget);
    expect(find.text('Bloqueio de acesso operacional'), findsOneWidget);
    expect(find.text('Comando de suporte criado'), findsOneWidget);
    expect(service.lastAuditQuery?.companyId, 'company-1');
  });

  testWidgets('/audit filtra por categoria e mostra detalhes sanitizados', (
    tester,
  ) async {
    _setLargeViewport(tester);
    final service = _FakeReadOnlyApiService();
    await tester.pumpWidget(
      _adminRouterTestApp(
        service: service,
        initialLocation: '/audit?companyId=company-1&category=access',
      ),
    );
    await tester.pumpAndSettle();

    expect(service.lastAuditQuery?.category, 'access');
    expect(find.text('Bloqueio de acesso operacional'), findsOneWidget);
    expect(find.text('Extensao emergencial'), findsNothing);

    await tester.tap(find.widgetWithText(TextButton, 'Detalhes').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Before sanitizado'), findsOneWidget);
    expect(find.textContaining('campo_sensivel_removido'), findsWidgets);
    expect(find.textContaining('passwordHash'), findsNothing);
    expect(find.textContaining('inviteTokenHash'), findsNothing);
    expect(find.textContaining('preapproval-secret-full-id'), findsNothing);
    expect(find.textContaining('Authorization'), findsNothing);
  });

  testWidgets('CTA de empresa navega para auditoria filtrada', (tester) async {
    _setLargeViewport(tester);
    final service = _FakeReadOnlyApiService();
    await tester.pumpWidget(
      _adminRouterTestApp(
        service: service,
        initialLocation: '/companies/company-1',
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ver auditoria da empresa'));
    await tester.pumpAndSettle();
    expect(find.text('Auditoria global'), findsOneWidget);
    expect(service.lastAuditQuery?.companyId, 'company-1');
  });

  testWidgets('estados vazio e erro funcionam', (tester) async {
    _setLargeViewport(tester);
    await tester.pumpWidget(
      _adminTestApp(
        service: _FakeReadOnlyApiService(emptyLicenses: true),
        child: const LicensesPage(),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Nenhuma licenca encontrada para os filtros.'),
      findsOneWidget,
    );

    await tester.pumpWidget(
      _adminTestApp(
        service: _FakeReadOnlyApiService(throwDashboard: true),
        child: const DashboardPage(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Nao foi possivel carregar o dashboard'), findsOneWidget);
    expect(find.textContaining('falha controlada'), findsOneWidget);

    await tester.pumpWidget(
      _adminTestApp(
        service: _FakeReadOnlyApiService(emptyPlans: true),
        child: const PlansPage(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Nenhum plano retornado pelo backend.'), findsOneWidget);

    await tester.pumpWidget(
      _adminTestApp(
        service: _FakeReadOnlyApiService(throwPlans: true),
        child: const PlansPage(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Nao foi possivel carregar planos'), findsOneWidget);
    expect(find.textContaining('falha controlada'), findsOneWidget);
  });
}

void _setLargeViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1800, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Widget _adminTestApp({
  required AdminApiService service,
  required Widget child,
}) {
  return ProviderScope(
    overrides: [adminApiServiceProvider.overrideWithValue(service)],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

Widget _adminRouterTestApp({
  required AdminApiService service,
  required String initialLocation,
}) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/companies/:companyId/sync',
        builder: (context, state) => Scaffold(
          body: SyncCompanyPage(
            companyId: state.pathParameters['companyId'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: '/companies/:companyId',
        builder: (context, state) => Scaffold(
          body: CompanyDetailPage(
            companyId: state.pathParameters['companyId'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: '/companies/:companyId/users',
        builder: (context, state) => Scaffold(
          body: CompanyUsersPage(
            companyId: state.pathParameters['companyId'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: '/companies/:companyId/devices',
        builder: (context, state) => Scaffold(
          body: DevicesPage(companyId: state.pathParameters['companyId'] ?? ''),
        ),
      ),
      GoRoute(
        path: '/companies/:companyId/sessions',
        builder: (context, state) => Scaffold(
          body: DevicesPage(companyId: state.pathParameters['companyId'] ?? ''),
        ),
      ),
      GoRoute(
        path: '/companies/:companyId/employees',
        builder: (context, state) => Scaffold(
          body: CompanyUsersPage(
            companyId: state.pathParameters['companyId'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: '/sync/:companyId',
        builder: (context, state) => Scaffold(
          body: SyncCompanyPage(
            companyId: state.pathParameters['companyId'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: '/licenses/:companyId',
        builder: (context, state) => Scaffold(
          body: LicenseCompanyPage(
            companyId: state.pathParameters['companyId'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: '/companies/:companyId/license',
        builder: (context, state) => Scaffold(
          body: LicenseCompanyPage(
            companyId: state.pathParameters['companyId'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: '/plans',
        builder: (context, state) => const Scaffold(body: PlansPage()),
      ),
      GoRoute(
        path: '/audit',
        builder: (context, state) => Scaffold(
          body: AuditPage(initialQueryParameters: state.uri.queryParameters),
        ),
      ),
      GoRoute(
        path: '/sync/:companyId/events/:eventId',
        builder: (context, state) => Scaffold(
          body: SyncEventDetailPage(
            companyId: state.pathParameters['companyId'] ?? '',
            eventId: state.pathParameters['eventId'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: '/sync/:companyId/conflicts/:conflictId',
        builder: (context, state) => Scaffold(
          body: SyncConflictDetailPage(
            companyId: state.pathParameters['companyId'] ?? '',
            conflictId: state.pathParameters['conflictId'] ?? '',
          ),
        ),
      ),
    ],
  );

  return ProviderScope(
    overrides: [adminApiServiceProvider.overrideWithValue(service)],
    child: MaterialApp.router(routerConfig: router),
  );
}

class _FakeReadOnlyApiService extends AdminApiService {
  _FakeReadOnlyApiService({
    this.emptyLicenses = false,
    this.emptyBillingHistory = false,
    this.emptyPlans = false,
    this.throwDashboard = false,
    this.throwPlans = false,
    this.emptyCompanySync = false,
    this.throwCompanySync = false,
  }) : super(
         apiClient: AdminApiClient(
           baseUrl: 'https://api.test/api',
           authStorage: AdminAuthStorage(),
           httpClient: MockClient((request) async {
             throw UnimplementedError(request.url.toString());
           }),
         ),
         authStorage: AdminAuthStorage(),
       );

  final bool emptyLicenses;
  final bool emptyBillingHistory;
  final bool emptyPlans;
  final bool throwDashboard;
  final bool throwPlans;
  final bool emptyCompanySync;
  final bool throwCompanySync;
  AdminSyncCenterCompaniesQuery? lastCompaniesQuery;
  int companyHealthFetchCount = 0;
  int supportDryRunCalls = 0;
  int supportCreateCalls = 0;
  int accessDryRunCalls = 0;
  int accessApplyCalls = 0;
  int mutableBillingCalls = 0;
  int auditFetchCount = 0;
  int devicesFetchCount = 0;
  int companySessionsFetchCount = 0;
  AdminAuditQuery? lastAuditQuery;
  AdminDevicesQuery? lastDevicesQuery;
  final supportCommands = <Map<String, dynamic>>[];

  @override
  Future<AdminDashboardSnapshot> fetchDashboard() async {
    if (throwDashboard) {
      throw const AdminApiException(message: 'falha controlada');
    }
    return AdminDashboardSnapshot(
      companies: [AdminCompanySummary.fromMap(_companyMap())],
      auditSummary: AdminAuditSummary.fromMap(_auditSummaryMap()),
      syncSummary: AdminSyncSummary.fromMap(_syncSummaryMap()),
    );
  }

  @override
  Future<AdminAuditLogPage> fetchAuditLogs({AdminAuditQuery? query}) async {
    auditFetchCount++;
    lastAuditQuery = query;
    if (throwDashboard) {
      throw const AdminApiException(message: 'falha controlada');
    }
    final category = query?.category;
    final companyId = query?.companyId;
    final items = _auditLogItems()
        .where((item) {
          if (category != null && category.trim().isNotEmpty) {
            return item['category'] == category;
          }
          return true;
        })
        .where((item) {
          if (companyId != null && companyId.trim().isNotEmpty) {
            return item['companyId'] == companyId;
          }
          return true;
        })
        .toList(growable: false);
    return AdminAuditLogPage.fromMap({
      'items': items,
      'pagination': {
        'page': query?.page ?? 1,
        'pageSize': query?.pageSize ?? 20,
        'total': items.length,
        'count': items.length,
        'hasNext': false,
        'hasPrevious': false,
      },
      'overview': {
        'totalEvents': items.length,
        'countsByCategory': {
          'license': items
              .where((item) => item['category'] == 'license')
              .length,
          'billing': items
              .where((item) => item['category'] == 'billing')
              .length,
          'access': items.where((item) => item['category'] == 'access').length,
          'sync': items.where((item) => item['category'] == 'sync').length,
        },
        'failures': items.where((item) => item['status'] == 'failed').length,
        'last7Days': items.length,
      },
      'filters': query?.toQueryParameters() ?? const <String, String>{},
      'sort': {'by': 'createdAt', 'direction': 'desc'},
    });
  }

  @override
  Future<AdminCompanyDetail> fetchCompanyDetail(String companyId) async {
    return AdminCompanyDetail.fromMap({
      'company': _companyMap(),
      'memberships': [
        {
          'id': 'membership-1',
          'role': 'OWNER',
          'isDefault': true,
          'createdAt': '2026-01-01T00:00:00.000Z',
          'updatedAt': '2026-05-24T12:00:00.000Z',
          'user': {
            'id': 'user-1',
            'name': 'Operador Local',
            'email': 'operador@tatuzin.test',
            'isActive': true,
            'isPlatformAdmin': false,
          },
        },
      ],
      'sessions': [_mobileSessionMap(), _adminSessionMap()],
    });
  }

  @override
  Future<AdminPlansOverview> fetchPlansOverview() async {
    if (throwPlans) {
      throw const AdminApiException(message: 'falha controlada');
    }
    if (emptyPlans) {
      return AdminPlansOverview.fromMap({
        'items': const [],
        'features': const [],
        'usageSummary': const {},
        'rules': const {
          'entitlementSource': 'license.plan',
          'pendingPlanReleasesFeatures': false,
        },
      });
    }
    return AdminPlansOverview.fromMap(_plansOverviewMap());
  }

  @override
  Future<AdminCompanyAccessSummary> fetchCompanyAccessSummary(
    String companyId,
  ) async {
    if (throwCompanySync) {
      throw const AdminApiException(message: 'falha controlada');
    }
    if (emptyCompanySync) {
      return AdminCompanyAccessSummary.fromMap({
        'company': {
          'id': companyId,
          'name': 'Loja Moda Sul',
          'slug': 'loja-moda-sul',
          'license': {'plan': 'PRO', 'status': 'ACTIVE'},
        },
        'summary': const {},
        'users': const [],
        'employees': const [],
        'permissionsCatalog': const [],
        'devices': const [],
        'audit': const [],
      });
    }
    return AdminCompanyAccessSummary.fromMap(_accessSummaryMap(companyId));
  }

  @override
  Future<AdminPaginatedResult<AdminDeviceInventoryItem>> fetchDevices({
    required AdminDevicesQuery query,
  }) async {
    devicesFetchCount++;
    lastDevicesQuery = query;
    if (throwCompanySync) {
      throw const AdminApiException(message: 'falha controlada');
    }
    final allItems = [_deviceInventoryMap(), _adminDeviceInventoryMap()];
    final filtered = allItems.where((item) {
      if (query.companyId != null && item['companyId'] != query.companyId) {
        return false;
      }
      if (query.clientType != 'all' && item['clientType'] != query.clientType) {
        return false;
      }
      if (query.attention == true) {
        final diagnostic = item['diagnostic'] as Map<String, dynamic>?;
        return (diagnostic?['pendingCount'] as int? ?? 0) > 0 ||
            (diagnostic?['failedCount'] as int? ?? 0) > 0 ||
            (diagnostic?['openConflictCount'] as int? ?? 0) > 0;
      }
      return true;
    }).toList(growable: false);
    return AdminPaginatedResult<AdminDeviceInventoryItem>(
      items: filtered.map(AdminDeviceInventoryItem.fromMap).toList(),
      pagination: AdminPaginationMeta(
        page: query.page,
        pageSize: query.pageSize,
        total: filtered.length,
        count: filtered.length,
        hasNext: false,
        hasPrevious: false,
      ),
      filters: query.toQueryParameters(),
      sort: const AdminSortMeta(by: 'lastSeenAt', direction: 'desc'),
    );
  }

  @override
  Future<List<AdminDeviceSession>> fetchCompanySessions(String companyId) async {
    companySessionsFetchCount++;
    if (throwCompanySync) {
      throw const AdminApiException(message: 'falha controlada');
    }
    return [
      AdminDeviceSession.fromMap(_mobileSessionMap()),
      AdminDeviceSession.fromMap(_adminSessionMap()),
    ];
  }

  @override
  Future<AdminAccessActionDryRun> dryRunAccessBlock({
    required String companyId,
    required String targetId,
    required String targetType,
    required String reason,
    String? note,
  }) async {
    accessDryRunCalls++;
    final isOwner = targetId.contains('owner');
    return AdminAccessActionDryRun.fromMap({
      'allowed': !isOwner,
      'expectedConfirmationText': 'BLOQUEAR',
      'summary': isOwner
          ? 'Acesso operacional protegido nao pode ser bloqueado.'
          : 'Bloqueio operacional pode ser aplicado com seguranca.',
      'risks': const [
        'O usuario perde acesso operacional nas rotas protegidas pelo contexto da empresa.',
        'Esta acao nao revoga sessoes ou JWT nesta fase.',
        'Esta acao nao apaga vendas, pedidos, estoque ou historico.',
      ],
      'blockers': isOwner
          ? const ['OWNER protegido nao pode ser bloqueado por esta acao.']
          : const [],
      'currentAccess': {
        'employeeProfileId': targetId,
        'status': 'ACTIVE',
        'passwordHash': 'hash-secret',
      },
      'proposedChange': {'status': 'DISABLED'},
    });
  }

  @override
  Future<AdminAccessActionResult> applyAccessBlock({
    required String companyId,
    required String targetId,
    required String targetType,
    required String reason,
    required String confirmationText,
    String? note,
  }) async {
    accessApplyCalls++;
    return AdminAccessActionResult.fromMap({
      'success': true,
      'message': 'Acesso operacional bloqueado.',
      'auditId': 'access-audit-block',
      'updatedAccess': {
        'employeeProfileId': targetId,
        'status': 'DISABLED',
        'passwordHash': 'hash-secret',
      },
    });
  }

  @override
  Future<AdminAccessActionDryRun> dryRunAccessReactivate({
    required String companyId,
    required String targetId,
    required String targetType,
    required String reason,
    String? note,
  }) async {
    accessDryRunCalls++;
    return AdminAccessActionDryRun.fromMap({
      'allowed': true,
      'expectedConfirmationText': 'REATIVAR',
      'summary': 'Reativacao operacional pode ser aplicada com seguranca.',
      'risks': const [
        'O usuario volta a acessar operacionalmente conforme papel e permissoes existentes.',
        'Esta acao nao altera senha.',
      ],
      'blockers': const [],
      'currentAccess': {'employeeProfileId': targetId, 'status': 'DISABLED'},
      'proposedChange': {'status': 'ACTIVE'},
    });
  }

  @override
  Future<AdminAccessActionResult> applyAccessReactivate({
    required String companyId,
    required String targetId,
    required String targetType,
    required String reason,
    required String confirmationText,
    String? note,
  }) async {
    accessApplyCalls++;
    return AdminAccessActionResult.fromMap({
      'success': true,
      'message': 'Acesso operacional reativado.',
      'auditId': 'access-audit-reactivate',
      'updatedAccess': {'employeeProfileId': targetId, 'status': 'ACTIVE'},
    });
  }

  @override
  Future<AdminPaginatedResult<AdminCompanySummary>> fetchCompanies({
    AdminCompaniesQuery? query,
  }) async {
    return AdminPaginatedResult<AdminCompanySummary>(
      items: [AdminCompanySummary.fromMap(_companyMap())],
      pagination: const AdminPaginationMeta(
        page: 1,
        pageSize: 20,
        total: 1,
        count: 1,
        hasNext: false,
        hasPrevious: false,
      ),
      filters: const {},
      sort: const AdminSortMeta(by: 'createdAt', direction: 'desc'),
    );
  }

  @override
  Future<AdminPaginatedResult<AdminLicenseSnapshot>> fetchLicenses({
    AdminLicensesQuery? query,
  }) async {
    return AdminPaginatedResult<AdminLicenseSnapshot>(
      items: emptyLicenses ? [] : [AdminLicenseSnapshot.fromMap(_licenseMap())],
      pagination: AdminPaginationMeta(
        page: 1,
        pageSize: 20,
        total: emptyLicenses ? 0 : 1,
        count: emptyLicenses ? 0 : 1,
        hasNext: false,
        hasPrevious: false,
      ),
      filters: const {},
      sort: const AdminSortMeta(by: 'expiresAt', direction: 'asc'),
    );
  }

  @override
  Future<AdminPaginatedResult<AdminBillingCompanySummary>>
  fetchBillingCompanies({AdminBillingCompaniesQuery? query}) async {
    return AdminPaginatedResult<AdminBillingCompanySummary>(
      items: emptyLicenses
          ? []
          : [
              AdminBillingCompanySummary.fromMap({
                'companyId': 'company-1',
                'companyName': 'Loja Moda Sul',
                'plan': 'PRO',
                'licenseStatus': 'ACTIVE',
                'billingProvider': 'mercadopago',
                'hasProviderSubscription': true,
                'maskedProviderSubscriptionId': 'pre_..._7890',
                'currentPeriodEnd': '2026-06-30T00:00:00.000Z',
                'nextPaymentDate': '2026-06-30T00:00:00.000Z',
                'pendingPlan': 'BASIC',
                'cancelAtPeriodEnd': true,
                'billingSubscriptionStatus': 'authorized',
              }),
            ],
      pagination: AdminPaginationMeta(
        page: 1,
        pageSize: 20,
        total: emptyLicenses ? 0 : 1,
        count: emptyLicenses ? 0 : 1,
        hasNext: false,
        hasPrevious: false,
      ),
      filters: const {},
      sort: const AdminSortMeta(by: 'currentPeriodEnd', direction: 'asc'),
    );
  }

  @override
  Future<AdminBillingCompanyStatus> fetchBillingCompanyStatus(
    String companyId,
  ) async {
    return AdminBillingCompanyStatus.fromMap({
      'company': {'id': companyId, 'name': 'Loja Moda Sul'},
      'license': {
        'plan': 'PRO',
        'status': 'ACTIVE',
        'startsAt': '2026-01-01T00:00:00.000Z',
        'expiresAt': '2026-12-31T00:00:00.000Z',
        'maxDevices': 100,
        'syncEnabled': true,
        'providerSubscriptionId': 'preapproval-secret-full-id',
        'currentPeriodEnd': '2026-06-30T00:00:00.000Z',
        'nextPaymentDate': '2026-06-30T00:00:00.000Z',
        'pendingPlan': 'BASIC',
        'pendingPlanRequestedAt': '2026-05-20T00:00:00.000Z',
        'billingSubscriptionStatus': 'authorized',
        'createdAt': '2026-01-01T00:00:00.000Z',
        'updatedAt': '2026-05-24T00:00:00.000Z',
      },
      'billing': {
        'provider': 'mercadopago',
        'hasProviderSubscription': true,
        'providerSubscriptionId': 'preapproval-secret-full-id',
        'maskedProviderSubscriptionId': 'pre_..._7890',
        'currentPeriodStart': '2026-05-30T00:00:00.000Z',
        'currentPeriodEnd': '2026-06-30T00:00:00.000Z',
        'nextPaymentDate': '2026-06-30T00:00:00.000Z',
        'cancelAtPeriodEnd': true,
        'cancelRequestedAt': '2026-05-25T00:00:00.000Z',
        'pendingPlan': 'BASIC',
        'billingSubscriptionStatus': 'authorized',
      },
      'events': emptyBillingHistory
          ? const []
          : [
              {
                'id': 'billing-event-1',
                'provider': 'mercadopago',
                'eventType': 'payment.created',
                'providerEventId': 'event-secret-full-id-123456789',
                'status': 'processed',
                'payload': {'Authorization': 'Bearer secret', 'public': 'ok'},
              },
            ],
      'invoices': const [],
      'checkoutSessions': emptyBillingHistory
          ? const []
          : [
              {
                'id': 'checkout-1',
                'plan': 'BASIC',
                'billingCycle': 'monthly',
                'status': 'pending',
                'provider': 'mercadopago',
                'providerReference': 'checkout-secret-reference-123456789',
                'createdAt': '2026-05-24T00:00:00.000Z',
                'updatedAt': '2026-05-24T00:00:00.000Z',
              },
            ],
    });
  }

  @override
  Future<AdminPaginatedResult<AdminBillingEvent>> fetchBillingEvents({
    required AdminBillingListQuery query,
  }) async {
    return AdminPaginatedResult<AdminBillingEvent>(
      items: emptyBillingHistory
          ? []
          : [
              AdminBillingEvent.fromMap({
                'id': 'billing-event-1',
                'provider': 'mercadopago',
                'eventType': 'payment.created',
                'providerEventId': 'event-secret-full-id-123456789',
                'status': 'processed',
                'payload': {'Authorization': 'Bearer secret', 'public': 'ok'},
              }),
            ],
      pagination: AdminPaginationMeta(
        page: 1,
        pageSize: 20,
        total: emptyBillingHistory ? 0 : 1,
        count: emptyBillingHistory ? 0 : 1,
        hasNext: false,
        hasPrevious: false,
      ),
      filters: const {},
      sort: const AdminSortMeta(by: 'createdAt', direction: 'desc'),
    );
  }

  @override
  Future<AdminPaginatedResult<AdminBillingCheckoutSession>>
  fetchBillingCheckoutSessions({required AdminBillingListQuery query}) async {
    return AdminPaginatedResult<AdminBillingCheckoutSession>(
      items: emptyBillingHistory
          ? []
          : [
              AdminBillingCheckoutSession.fromMap({
                'id': 'checkout-1',
                'plan': 'BASIC',
                'billingCycle': 'monthly',
                'status': 'pending',
                'provider': 'mercadopago',
                'providerReference': 'checkout-secret-reference-123456789',
                'createdAt': '2026-05-24T00:00:00.000Z',
                'updatedAt': '2026-05-24T00:00:00.000Z',
              }),
            ],
      pagination: AdminPaginationMeta(
        page: 1,
        pageSize: 20,
        total: emptyBillingHistory ? 0 : 1,
        count: emptyBillingHistory ? 0 : 1,
        hasNext: false,
        hasPrevious: false,
      ),
      filters: const {},
      sort: const AdminSortMeta(by: 'createdAt', direction: 'desc'),
    );
  }

  @override
  Future<AdminPaginatedResult<AdminBillingAuditLog>> fetchBillingAuditLogs({
    required AdminBillingListQuery query,
  }) async {
    return AdminPaginatedResult<AdminBillingAuditLog>(
      items: emptyBillingHistory
          ? []
          : [
              AdminBillingAuditLog.fromMap({
                'id': 'billing-audit-1',
                'action': 'license.emergency_extension',
                'reason': 'Atendimento emergencial',
                'actorUserId': 'admin-user-123456789',
                'actorName': 'Admin Suporte',
                'companyId': query.companyId,
                'before': {
                  'expiresAt': '2026-05-20T00:00:00.000Z',
                  'providerSubscriptionId': 'preapproval-secret-full-id',
                },
                'after': {
                  'expiresAt': '2026-05-27T00:00:00.000Z',
                  'providerSubscriptionId': 'preapproval-secret-full-id',
                },
                'metadata': {'Authorization': 'Bearer secret'},
                'createdAt': '2026-05-25T00:00:00.000Z',
              }),
            ],
      pagination: AdminPaginationMeta(
        page: 1,
        pageSize: 20,
        total: emptyBillingHistory ? 0 : 1,
        count: emptyBillingHistory ? 0 : 1,
        hasNext: false,
        hasPrevious: false,
      ),
      filters: const {},
      sort: const AdminSortMeta(by: 'createdAt', direction: 'desc'),
    );
  }

  @override
  Future<AdminLicenseSnapshot> updateLicense({
    required String companyId,
    required String plan,
    required String status,
    required DateTime? startsAt,
    required DateTime? expiresAt,
    required bool syncEnabled,
    required int? maxDevices,
  }) async {
    mutableBillingCalls++;
    throw StateError('updateLicense nao deveria ser chamado');
  }

  @override
  Future<AdminBillingActionResult> refreshBillingCompany({
    required String companyId,
    required String reason,
  }) async {
    mutableBillingCalls++;
    throw StateError('refreshBillingCompany nao deveria ser chamado');
  }

  @override
  Future<AdminBillingActionResult> forceBillingPlan({
    required String companyId,
    required String plan,
    required String reason,
    String? status,
    DateTime? currentPeriodEnd,
    bool clearProvider = false,
  }) async {
    mutableBillingCalls++;
    throw StateError('forceBillingPlan nao deveria ser chamado');
  }

  @override
  Future<AdminBillingActionResult> cancelBillingLocal({
    required String companyId,
    required String reason,
    required String effective,
  }) async {
    mutableBillingCalls++;
    throw StateError('cancelBillingLocal nao deveria ser chamado');
  }

  @override
  Future<AdminPaginatedResult<AdminSyncCenterCompany>>
  fetchSyncCenterCompanies({AdminSyncCenterCompaniesQuery? query}) async {
    lastCompaniesQuery = query;
    return AdminPaginatedResult<AdminSyncCenterCompany>(
      items: [AdminSyncCenterCompany.fromMap(_syncCompanyMap())],
      pagination: const AdminPaginationMeta(
        page: 1,
        pageSize: 20,
        total: 1,
        count: 1,
        hasNext: false,
        hasPrevious: false,
      ),
      filters: const {},
      sort: const AdminSortMeta(by: 'companyName', direction: 'asc'),
    );
  }

  @override
  Future<AdminSyncCenterCompanySummary> fetchSyncCenterCompanySummary(
    String companyId,
  ) async {
    return AdminSyncCenterCompanySummary.fromMap({
      'company': {
        'companyId': companyId,
        'companyName': 'Loja Moda Sul',
        'plan': 'PRO',
      },
      'syncState': {
        'currentVersion': '42',
        'serverFirstSnapshotVersion': '40',
        'updatedAt': '2026-05-24T12:00:00.000Z',
      },
      'eventStatusCounts': {
        'accepted': 10,
        'duplicate': 1,
        'pending': 2,
        'conflict': 1,
        'failed': 1,
        'rejected': 0,
      },
      'entityOperationStatusCounts': const [],
      'conflictCounts': [
        {
          'code': 'STOCK_VARIANT_NOT_FOUND',
          'entity': 'stockDeduction',
          'status': 'open',
          'count': 1,
        },
        {
          'code': 'OLD_CONFLICT',
          'entity': 'cashSession',
          'status': 'resolved',
          'count': 1,
        },
      ],
      'incidentCounts': const [],
      'latestEvents': [_eventMap()],
      'latestConflicts': [_openConflictMap(), _resolvedConflictMap()],
      'latestIncidents': [
        {
          'id': 'incident-1',
          'code': 'SYNC_FAILED',
          'message': 'Falha de materializacao.',
          'severity': 'error',
          'createdAt': '2026-05-24T12:00:00.000Z',
        },
      ],
      'recommendation': 'Existe problema ativo.',
      'requiresReview': true,
    });
  }

  @override
  Future<AdminPaginatedResult<AdminSyncCenterEvent>> fetchSyncCenterEvents({
    required AdminSyncCenterEventsQuery query,
  }) async {
    return AdminPaginatedResult<AdminSyncCenterEvent>(
      items: [AdminSyncCenterEvent.fromMap(_eventMap())],
      pagination: const AdminPaginationMeta(
        page: 1,
        pageSize: 20,
        total: 1,
        count: 1,
        hasNext: false,
        hasPrevious: false,
      ),
      filters: const {},
      sort: const AdminSortMeta(by: 'createdAt', direction: 'desc'),
    );
  }

  @override
  Future<AdminPaginatedResult<AdminSyncCenterConflict>>
  fetchSyncCenterConflicts({
    required AdminSyncCenterConflictsQuery query,
  }) async {
    return AdminPaginatedResult<AdminSyncCenterConflict>(
      items: [AdminSyncCenterConflict.fromMap(_openConflictMap())],
      pagination: const AdminPaginationMeta(
        page: 1,
        pageSize: 20,
        total: 1,
        count: 1,
        hasNext: false,
        hasPrevious: false,
      ),
      filters: const {},
      sort: const AdminSortMeta(by: 'createdAt', direction: 'desc'),
    );
  }

  @override
  Future<List<AdminSyncSupportDevice>> fetchSyncSupportDevices({
    required String companyId,
  }) async {
    return [AdminSyncSupportDevice.fromMap(_supportDeviceMap())];
  }

  @override
  Future<AdminSyncSupportDeviceDetail> fetchSyncSupportDeviceDetail({
    required String companyId,
    required String deviceId,
  }) async {
    return AdminSyncSupportDeviceDetail.fromMap({
      'device': _supportDeviceMap(),
      'diagnostic': _supportDiagnosticMap(),
      'failedEvents': const [],
      'openConflicts': const [],
      'resolvedConflicts': const [],
      'commands': supportCommands,
    });
  }

  @override
  Future<AdminSyncSupportDryRunResult> dryRunSyncSupportAction({
    required String companyId,
    required String deviceId,
    required String command,
    required String reason,
  }) async {
    supportDryRunCalls++;
    final expected = switch (command) {
      'RETRY_FAILED_SYNC_EVENTS' => 'REPROCESSAR',
      'REPAIR_OPERATIONAL_ORDER_ITEM_TOTAL_CENTS' => 'REPARAR',
      'CLEAR_RESOLVED_CONFLICT_CACHE' => 'LIMPAR',
      'FORCE_SYNC_PULL' => 'ATUALIZAR',
      _ => 'RECALCULAR',
    };
    return AdminSyncSupportDryRunResult.fromMap({
      'allowed': true,
      'command': command,
      'label': 'Comando seguro',
      'expectedConfirmationText': expected,
      'blockers': const [],
      'risks': ['Executado pelo app no proprio dispositivo.'],
      'summary': 'Comando pode ser enviado com seguranca.',
    });
  }

  @override
  Future<AdminSyncSupportActionResult> createSyncSupportAction({
    required String companyId,
    required String deviceId,
    required String command,
    required String reason,
    required String confirmationText,
  }) async {
    supportCreateCalls++;
    final commandMap = {
      'id': 'cmd-created',
      'command': command,
      'label': 'Comando seguro',
      'status': 'PENDING',
      'reason': reason,
      'payload': const {},
      'result': const {},
      'errorMessage': null,
      'requestedAt': '2026-05-24T12:30:00.000Z',
      'pickedUpAt': null,
      'completedAt': null,
      'expiresAt': '2026-05-25T12:30:00.000Z',
    };
    supportCommands.insert(0, commandMap);
    return AdminSyncSupportActionResult.fromMap({
      'ok': true,
      'message': 'Comando enviado ao dispositivo.',
      'command': commandMap,
    });
  }

  @override
  Future<AdminCompanySyncHealth> fetchCompanySyncHealth(
    String companyId,
  ) async {
    companyHealthFetchCount++;
    if (throwCompanySync) {
      throw const AdminApiException(message: 'falha controlada');
    }
    return AdminCompanySyncHealth.fromMap(_companySyncHealthMap());
  }

  @override
  Future<List<AdminCompanySyncDevice>> fetchCompanySyncDevices(
    String companyId,
  ) async {
    if (throwCompanySync) {
      throw const AdminApiException(message: 'falha controlada');
    }
    if (emptyCompanySync) {
      return const [];
    }
    return [AdminCompanySyncDevice.fromMap(_companyDeviceMap())];
  }

  @override
  Future<AdminPaginatedResult<AdminSyncEventDiagnostic>>
  fetchCompanySyncEvents({required AdminCompanySyncEventsQuery query}) async {
    if (throwCompanySync) {
      throw const AdminApiException(message: 'falha controlada');
    }
    return AdminPaginatedResult<AdminSyncEventDiagnostic>(
      items: emptyCompanySync
          ? []
          : [AdminSyncEventDiagnostic.fromMap(_companyEventMap())],
      pagination: AdminPaginationMeta(
        page: 1,
        pageSize: 20,
        total: emptyCompanySync ? 0 : 1,
        count: emptyCompanySync ? 0 : 1,
        hasNext: false,
        hasPrevious: false,
      ),
      filters: const {},
      sort: const AdminSortMeta(by: 'createdAt', direction: 'desc'),
    );
  }

  @override
  Future<AdminPaginatedResult<AdminSyncConflictDiagnostic>>
  fetchCompanySyncConflicts({
    required AdminCompanySyncConflictsQuery query,
  }) async {
    if (throwCompanySync) {
      throw const AdminApiException(message: 'falha controlada');
    }
    final items = query.status == 'open'
        ? [_companyOpenConflictMap()]
        : [_companyOpenConflictMap(), _companyResolvedConflictMap()];
    return AdminPaginatedResult<AdminSyncConflictDiagnostic>(
      items: emptyCompanySync
          ? []
          : items.map(AdminSyncConflictDiagnostic.fromMap).toList(),
      pagination: AdminPaginationMeta(
        page: 1,
        pageSize: 20,
        total: emptyCompanySync ? 0 : items.length,
        count: emptyCompanySync ? 0 : items.length,
        hasNext: false,
        hasPrevious: false,
      ),
      filters: const {},
      sort: const AdminSortMeta(by: 'createdAt', direction: 'desc'),
    );
  }

  @override
  Future<AdminPaginatedResult<AdminSyncIncidentDiagnostic>>
  fetchCompanySyncIncidents({
    required AdminCompanySyncIncidentsQuery query,
  }) async {
    if (throwCompanySync) {
      throw const AdminApiException(message: 'falha controlada');
    }
    return AdminPaginatedResult<AdminSyncIncidentDiagnostic>(
      items: emptyCompanySync
          ? []
          : [AdminSyncIncidentDiagnostic.fromMap(_companyIncidentMap())],
      pagination: AdminPaginationMeta(
        page: 1,
        pageSize: 20,
        total: emptyCompanySync ? 0 : 1,
        count: emptyCompanySync ? 0 : 1,
        hasNext: false,
        hasPrevious: false,
      ),
      filters: const {},
      sort: const AdminSortMeta(by: 'createdAt', direction: 'desc'),
    );
  }
}

Map<String, dynamic> _companyMap() {
  return {
    'id': 'company-1',
    'name': 'Loja Moda Sul',
    'legalName': 'Loja Moda Sul LTDA',
    'documentNumber': '00.000.000/0001-00',
    'slug': 'loja-moda-sul',
    'isActive': true,
    'createdAt': '2026-01-01T00:00:00.000Z',
    'updatedAt': '2026-05-24T00:00:00.000Z',
    'license': _licenseMap(),
    'counts': {
      'memberships': 1,
      'categories': 2,
      'products': 10,
      'customers': 3,
      'suppliers': 1,
      'purchases': 2,
      'sales': 5,
      'financialEvents': 4,
      'cashEvents': 2,
    },
  };
}

Map<String, dynamic> _licenseMap() {
  return {
    'id': 'license-1',
    'companyId': 'company-1',
    'companyName': 'Loja Moda Sul',
    'companyLegalName': 'Loja Moda Sul LTDA',
    'companySlug': 'loja-moda-sul',
    'companyIsActive': true,
    'plan': 'PRO',
    'status': 'active',
    'startsAt': '2026-01-01T00:00:00.000Z',
    'expiresAt': '2026-05-29T00:00:00.000Z',
    'maxDevices': 100,
    'syncEnabled': true,
    'createdAt': '2026-01-01T00:00:00.000Z',
    'updatedAt': '2026-05-24T00:00:00.000Z',
  };
}

Map<String, dynamic> _accessSummaryMap(String companyId) {
  return {
    'company': {
      'id': companyId,
      'name': 'Loja Moda Sul',
      'slug': 'loja-moda-sul',
      'license': {'plan': 'BASIC', 'status': 'ACTIVE', 'pendingPlan': 'PRO'},
    },
    'summary': {
      'totalUsers': 2,
      'totalEmployees': 3,
      'activeEmployees': 1,
      'invitedEmployees': 1,
      'disabledEmployees': 1,
      'owners': 1,
      'admins': 1,
      'operators': 1,
      'usersWithoutEmployeeProfile': 0,
      'employeeProfilesWithoutUser': 1,
      'lastSeenAt': '2026-05-24T12:00:00.000Z',
      'lastPermissionChangeAt': '2026-05-23T12:00:00.000Z',
    },
    'users': [
      {
        'userId': 'user-owner-secret-long-id',
        'membershipId': 'membership-owner-secret-long-id',
        'employeeProfileId': 'employee-owner-secret-long-id',
        'name': 'Dona Tatuzin',
        'email': 'owner@tatuzin.test',
        'membershipRole': 'OWNER',
        'employeeRole': 'OWNER',
        'status': 'ACTIVE',
        'accountStatus': 'ACTIVE',
        'effectivePermissions': ['employees.manage', 'subscription.manage'],
        'isOwner': true,
        'isProtectedOwner': true,
        'hasUserAccount': true,
        'hasEmployeeProfile': true,
        'lastSeenAt': '2026-05-24T12:00:00.000Z',
        'createdAt': '2026-01-01T00:00:00.000Z',
        'updatedAt': '2026-05-24T00:00:00.000Z',
        'devices': [
          {
            'id': 'session-mobile-1',
            'userId': 'user-owner-secret-long-id',
            'membershipId': 'membership-owner-secret-long-id',
            'userName': 'Dona Tatuzin',
            'userEmail': 'owner@tatuzin.test',
            'membershipRole': 'OWNER',
            'clientType': 'MOBILE_APP',
            'clientInstanceId': 'client-instance-secret-long-id',
            'deviceLabel': 'PDV Android',
            'platform': 'android',
            'appVersion': '1.2.3',
            'status': 'ACTIVE',
            'lastSeenAt': '2026-05-24T12:00:00.000Z',
            'createdAt': '2026-01-01T00:00:00.000Z',
          },
        ],
      },
      {
        'userId': 'user-admin-secret-long-id',
        'membershipId': 'membership-admin-secret-long-id',
        'employeeProfileId': 'employee-admin-secret-long-id',
        'name': 'Gerente Loja',
        'email': 'gerente@tatuzin.test',
        'membershipRole': 'ADMIN',
        'employeeRole': 'MANAGER',
        'status': 'ACTIVE',
        'accountStatus': 'ACTIVE',
        'effectivePermissions': ['sales.create'],
        'isOwner': false,
        'isProtectedOwner': false,
        'hasUserAccount': true,
        'hasEmployeeProfile': true,
        'lastSeenAt': '2026-05-24T11:00:00.000Z',
        'createdAt': '2026-01-02T00:00:00.000Z',
        'updatedAt': '2026-05-24T00:00:00.000Z',
        'devices': [
          {
            'id': 'session-admin-1',
            'userId': 'user-admin-secret-long-id',
            'membershipId': 'membership-admin-secret-long-id',
            'userName': 'Gerente Loja',
            'userEmail': 'gerente@tatuzin.test',
            'membershipRole': 'ADMIN',
            'clientType': 'ADMIN_WEB',
            'clientInstanceId': 'admin-client-instance-secret-long-id',
            'deviceLabel': 'Admin Chrome',
            'platform': 'web',
            'appVersion': 'admin',
            'status': 'ACTIVE',
            'lastSeenAt': '2026-05-24T11:00:00.000Z',
            'createdAt': '2026-01-02T00:00:00.000Z',
          },
        ],
      },
    ],
    'employees': [
      {
        'employeeProfileId': 'employee-owner-secret-long-id',
        'userId': 'user-owner-secret-long-id',
        'membershipId': 'membership-owner-secret-long-id',
        'name': 'Dona Tatuzin',
        'email': 'owner@tatuzin.test',
        'phone': '(11) 99999-0000',
        'employeeRole': 'OWNER',
        'membershipRole': 'OWNER',
        'status': 'ACTIVE',
        'savedPermissions': const [],
        'effectivePermissions': ['employees.manage', 'subscription.manage'],
        'isOwner': true,
        'isProtectedOwner': true,
        'hasUserAccount': true,
        'createdAt': '2026-01-01T00:00:00.000Z',
        'updatedAt': '2026-05-24T00:00:00.000Z',
      },
      {
        'employeeProfileId': 'employee-invited-secret-long-id',
        'name': 'Operadora Convidada',
        'email': 'convite@tatuzin.test',
        'phone': '(11) 98888-0000',
        'employeeRole': 'CASHIER',
        'status': 'INVITED',
        'savedPermissions': ['sales.create'],
        'effectivePermissions': ['sales.create'],
        'isOwner': false,
        'isProtectedOwner': false,
        'hasUserAccount': false,
        'invitationStatus': 'PENDING',
        'invitationSentAt': '2026-05-20T00:00:00.000Z',
        'inviteExpiresAt': '2026-05-27T00:00:00.000Z',
        'createdAt': '2026-05-20T00:00:00.000Z',
        'updatedAt': '2026-05-20T00:00:00.000Z',
      },
      {
        'employeeProfileId': 'employee-disabled-secret-long-id',
        'name': 'Ex Operador',
        'email': 'disabled@tatuzin.test',
        'employeeRole': 'SELLER',
        'status': 'DISABLED',
        'savedPermissions': ['sales.create'],
        'effectivePermissions': const [],
        'isOwner': false,
        'isProtectedOwner': false,
        'hasUserAccount': false,
        'disabledAt': '2026-05-21T00:00:00.000Z',
        'createdAt': '2026-05-01T00:00:00.000Z',
        'updatedAt': '2026-05-21T00:00:00.000Z',
      },
    ],
    'permissionsCatalog': [
      {
        'key': 'employees.manage',
        'description': 'Gerenciar funcionarios.',
        'owner': true,
        'admin': true,
        'operator': false,
      },
      {
        'key': 'sales.create',
        'description': 'Criar vendas.',
        'owner': true,
        'admin': true,
        'operator': true,
      },
      {
        'key': 'unknown.future',
        'description': '',
        'owner': false,
        'admin': false,
        'operator': false,
      },
    ],
    'devices': [
      {
        'id': 'session-mobile-1',
        'userId': 'user-owner-secret-long-id',
        'membershipId': 'membership-owner-secret-long-id',
        'userName': 'Dona Tatuzin',
        'userEmail': 'owner@tatuzin.test',
        'membershipRole': 'OWNER',
        'clientType': 'MOBILE_APP',
        'clientInstanceId': 'client-instance-secret-long-id',
        'deviceLabel': 'PDV Android',
        'platform': 'android',
        'appVersion': '1.2.3',
        'status': 'ACTIVE',
        'lastSeenAt': '2026-05-24T12:00:00.000Z',
        'createdAt': '2026-01-01T00:00:00.000Z',
      },
      {
        'id': 'session-admin-1',
        'userId': 'user-admin-secret-long-id',
        'membershipId': 'membership-admin-secret-long-id',
        'userName': 'Gerente Loja',
        'userEmail': 'gerente@tatuzin.test',
        'membershipRole': 'ADMIN',
        'clientType': 'ADMIN_WEB',
        'clientInstanceId': 'admin-client-instance-secret-long-id',
        'deviceLabel': 'Admin Chrome',
        'platform': 'web',
        'appVersion': 'admin',
        'status': 'ACTIVE',
        'lastSeenAt': '2026-05-24T11:00:00.000Z',
        'createdAt': '2026-01-02T00:00:00.000Z',
      },
    ],
    'audit': [
      {
        'id': 'audit-access-1',
        'source': 'admin',
        'action': 'access.block',
        'actorUserId': 'platform-admin-1',
        'actorName': 'Admin',
        'actorEmail': 'admin@tatuzin.test',
        'target': 'Gerente Loja',
        'targetEmail': 'gerente@tatuzin.test',
        'targetUserId': 'user-admin-secret-long-id',
        'targetEmployeeId': 'employee-admin-secret-long-id',
        'membershipId': 'membership-admin-secret-long-id',
        'reason': 'Chamado 123',
        'before': {
          'status': 'ACTIVE',
          'passwordHash': 'hash-secret',
          'name': 'Gerente Loja',
        },
        'after': {'status': 'DISABLED', 'name': 'Gerente Loja'},
        'metadata': {
          'Authorization': 'Bearer secret',
          'public': 'ok',
          'confirmationTextExpected': 'BLOQUEAR',
        },
        'createdAt': '2026-05-24T12:00:00.000Z',
      },
      {
        'id': 'audit-access-2',
        'source': 'admin',
        'action': 'access.reactivate',
        'actorUserId': 'platform-admin-1',
        'actorName': 'Admin',
        'actorEmail': 'admin@tatuzin.test',
        'target': 'Ex Operador',
        'targetEmail': 'disabled@tatuzin.test',
        'targetEmployeeId': 'employee-disabled-secret-long-id',
        'reason': 'Retorno autorizado',
        'before': {'status': 'DISABLED', 'name': 'Ex Operador'},
        'after': {'status': 'ACTIVE', 'name': 'Ex Operador'},
        'metadata': {'confirmationTextExpected': 'REATIVAR'},
        'createdAt': '2026-05-23T12:00:00.000Z',
      },
    ],
  };
}

Map<String, dynamic> _auditSummaryMap() {
  return {
    'overview': {
      'totalEvents': 1,
      'countsByAction': {'login': 1},
    },
    'items': [
      {
        'id': 'audit-1',
        'action': 'ADMIN_VIEW',
        'actorUserId': 'user-1',
        'actorUserName': 'Admin',
        'actorUserEmail': 'admin@tatuzin.test',
        'targetCompanyId': 'company-1',
        'targetCompanyName': 'Loja Moda Sul',
        'metadata': const {},
        'createdAt': '2026-05-24T00:00:00.000Z',
      },
    ],
    'pagination': {
      'page': 1,
      'pageSize': 20,
      'total': 1,
      'count': 1,
      'hasNext': false,
      'hasPrevious': false,
    },
    'filters': const {},
  };
}

List<Map<String, dynamic>> _auditLogItems() {
  return [
    {
      'id': 'audit-license-1',
      'source': 'billing_admin',
      'category': 'license',
      'action': 'license.emergency_extension',
      'status': 'success',
      'companyId': 'company-1',
      'companyName': 'Loja Moda Sul',
      'actorUserId': 'admin-1',
      'actorName': 'Admin Tatuzin',
      'actorEmail': 'admin@tatuzin.test',
      'targetType': 'license',
      'targetId': 'company-1',
      'targetLabel': 'Licenca Loja Moda Sul',
      'reason': 'Atendimento emergencial',
      'summary': 'Extensao emergencial',
      'before': {
        'status': 'EXPIRED',
        'providerSubscriptionId': 'preapproval-secret-full-id',
      },
      'after': {'status': 'ACTIVE', 'expiresAt': '2026-06-01T00:00:00.000Z'},
      'metadata': {'Authorization': 'Bearer secret', 'source': 'admin_web'},
      'createdAt': '2026-05-26T10:00:00.000Z',
    },
    {
      'id': 'audit-access-1',
      'source': 'admin',
      'category': 'access',
      'action': 'access.block',
      'status': 'success',
      'companyId': 'company-1',
      'companyName': 'Loja Moda Sul',
      'actorUserId': 'admin-1',
      'actorName': 'Admin Tatuzin',
      'targetType': 'employee',
      'targetId': 'employee-2',
      'targetLabel': 'Gerente Loja',
      'reason': 'Chamado 123',
      'summary': 'Bloqueio de acesso operacional',
      'before': {'status': 'ACTIVE', 'passwordHash': 'hash-secret'},
      'after': {'status': 'DISABLED'},
      'metadata': {'inviteTokenHash': 'hash-secret'},
      'createdAt': '2026-05-26T09:00:00.000Z',
    },
    {
      'id': 'audit-sync-1',
      'source': 'sync_support',
      'category': 'sync',
      'action': 'sync.support_command.created',
      'status': 'pending',
      'companyId': 'company-1',
      'companyName': 'Loja Moda Sul',
      'actorUserId': 'admin-1',
      'actorName': 'Admin Tatuzin',
      'targetType': 'device',
      'targetId': 'device-1',
      'targetLabel': 'PDV Caixa',
      'reason': 'Recalcular status',
      'summary': 'Comando de suporte criado',
      'metadata': {
        'command': 'REFRESH_SYNC_STATUS',
        'headers': {'authorization': 'Bearer secret'},
      },
      'createdAt': '2026-05-26T08:00:00.000Z',
    },
  ];
}

Map<String, dynamic> _syncSummaryMap() {
  return {
    'overview': {
      'totalCompanies': 1,
      'syncEnabledCompanies': 0,
      'licenseStatusCounts': {'active': 1},
    },
    'items': [
      {
        'companyId': 'company-1',
        'companyName': 'Loja Moda Sul',
        'companySlug': 'loja-moda-sul',
        'licenseStatus': 'active',
        'licensePlan': 'PRO',
        'syncEnabled': false,
        'remoteRecordCount': 29,
        'entityCounts': {
          'memberships': 1,
          'categories': 2,
          'products': 10,
          'customers': 3,
          'suppliers': 1,
          'purchases': 2,
          'sales': 5,
          'financialEvents': 4,
          'cashEvents': 2,
        },
      },
    ],
    'pagination': {
      'page': 1,
      'pageSize': 20,
      'total': 1,
      'count': 1,
      'hasNext': false,
      'hasPrevious': false,
    },
    'filters': const {},
  };
}

Map<String, dynamic> _syncCompanyMap() {
  return {
    'companyId': 'company-1',
    'companyName': 'Loja Moda Sul',
    'plan': 'PRO',
    'syncStatus': 'failed',
    'currentVersion': '42',
    'serverFirstSnapshotVersion': '40',
    'acceptedCount': 10,
    'duplicateCount': 1,
    'pendingCount': 2,
    'conflictCount': 1,
    'failedCount': 1,
    'openConflictCount': 1,
    'incidentCount': 1,
    'lastEventAt': '2026-05-24T12:00:00.000Z',
    'lastIncidentAt': '2026-05-24T12:00:00.000Z',
    'requiresReview': true,
  };
}

Map<String, dynamic> _eventMap() {
  return {
    'id': 'event-1',
    'eventId': 'client-event-1',
    'feature': 'pdv',
    'entity': 'stockDeduction',
    'operation': 'create',
    'entityLocalId': 'local-1',
    'entityServerId': null,
    'status': 'failed',
    'serverVersion': '42',
    'rejectionCode': 'STOCK_VARIANT_NOT_FOUND',
    'rejectionMessage': 'Variante nao encontrada.',
    'occurredAt': '2026-05-24T12:00:00.000Z',
    'createdAt': '2026-05-24T12:00:00.000Z',
    'updatedAt': '2026-05-24T12:00:00.000Z',
    'materializedAt': null,
    'relatedConflictId': 'conflict-open',
    'classification': 'READ_ONLY',
    'recommendedAction': 'CONTACT_SUPPORT',
    'canReprocess': false,
    'canArchive': false,
    'safePayloadPreview': {'entity': 'stockDeduction'},
  };
}

Map<String, dynamic> _openConflictMap() {
  return {
    'conflictId': 'conflict-open',
    'syncEventId': 'event-1',
    'entity': 'stockDeduction',
    'entityLocalId': 'local-1',
    'entityServerId': null,
    'code': 'STOCK_VARIANT_NOT_FOUND',
    'message': 'Produto remoto nao encontrado.',
    'status': 'open',
    'createdAt': '2026-05-24T12:00:00.000Z',
    'updatedAt': '2026-05-24T12:00:00.000Z',
    'resolvedAt': null,
    'classification': 'READ_ONLY',
    'recommendedAction': 'CONTACT_SUPPORT',
    'canReprocess': false,
    'canArchive': false,
    'canCreateManualStockAdjustment': false,
    'safePayloadPreview': {'entity': 'stockDeduction'},
    'resolution': const {},
  };
}

Map<String, dynamic> _resolvedConflictMap() {
  return {
    ..._openConflictMap(),
    'conflictId': 'conflict-resolved',
    'code': 'OLD_CONFLICT',
    'status': 'resolved',
    'resolvedAt': '2026-05-24T13:00:00.000Z',
  };
}

Map<String, dynamic> _supportDeviceMap() {
  return {
    'id': 'device-1',
    'maskedDeviceId': 'device...0001',
    'clientInstanceId': 'client...0001',
    'deviceLabel': 'PDV Loja Moda Sul',
    'platform': 'android',
    'appVersion': '2.1.0',
    'status': 'local_failure',
    'deviceStatus': 'active',
    'lastSeenAt': '2026-05-24T12:00:00.000Z',
    'lastPushAt': '2026-05-24T12:00:00.000Z',
    'lastPullAt': '2026-05-24T12:00:00.000Z',
    'user': {
      'id': 'user-1',
      'name': 'Operador Local',
      'email': 'operador@tatuzin.test',
    },
    'diagnostic': {
      'pendingCount': 2,
      'failedCount': 1,
      'openConflictCount': 1,
      'resolvedConflictCount': 1,
      'ignoredConflictCount': 0,
      'lastLocalError': 'totalCents antigo',
      'reportedAt': '2026-05-24T12:00:00.000Z',
    },
    'remoteConflictCounts': {
      'openConflictCount': 1,
      'resolvedConflictCount': 1,
      'ignoredConflictCount': 0,
    },
  };
}

Map<String, dynamic> _supportDiagnosticMap() {
  return {
    'id': 'diagnostic-1',
    'pendingCount': 2,
    'failedCount': 1,
    'openConflictCount': 1,
    'resolvedConflictCount': 1,
    'ignoredConflictCount': 0,
    'lastLocalError': 'totalCents antigo',
    'lastLocalErrorCode': 'SYNC_PUSH_FAILED',
    'lastLocalErrorEntity': 'operationalOrderItem',
    'appVersion': '2.1.0',
    'platform': 'android',
    'localSchemaVersion': '37',
    'lastPushAt': '2026-05-24T12:00:00.000Z',
    'lastPullAt': '2026-05-24T12:00:00.000Z',
    'lastSuccessfulSyncAt': '2026-05-24T12:00:00.000Z',
    'safeDetails': {'entity': 'operationalOrderItem'},
    'reportedAt': '2026-05-24T12:00:00.000Z',
  };
}

Map<String, dynamic> _companySyncHealthMap() {
  return {
    'companyId': 'company-1',
    'companyName': 'Loja Moda Sul',
    'companySlug': 'loja-moda-sul',
    'currentServerVersion': '42',
    'serverFirstSnapshotVersion': '40',
    'status': 'attention',
    'syncEnabled': true,
    'license': _licenseMap(),
    'devices': {
      'active': 1,
      'blocked': 0,
      'revoked': 0,
      'pending': 0,
      'total': 1,
    },
    'events': {
      'accepted': 10,
      'rejected': 1,
      'conflict': 2,
      'failed': 1,
      'duplicate': 0,
      'pending': 0,
      'total': 14,
    },
    'openConflictsCount': 1,
    'lastMaterializedAt': '2026-05-24T12:00:00.000Z',
    'lastSyncAt': '2026-05-24T12:05:00.000Z',
    'deviceSyncStates': [
      {
        'deviceId': 'device-1',
        'deviceLabel': 'PDV Loja Moda Sul',
        'clientInstanceId': 'client-mobile-1',
        'status': 'active',
        'lastSyncAt': '2026-05-24T12:05:00.000Z',
        'lastSeenAt': '2026-05-24T12:00:00.000Z',
      },
    ],
    'lastIncident': {
      'id': 'incident-1',
      'code': 'SYNC_FAILED',
      'message': 'Falha de materializacao.',
      'severity': 'error',
      'createdAt': '2026-05-24T12:00:00.000Z',
    },
  };
}

Map<String, dynamic> _companyDeviceRefMap() {
  return {
    'id': 'device-1',
    'deviceLabel': 'PDV Loja Moda Sul',
    'clientInstanceId': 'client-mobile-1',
    'status': 'active',
  };
}

Map<String, dynamic> _companyUserRefMap() {
  return {
    'id': 'user-1',
    'name': 'Operador Local',
    'email': 'operador@tatuzin.test',
  };
}

Map<String, dynamic> _companyEventRefMap() {
  return {
    'id': 'event-1',
    'eventId': 'client-event-1',
    'feature': 'pdv',
    'entity': 'stockDeduction',
    'operation': 'create',
    'status': 'failed',
    'serverVersion': '42',
  };
}

Map<String, dynamic> _companyEventMap() {
  return {
    ..._companyEventRefMap(),
    'entityLocalId': 'local-1',
    'entityServerId': null,
    'occurredAt': '2026-05-24T12:00:00.000Z',
    'createdAt': '2026-05-24T12:00:00.000Z',
    'materializedAt': null,
    'errorCode': 'STOCK_VARIANT_NOT_FOUND',
    'errorMessage': 'Variante nao encontrada.',
    'payloadSummary': '{"entity":"stockDeduction"}',
    'device': _companyDeviceRefMap(),
    'user': _companyUserRefMap(),
  };
}

Map<String, dynamic> _companyOpenConflictMap() {
  return {
    'id': 'conflict-open',
    'entity': 'stockDeduction',
    'entityLocalId': 'local-1',
    'entityServerId': null,
    'code': 'STOCK_VARIANT_NOT_FOUND',
    'message': 'Produto remoto nao encontrado.',
    'status': 'open',
    'createdAt': '2026-05-24T12:00:00.000Z',
    'resolvedAt': null,
    'payloadSummary': '{"entity":"stockDeduction"}',
    'resolutionSummary': null,
    'device': _companyDeviceRefMap(),
    'user': _companyUserRefMap(),
    'resolvedBy': null,
    'event': _companyEventRefMap(),
  };
}

Map<String, dynamic> _companyResolvedConflictMap() {
  return {
    ..._companyOpenConflictMap(),
    'id': 'conflict-resolved',
    'code': 'OLD_CONFLICT',
    'message': 'Conflito antigo resolvido.',
    'status': 'resolved',
    'resolvedAt': '2026-05-24T13:00:00.000Z',
    'resolutionSummary': '{"decision":"ignored old"}',
    'resolvedBy': _companyUserRefMap(),
  };
}

Map<String, dynamic> _companyIncidentMap() {
  return {
    'id': 'incident-1',
    'code': 'SYNC_FAILED',
    'message': 'Falha de materializacao.',
    'severity': 'error',
    'createdAt': '2026-05-24T12:00:00.000Z',
    'detailsSummary': '{"cause":"stock"}',
    'device': _companyDeviceRefMap(),
    'user': _companyUserRefMap(),
    'event': _companyEventRefMap(),
  };
}

Map<String, dynamic> _companyDeviceMap() {
  return {
    'id': 'device-1',
    'deviceLabel': 'PDV Loja Moda Sul',
    'platform': 'android',
    'appVersion': '2.1.0',
    'status': 'active',
    'lastSeenAt': '2026-05-24T12:00:00.000Z',
    'userId': 'user-1',
    'userName': 'Operador Local',
    'userEmail': 'operador@tatuzin.test',
    'clientInstanceId': 'client-mobile-1',
    'createdAt': '2026-05-24T00:00:00.000Z',
    'approvedAt': '2026-05-24T00:00:00.000Z',
    'revokedAt': null,
    'revokedReason': null,
  };
}

Map<String, dynamic> _plansOverviewMap() {
  const featureKeys = [
    'sales',
    'cash',
    'products',
    'categories',
    'customersBasic',
    'fiadoCreateSale',
    'fiadoManagement',
    'supplies',
    'costs',
    'suppliers',
    'purchases',
    'inventoryBasic',
    'inventoryAdvanced',
    'reportsDaily',
    'reportsBasic',
    'reportsAdvanced',
    'employees',
    'permissions',
    'multiDevice',
    'ownerWebPanel',
    'commissions',
    'devicesManagement',
  ];
  const freeFeatures = {
    'sales',
    'cash',
    'products',
    'categories',
    'customersBasic',
    'fiadoCreateSale',
    'reportsDaily',
    'inventoryBasic',
  };
  const basicFeatures = {
    ...freeFeatures,
    'fiadoManagement',
    'supplies',
    'costs',
    'suppliers',
    'purchases',
    'inventoryAdvanced',
    'reportsBasic',
  };

  Map<String, dynamic> plan(
    String key,
    Set<String> enabledFeatures, {
    required int priceCents,
    required int maxDevices,
    required int maxEmployees,
    required List<String> reportPeriods,
    required int companiesCount,
    required int activeCompaniesCount,
    required int pendingPlanCount,
  }) {
    return {
      'key': key,
      'name': key == 'FREE'
          ? 'Free'
          : key == 'BASIC'
          ? 'Basico'
          : 'Pro',
      'description': key == 'PRO'
          ? 'Equipe, dispositivos e relatorios avancados.'
          : 'Contrato administrativo real.',
      'priceCents': priceCents,
      'currency': 'BRL',
      'billingCycle': key == 'FREE' ? 'free' : 'monthly',
      'featuresSummary': key == 'PRO'
          ? const [
              'Multi-dispositivo',
              'Funcionarios, permissoes e comissoes',
              'Relatorios avancados',
            ]
          : const ['Contrato real'],
      'entitlements': {
        'plan': key,
        'features': {
          for (final feature in featureKeys)
            feature: enabledFeatures.contains(feature),
        },
        'limits': {
          'maxDevices': maxDevices,
          'maxEmployees': maxEmployees,
          'reportPeriods': reportPeriods,
        },
      },
      'usage': {
        'companiesCount': companiesCount,
        'activeCompaniesCount': activeCompaniesCount,
        'pendingPlanCount': pendingPlanCount,
      },
      'status': 'ACTIVE',
      'isPublic': true,
      'observations': key == 'PRO'
          ? const [
              'Libera Funcionarios PRO, permissoes, multi-dispositivo, owner_web e relatorios avancados.',
            ]
          : const ['pendingPlan nao libera acesso.'],
    };
  }

  return {
    'items': [
      plan(
        'FREE',
        freeFeatures,
        priceCents: 0,
        maxDevices: 1,
        maxEmployees: 0,
        reportPeriods: const ['daily'],
        companiesCount: 2,
        activeCompaniesCount: 1,
        pendingPlanCount: 0,
      ),
      plan(
        'BASIC',
        basicFeatures,
        priceCents: 4900,
        maxDevices: 1,
        maxEmployees: 0,
        reportPeriods: const ['daily', 'weekly', 'monthly'],
        companiesCount: 3,
        activeCompaniesCount: 2,
        pendingPlanCount: 1,
      ),
      plan(
        'PRO',
        featureKeys.toSet(),
        priceCents: 9900,
        maxDevices: 100,
        maxEmployees: 100,
        reportPeriods: const ['daily', 'weekly', 'monthly', 'yearly', 'custom'],
        companiesCount: 4,
        activeCompaniesCount: 4,
        pendingPlanCount: 2,
      ),
    ],
    'features': [
      for (final feature in featureKeys)
        {
          'key': feature,
          'requiredPlan': feature == 'employees' || feature == 'ownerWebPanel'
              ? 'PRO'
              : basicFeatures.contains(feature)
              ? 'BASIC'
              : 'FREE',
        },
    ],
    'usageSummary': const {
      'totalPlans': 3,
      'companiesByPlan': {'FREE': 2, 'BASIC': 3, 'PRO': 4},
      'activeCompaniesByPlan': {'FREE': 1, 'BASIC': 2, 'PRO': 4},
      'pendingCompaniesByPlan': {'FREE': 0, 'BASIC': 1, 'PRO': 2},
      'pendingPlanCount': 3,
      'plansWithActiveCompanies': 3,
    },
    'rules': const {
      'entitlementSource': 'license.plan',
      'pendingPlanReleasesFeatures': false,
    },
  };
}

Map<String, dynamic> _deviceInventoryMap() {
  return {
    'id': 'device-secret-full-id-123456789',
    'maskedDeviceId': 'devi...6789',
    'companyId': 'company-1',
    'companyName': 'Loja Moda Sul',
    'companySlug': 'loja-moda-sul',
    'userId': 'user-1',
    'userName': 'Operador Local',
    'userEmail': 'operador@tatuzin.test',
    'membershipId': 'membership-1',
    'membershipRole': 'OWNER',
    'deviceLabel': 'PDV Loja Moda Sul',
    'clientType': 'MOBILE_APP',
    'clientInstanceId': 'clie...0001',
    'platform': 'android',
    'appVersion': '2.1.0',
    'status': 'active',
    'lastSeenAt': '2026-05-24T12:00:00.000Z',
    'createdAt': '2026-05-24T00:00:00.000Z',
    'updatedAt': '2026-05-24T12:00:00.000Z',
    'revokedAt': null,
    'revokedReason': null,
    'session': {
      'id': 'sess...0001',
      'status': 'active',
      'createdAt': '2026-05-24T00:00:00.000Z',
      'lastSeenAt': '2026-05-24T12:00:00.000Z',
      'lastRefreshedAt': '2026-05-24T12:00:00.000Z',
      'expiresAt': '2026-06-24T12:00:00.000Z',
      'revokedAt': null,
      'revokedReason': null,
    },
    'diagnostic': {
      'pendingCount': 1,
      'failedCount': 3,
      'openConflictCount': 2,
      'resolvedConflictCount': 1,
      'ignoredConflictCount': 0,
      'lastLocalError': 'totalCents antigo',
      'lastLocalErrorCode': 'SYNC_PUSH_FAILED',
      'lastLocalErrorEntity': 'operationalOrderItem',
      'reportedAt': '2026-05-24T12:00:00.000Z',
    },
  };
}

Map<String, dynamic> _adminDeviceInventoryMap() {
  return {
    ..._deviceInventoryMap(),
    'id': 'device-admin-full-id-123456789',
    'maskedDeviceId': 'admi...6789',
    'userId': 'user-admin-secret-long-id',
    'userName': 'Admin Tatuzin',
    'userEmail': 'admin@tatuzin.test',
    'membershipId': 'membership-admin-secret-long-id',
    'membershipRole': 'ADMIN',
    'deviceLabel': 'Admin web',
    'clientType': 'ADMIN_WEB',
    'clientInstanceId': 'admi...0002',
    'platform': 'web',
    'appVersion': 'admin-web',
    'lastSeenAt': '2026-05-24T11:00:00.000Z',
    'diagnostic': null,
    'session': {
      'id': 'sess...0002',
      'status': 'active',
      'createdAt': '2026-05-24T01:00:00.000Z',
      'lastSeenAt': '2026-05-24T11:00:00.000Z',
      'lastRefreshedAt': '2026-05-24T11:00:00.000Z',
      'expiresAt': '2026-06-24T11:00:00.000Z',
      'revokedAt': null,
      'revokedReason': null,
    },
  };
}

Map<String, dynamic> _mobileSessionMap() {
  return {
    'id': 'session-mobile',
    'userId': 'user-1',
    'userName': 'Operador Local',
    'userEmail': 'operador@tatuzin.test',
    'companyId': 'company-1',
    'companyName': 'Loja Moda Sul',
    'membershipId': 'membership-1',
    'membershipRole': 'OWNER',
    'clientType': 'mobile_app',
    'clientInstanceId': 'client-mobile-1',
    'deviceLabel': 'PDV Loja Moda Sul',
    'platform': 'android',
    'appVersion': '2.1.0',
    'status': 'active',
    'createdAt': '2026-05-24T00:00:00.000Z',
    'lastSeenAt': '2026-05-24T12:00:00.000Z',
    'lastRefreshedAt': '2026-05-24T12:00:00.000Z',
    'refreshTokenExpiresAt': '2026-06-24T12:00:00.000Z',
    'revokedAt': null,
    'revokedReason': null,
  };
}

Map<String, dynamic> _adminSessionMap() {
  return {
    ..._mobileSessionMap(),
    'id': 'session-admin',
    'clientType': 'admin_web',
    'clientInstanceId': 'client-admin-1',
    'deviceLabel': 'Admin web',
    'platform': 'web',
  };
}
