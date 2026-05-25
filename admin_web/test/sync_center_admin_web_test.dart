import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/testing.dart';
import 'package:tatuzin_admin_web/src/core/auth/admin_auth_storage.dart';
import 'package:tatuzin_admin_web/src/core/auth/admin_providers.dart';
import 'package:tatuzin_admin_web/src/core/models/admin_billing_models.dart';
import 'package:tatuzin_admin_web/src/core/models/admin_models.dart';
import 'package:tatuzin_admin_web/src/core/models/admin_sync_center_models.dart';
import 'package:tatuzin_admin_web/src/core/network/admin_api_client.dart';
import 'package:tatuzin_admin_web/src/core/network/admin_api_service.dart';
import 'package:tatuzin_admin_web/src/core/widgets/admin_shell_scaffold.dart';
import 'package:tatuzin_admin_web/src/features/companies/presentation/companies_page.dart';
import 'package:tatuzin_admin_web/src/features/companies/presentation/company_detail_page.dart';
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
    expect(find.text('Abrir console de sync'), findsWidgets);
    expect(find.text('Sync'), findsOneWidget);
    expect(find.text('Licenca'), findsOneWidget);
    expect(find.text('Dispositivos'), findsWidgets);
    expect(find.text('Funcionarios'), findsOneWidget);
    expect(find.text('Auditoria'), findsOneWidget);
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

    expect(find.text('Dispositivos por empresa'), findsOneWidget);
    expect(service.lastCompaniesQuery?.status, 'all');
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
    await tester.pumpWidget(
      _adminRouterTestApp(
        service: _FakeReadOnlyApiService(),
        initialLocation: '/licenses/company-1',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Plano atual'), findsOneWidget);
    expect(find.text('Pending plan'), findsOneWidget);
    expect(find.textContaining('Extensao emergencial'), findsOneWidget);
    expect(find.textContaining('Trocar plano'), findsOneWidget);
    expect(find.textContaining('Suspender'), findsOneWidget);
    expect(find.textContaining('Reativar'), findsOneWidget);

    await tester.tap(find.textContaining('Trocar plano'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Acao administrativa sera implementada em fase posterior com dry-run, confirmacao e auditoria.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Planos mostra matriz', (tester) async {
    _setLargeViewport(tester);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PlansPage())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Planos read-only'), findsOneWidget);
    expect(find.text('Matriz de features'), findsOneWidget);
    expect(find.text('FREE'), findsWidgets);
    expect(find.text('BASIC'), findsWidgets);
    expect(find.text('PRO'), findsWidgets);
    expect(find.text('Max dispositivos'), findsOneWidget);
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
        path: '/companies/:companyId',
        builder: (context, state) => Scaffold(
          body: CompanyDetailPage(
            companyId: state.pathParameters['companyId'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: '/companies/:companyId/sync',
        builder: (context, state) => Scaffold(
          body: SyncCompanyPage(
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
    this.throwDashboard = false,
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
  final bool throwDashboard;
  final bool emptyCompanySync;
  final bool throwCompanySync;
  AdminSyncCenterCompaniesQuery? lastCompaniesQuery;
  int companyHealthFetchCount = 0;
  int supportDryRunCalls = 0;
  int supportCreateCalls = 0;
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
  Future<AdminBillingCompanyStatus> fetchBillingCompanyStatus(
    String companyId,
  ) async {
    return AdminBillingCompanyStatus.fromMap({
      'company': {'id': companyId, 'name': 'Loja Moda Sul'},
      'license': {
        'plan': 'PRO',
        'status': 'ACTIVE',
        'currentPeriodEnd': '2026-06-30T00:00:00.000Z',
        'nextPaymentDate': '2026-06-30T00:00:00.000Z',
        'pendingPlan': 'BASIC',
        'billingSubscriptionStatus': 'authorized',
      },
      'billing': {
        'provider': 'mercadopago',
        'hasProviderSubscription': true,
        'maskedProviderSubscriptionId': 'pre_..._7890',
        'currentPeriodEnd': '2026-06-30T00:00:00.000Z',
        'nextPaymentDate': '2026-06-30T00:00:00.000Z',
        'pendingPlan': 'BASIC',
        'billingSubscriptionStatus': 'authorized',
      },
      'events': [
        {
          'id': 'billing-event-1',
          'provider': 'mercadopago',
          'eventType': 'payment.created',
          'status': 'processed',
        },
      ],
      'invoices': const [],
      'checkoutSessions': const [],
    });
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
