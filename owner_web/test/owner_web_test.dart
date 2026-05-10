import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tatuzin_owner_web/src/app/owner_web_app.dart';
import 'package:tatuzin_owner_web/src/app/owner_web_router.dart';
import 'package:tatuzin_owner_web/src/core/auth/owner_auth_controller.dart';
import 'package:tatuzin_owner_web/src/core/auth/owner_auth_storage.dart';
import 'package:tatuzin_owner_web/src/core/auth/owner_debug_log.dart';
import 'package:tatuzin_owner_web/src/core/auth/owner_providers.dart';
import 'package:tatuzin_owner_web/src/core/models/owner_models.dart';
import 'package:tatuzin_owner_web/src/core/network/owner_api_client.dart';
import 'package:tatuzin_owner_web/src/core/network/owner_api_service.dart';
import 'package:tatuzin_owner_web/src/core/widgets/owner_shell_scaffold.dart';
import 'package:tatuzin_owner_web/src/features/billing/presentation/owner_billing_page.dart';
import 'package:tatuzin_owner_web/src/features/clients/presentation/owner_clients_page.dart';
import 'package:tatuzin_owner_web/src/features/dashboard/presentation/owner_dashboard_page.dart';
import 'package:tatuzin_owner_web/src/features/devices/presentation/owner_devices_page.dart';
import 'package:tatuzin_owner_web/src/features/employees/presentation/owner_employees_page.dart';
import 'package:tatuzin_owner_web/src/features/finance/presentation/owner_finance_page.dart';
import 'package:tatuzin_owner_web/src/features/products/presentation/owner_products_page.dart';
import 'package:tatuzin_owner_web/src/features/reports/presentation/owner_reports_page.dart';
import 'package:tatuzin_owner_web/src/features/sales/presentation/owner_sales_page.dart';
import 'package:tatuzin_owner_web/src/features/settings/presentation/owner_settings_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('routes include owner pages and no /admin frontend route', () {
    expect(ownerRoutePaths, contains('/dashboard'));
    expect(ownerRoutePaths, contains('/sales'));
    expect(ownerRoutePaths, contains('/clients'));
    expect(ownerRoutePaths, contains('/finance'));
    expect(ownerRoutePaths, contains('/products'));
    expect(ownerRoutePaths, contains('/reports'));
    expect(ownerRoutePaths, contains('/billing'));
    expect(ownerRoutePaths, contains('/employees'));
    expect(ownerRoutePaths, contains('/settings'));
    expect(ownerRoutePaths, isNot(contains('/admin')));
  });

  testWidgets('unauthenticated app shows login page', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: OwnerWebApp()));
    await tester.pumpAndSettle();

    expect(find.text('Painel da empresa'), findsOneWidget);
    expect(find.text('Entrar'), findsOneWidget);
  });

  testWidgets('menu shows company management navigation', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ownerAuthControllerProvider.overrideWith(
            (ref) => _ReadyOwnerAuthController(),
          ),
        ],
        child: const MaterialApp(
          home: OwnerShellScaffold(
            currentLocation: '/dashboard',
            title: 'Dashboard',
            child: SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pump();

    for (final label in [
      'Dashboard',
      'Vendas',
      'Clientes / CRM',
      'Fiado',
      'Produtos e estoque',
      'Funcionários',
      'Relatórios',
      'Assinatura',
      'Configurações',
    ]) {
      expect(find.text(label), findsWidgets);
    }
    expect(find.text('Painel da empresa'), findsOneWidget);
    expect(find.text('Painel do dono'), findsNothing);
  });

  test('debug sanitizer does not expose tokens or passwords', () {
    final sanitized = sanitizeOwnerDebugData({
      'accessToken': 'secret-access',
      'refreshToken': 'secret-refresh',
      'Authorization': 'Bearer secret',
      'password': 'secret-password',
      'path': '/owner/company',
    });

    expect(sanitized['accessToken'], true);
    expect(sanitized['refreshToken'], true);
    expect(sanitized['Authorization'], true);
    expect(sanitized['password'], true);
    expect(sanitized.values, isNot(contains('secret-access')));
    expect(sanitized.values, isNot(contains('secret-refresh')));
    expect(sanitized.values, isNot(contains('Bearer secret')));
  });

  test('models parse safe payloads and ignore sensitive extras', () {
    final billing = OwnerBillingStatus.fromMap({
      'companyId': 'company-1',
      'plan': 'PRO',
      'status': 'ACTIVE',
      'providerSubscriptionId': 'preapproval-owner-secret-9999',
      'maskedProviderSubscriptionId': 'prea...9999',
      'hasProviderSubscription': true,
      'limits': {'maxDevices': 100, 'maxEmployees': 100},
      'features': {'ownerWebPanel': true},
    });
    final invoice = OwnerInvoice.fromMap({
      'id': 'invoice-1',
      'status': 'paid',
      'amountCents': 12990,
      'payload': {'token': 'secret'},
    });
    final device = OwnerDevice.fromMap({
      'id': 'device-1',
      'clientInstanceId': 'full-client-instance-id',
      'maskedClientInstanceId': 'full...e-id',
      'status': 'ACTIVE',
    });
    final employees = OwnerEmployeesPlaceholder.fromMap({
      'items': [],
      'count': 0,
      'available': false,
      'reason': 'EMPLOYEES_NOT_IMPLEMENTED',
    });
    final dashboard = OwnerBusinessDashboard.fromMap({
      'sales': {'todayAmountCents': null},
      'employees': {
        'available': false,
        'reason': 'EMPLOYEE_REPORTS_NOT_AVAILABLE',
        'inviteTokenHash': 'secret-hash',
      },
      'alerts': [],
    });
    final sales = OwnerSalesSummary.fromMap({
      ..._salesSummaryPayload(),
      'byPaymentMethod': [
        {
          'key': 'pm:vale_interno',
          'label': '[pm:vale_interno]',
          'totalAmountCents': 1000,
          'count': 1,
        },
      ],
      'recentSales': {
        ...(_salesSummaryPayload()['recentSales'] as Map<String, dynamic>),
        'items': [
          {
            'title': 'Venda recebida',
            'receiptNumber': 'sale-very-long-internal-id-123456',
            'paymentMethod': '[pm:dinheiro]',
            'totalAmountCents': 1000,
            'soldAt': '2026-05-10T00:00:00.000Z',
          },
        ],
      },
      'payload': {'token': 'secret'},
    });

    expect(billing.maskedProviderSubscriptionId, 'prea...9999');
    expect(invoice.amountCents, 12990);
    expect(device.maskedClientInstanceId, 'full...e-id');
    expect(employees.available, false);
    expect(employees.reason, 'EMPLOYEES_NOT_IMPLEMENTED');
    expect(dashboard.sales.todayAmountCents, isNull);
    expect(dashboard.employees.reason, 'EMPLOYEE_REPORTS_NOT_AVAILABLE');
    expect(sales.recentSales.items.single.receiptNumber, isNull);
    expect(sales.recentSales.items.single.paymentMethod, 'Dinheiro');
    expect(sales.byPaymentMethod.single.label, 'Outro');
  });

  test('api service calls only auth and owner endpoints', () async {
    final fakeClient = _FakeHttpClient((request) {
      switch (request.url.path) {
        case '/api/auth/login':
          return _jsonResponse(_loginPayload());
        case '/api/owner/company':
          return _jsonResponse(_companyPayload());
        case '/api/owner/dashboard':
          return _jsonResponse(_dashboardPayload());
        case '/api/owner/dashboard/business':
          return _jsonResponse(_businessDashboardPayload());
        case '/api/owner/reports/sales-summary':
          return _jsonResponse(_salesSummaryPayload());
        case '/api/owner/reports/products':
          return _jsonResponse(_productsReportPayload());
        case '/api/owner/stock/summary':
          return _jsonResponse(_stockSummaryPayload());
        case '/api/owner/crm/summary':
          return _jsonResponse(_crmSummaryPayload());
        case '/api/owner/crm/customers':
          return _jsonResponse(_crmCustomersPayload());
        case '/api/owner/crm/customers/customer-1':
          return _jsonResponse(_crmCustomerDetailPayload());
        case '/api/owner/financial/receivables':
          return _jsonResponse(_receivablesPayload());
        case '/api/owner/reports/employees':
          return _jsonResponse(_employeeReportsPayload());
        case '/api/owner/reports/catalog':
          return _jsonResponse(_reportsCatalogPayload());
        case '/api/owner/billing/status':
          return _jsonResponse(_billingPayload());
        case '/api/owner/billing/invoices':
          return _jsonResponse(_invoicesPayload());
        case '/api/owner/employees':
          return _jsonResponse(_employeesPayload());
        case '/api/owner/devices':
          return _jsonResponse(_devicesPayload());
        default:
          return http.Response('not found', 404);
      }
    });
    final storage = OwnerAuthStorage();
    await storage.saveTokens(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
    );
    final service = OwnerApiService(
      apiClient: OwnerApiClient(
        baseUrl: 'https://api.tatuzin.com.br/api',
        authStorage: storage,
        httpClient: fakeClient,
      ),
      authStorage: storage,
    );

    await service.login(email: 'owner@tatuzin.com', password: 'secret123');
    await service.getCompany();
    await service.getDashboard();
    await service.getBusinessDashboard();
    await service.getSalesSummary();
    await service.getProductsReport();
    await service.getStockSummary();
    await service.getCrmSummary();
    await service.getCrmCustomers();
    await service.getCrmCustomer('customer-1');
    await service.getReceivables();
    await service.getEmployeeReports();
    await service.getReportsCatalog();
    await service.getBillingStatus();
    await service.getBillingInvoices(
      query: const OwnerInvoicesQuery(page: 2, pageSize: 10, status: 'paid'),
    );
    await service.getEmployees();
    await service.getDevices();

    final paths = fakeClient.requests
        .map((request) => request.url.path)
        .toList();
    expect(paths, contains('/api/auth/login'));
    expect(paths, contains('/api/owner/company'));
    expect(paths, contains('/api/owner/dashboard'));
    expect(paths, contains('/api/owner/dashboard/business'));
    expect(paths, contains('/api/owner/reports/sales-summary'));
    expect(paths, contains('/api/owner/reports/products'));
    expect(paths, contains('/api/owner/stock/summary'));
    expect(paths, contains('/api/owner/crm/summary'));
    expect(paths, contains('/api/owner/crm/customers'));
    expect(paths, contains('/api/owner/crm/customers/customer-1'));
    expect(paths, contains('/api/owner/financial/receivables'));
    expect(paths, contains('/api/owner/reports/employees'));
    expect(paths, contains('/api/owner/reports/catalog'));
    expect(paths, contains('/api/owner/billing/status'));
    expect(paths, contains('/api/owner/billing/invoices'));
    expect(paths, contains('/api/owner/employees'));
    expect(paths, contains('/api/owner/devices'));
    expect(paths.any((path) => path.startsWith('/api/admin/')), false);
    expect(paths.any((path) => path.startsWith('/api/billing/')), false);
    expect(paths.any((path) => path.startsWith('/api/employees/')), false);
    expect(paths.any((path) => path.startsWith('/api/sync/')), false);
  });

  test('source does not call admin APIs or owner write endpoints', () {
    final source = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .map((file) => file.readAsStringSync())
        .join('\n');

    expect(source, isNot(contains('/api/admin')));
    expect(source, isNot(contains('/admin/')));
    expect(
      RegExp(
        r'''(?:postJson|putJson|patchJson|deleteJson)\(\s*['"]/owner/''',
      ).hasMatch(source),
      isFalse,
    );
    expect(
      RegExp(r'''_send\('(?:PUT|PATCH|DELETE)' ''').hasMatch(source),
      isFalse,
    );
  });

  test('api client clears local session on final 401', () async {
    final fakeClient = _FakeHttpClient((request) {
      return _jsonResponse({
        'code': 'AUTH_REQUIRED',
        'message': 'auth required',
      }, status: 401);
    });
    final storage = OwnerAuthStorage();
    await storage.saveTokens(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
    );
    final service = OwnerApiService(
      apiClient: OwnerApiClient(
        baseUrl: 'https://api.tatuzin.com.br/api',
        authStorage: storage,
        httpClient: fakeClient,
      ),
      authStorage: storage,
    );

    await expectLater(service.getCompany(), throwsA(isA<OwnerApiException>()));

    expect(await storage.readAccessToken(), isNull);
    expect(await storage.readRefreshToken(), isNull);
  });

  test('api client refreshes token and retries once on 401', () async {
    var ownerCompanyCalls = 0;
    final fakeClient = _FakeHttpClient((request) {
      if (request.url.path == '/api/owner/company') {
        ownerCompanyCalls++;
        if (ownerCompanyCalls == 1) {
          return _jsonResponse({
            'code': 'AUTH_REQUIRED',
            'message': 'expired',
          }, status: 401);
        }
        return _jsonResponse(_companyPayload());
      }
      if (request.url.path == '/api/auth/refresh') {
        return _jsonResponse({
          ..._loginPayload(),
          'accessToken': 'next-access-token',
          'refreshToken': 'next-refresh-token',
        });
      }
      return http.Response('not found', 404);
    });
    final storage = OwnerAuthStorage();
    await storage.ensureClientContext();
    await storage.saveTokens(
      accessToken: 'old-access-token',
      refreshToken: 'old-refresh-token',
    );
    final service = OwnerApiService(
      apiClient: OwnerApiClient(
        baseUrl: 'https://api.tatuzin.com.br/api',
        authStorage: storage,
        httpClient: fakeClient,
      ),
      authStorage: storage,
    );

    final company = await service.getCompany();

    expect(company.companyId, 'company-1');
    expect(await storage.readAccessToken(), 'next-access-token');
    expect(await storage.readRefreshToken(), 'next-refresh-token');
    final paths = fakeClient.requests.map((request) => request.url.path);
    expect(paths.where((path) => path == '/api/owner/company').length, 2);
    expect(paths, contains('/api/auth/refresh'));
  });

  test('logout calls auth logout and no owner write endpoint', () async {
    final fakeClient = _FakeHttpClient((request) {
      if (request.url.path == '/api/auth/logout') {
        return http.Response('', 204);
      }
      return http.Response('not found', 404);
    });
    final storage = OwnerAuthStorage();
    final service = OwnerApiService(
      apiClient: OwnerApiClient(
        baseUrl: 'https://api.tatuzin.com.br/api',
        authStorage: storage,
        httpClient: fakeClient,
      ),
      authStorage: storage,
    );

    await service.logout('access-token');

    expect(fakeClient.requests.single.url.path, '/api/auth/logout');
    expect(fakeClient.requests.single.method, 'POST');
    expect(
      fakeClient.requests.any(
        (request) =>
            request.url.path.startsWith('/api/owner/') &&
            request.method != 'GET',
      ),
      false,
    );
  });

  test('owner access errors are mapped by backend code', () {
    expect(
      describeOwnerError(
        const OwnerApiException(
          message: 'raw',
          statusCode: 403,
          code: 'OWNER_REQUIRED',
        ),
      ),
      'Apenas o dono da empresa pode acessar este painel.',
    );
    expect(
      describeOwnerError(
        const OwnerApiException(
          message: 'raw',
          statusCode: 403,
          code: 'FEATURE_NOT_AVAILABLE',
        ),
      ),
      'Painel da empresa está disponível no plano PRO.',
    );
    expect(
      describeOwnerError(TimeoutException('network')),
      'Não foi possível carregar o painel agora. Tente novamente.',
    );
  });

  testWidgets('dashboard renders management language', (tester) async {
    await tester.pumpWidget(
      _withProviders(
        overrides: [
          ownerDashboardProvider.overrideWith((ref) async {
            return OwnerBusinessDashboard.fromMap(_businessDashboardPayload());
          }),
        ],
        child: const OwnerDashboardPage(),
      ),
    );
    await tester.pump();

    expect(find.text('Dashboard da empresa'), findsOneWidget);
    expect(find.text('Vendas hoje'), findsOneWidget);
    expect(find.text('Faturamento do mês'), findsOneWidget);
    expect(find.text('R\$ 250,00'), findsOneWidget);
    expect(find.text('R\$ 4250,00'), findsOneWidget);
    expect(find.text('Contas a receber'), findsOneWidget);
    expect(find.text('Top produtos'), findsOneWidget);
    expect(find.text('Vendas por funcionário'), findsOneWidget);
    expect(find.textContaining('Sync'), findsNothing);
    expect(find.textContaining('ownerWebPanel'), findsNothing);
  });

  testWidgets('dashboard treats null values and unavailable employees safely', (
    tester,
  ) async {
    await tester.pumpWidget(
      _withProviders(
        overrides: [
          ownerDashboardProvider.overrideWith((ref) async {
            return OwnerBusinessDashboard.fromMap({
              'period': {'startDate': '2026-05-01', 'endDate': '2026-05-30'},
              'sales': {
                'todayAmountCents': null,
                'monthAmountCents': null,
                'todayCount': null,
                'monthCount': null,
                'averageTicketCents': null,
              },
              'receivables': {},
              'customers': {},
              'products': {},
              'employees': {
                'available': false,
                'reason': 'EMPLOYEE_REPORTS_NOT_AVAILABLE',
                'topPerformers': [],
              },
              'alerts': [],
            });
          }),
        ],
        child: const OwnerDashboardPage(),
      ),
    );
    await tester.pump();

    expect(find.text('Sem dados'), findsWidgets);
    expect(
      find.text(
        'Os relatórios de funcionários serão liberados quando houver vendas vinculadas aos usuários.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('0,00'), findsNothing);
  });

  testWidgets('business pages render friendly empty states', (tester) async {
    await tester.pumpWidget(
      _withProviders(
        overrides: [
          ownerSalesSummaryProvider.overrideWith((ref) async {
            return OwnerSalesSummary.fromMap(_salesSummaryPayload());
          }),
          ownerCrmSummaryProvider.overrideWith((ref) async {
            return OwnerCrmSummary.fromMap(_crmSummaryPayload());
          }),
          ownerCrmCustomersProvider.overrideWith((ref) async {
            return OwnerCrmCustomerPage.fromMap(_crmCustomersPayload());
          }),
          ownerReceivablesProvider.overrideWith((ref) async {
            return OwnerReceivablesReport.fromMap(_receivablesPayload());
          }),
          ownerProductsReportProvider.overrideWith((ref) async {
            return OwnerProductsReport.fromMap(_productsReportPayload());
          }),
          ownerStockSummaryProvider.overrideWith((ref) async {
            return OwnerStockSummary.fromMap(_stockSummaryPayload());
          }),
          ownerReportsCatalogProvider.overrideWith((ref) async {
            return OwnerReportsCatalog.fromMap(_reportsCatalogPayload());
          }),
        ],
        child: const Column(
          children: [
            OwnerSalesPage(),
            OwnerClientsPage(),
            OwnerFinancePage(),
            OwnerProductsPage(),
            OwnerReportsPage(),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Vendas'), findsWidgets);
    expect(find.text('Clientes / CRM'), findsOneWidget);
    expect(find.text('Fiado e financeiro'), findsOneWidget);
    expect(find.text('Produtos e estoque'), findsOneWidget);
    expect(find.text('Relatórios'), findsOneWidget);
    expect(find.text('Lucratividade'), findsOneWidget);
    expect(find.text('R\$ 198,50'), findsWidgets);
    expect(find.text('Cliente Maria'), findsWidgets);
    expect(find.textContaining('Sem vencimento informado'), findsOneWidget);
    expect(find.text('Produto A'), findsWidgets);
    expect(find.text('Em preparação'), findsWidgets);
    expect(find.textContaining('endpoint'), findsNothing);
    expect(find.textContaining('payload'), findsNothing);
    expect(find.textContaining('[pm:dinheiro]'), findsNothing);
    expect(find.textContaining('sale-very-long-internal-id'), findsNothing);
  });

  testWidgets('reports catalog translates unavailable reasons', (tester) async {
    await tester.pumpWidget(
      _withProviders(
        overrides: [
          ownerReportsCatalogProvider.overrideWith((ref) async {
            return OwnerReportsCatalog.fromMap(_reportsCatalogPayload());
          }),
        ],
        child: const OwnerReportsPage(),
      ),
    );
    await tester.pump();

    expect(find.text('Compras'), findsOneWidget);
    expect(
      find.text('Este relatório será liberado em uma próxima atualização.'),
      findsOneWidget,
    );
    expect(
      find.text('Será exibido quando houver vendas vinculadas aos usuários.'),
      findsOneWidget,
    );
    expect(find.textContaining('PURCHASE_REPORTS_NOT_AVAILABLE'), findsNothing);
    expect(find.textContaining('EMPLOYEE_REPORTS_NOT_AVAILABLE'), findsNothing);
  });

  testWidgets('billing page hides full provider id and payload', (
    tester,
  ) async {
    await tester.pumpWidget(
      _withProviders(
        overrides: [
          ownerBillingStatusProvider.overrideWith((ref) async {
            return OwnerBillingStatus.fromMap({
              ..._billingPayload(),
              'providerSubscriptionId': 'preapproval-owner-secret-9999',
            });
          }),
          ownerBillingInvoicesProvider.overrideWith((ref) async {
            return OwnerInvoicesPage.fromMap({
              ..._invoicesPayload(),
              'items': [
                {
                  ...(_invoicesPayload()['items'] as List).first
                      as Map<String, Object?>,
                  'payload': {'token': 'invoice-token'},
                },
              ],
            });
          }),
        ],
        child: const OwnerBillingPage(),
      ),
    );
    await tester.pump();

    expect(find.text('Cobrança vinculada'), findsOneWidget);
    expect(find.textContaining('prea...9999'), findsNothing);
    expect(find.textContaining('preapproval-owner-secret-9999'), findsNothing);
    expect(find.textContaining('invoice-token'), findsNothing);
    expect(find.textContaining('payload'), findsNothing);
  });

  testWidgets('employees placeholder renders without token or hash', (
    tester,
  ) async {
    await tester.pumpWidget(
      _withProviders(
        overrides: [
          ownerEmployeeReportsProvider.overrideWith((ref) async {
            return OwnerEmployeeReports.fromMap(
              _employeeReportsPayload(available: false),
            );
          }),
        ],
        child: const OwnerEmployeesPage(),
      ),
    );
    await tester.pump();

    expect(find.text('Desempenho da equipe'), findsOneWidget);
    expect(
      find.text('Relatórios de funcionários em preparação'),
      findsOneWidget,
    );
    expect(find.textContaining('inviteTokenHash'), findsNothing);
    expect(find.textContaining('token'), findsNothing);
  });

  testWidgets('devices page hides technical ids', (tester) async {
    await tester.pumpWidget(
      _withProviders(
        overrides: [
          ownerDevicesProvider.overrideWith((ref) async {
            return OwnerDevicesResult.fromMap(_devicesPayload());
          }),
        ],
        child: const OwnerDevicesPage(),
      ),
    );
    await tester.pump();

    expect(find.textContaining('own-1234-secret-client'), findsNothing);
    expect(find.textContaining('own-...7890'), findsNothing);
    expect(find.text('PDV Principal'), findsOneWidget);
    expect(find.textContaining('Aplicativo Android'), findsOneWidget);
  });

  testWidgets('settings keeps devices friendly and secondary', (tester) async {
    await tester.pumpWidget(
      _withProviders(
        overrides: [
          ownerCompanyProvider.overrideWith((ref) async {
            return OwnerCompanySummary.fromMap(_companyPayload());
          }),
          ownerDevicesProvider.overrideWith((ref) async {
            return OwnerDevicesResult.fromMap({
              'items': [
                {
                  'id': 'device-1',
                  'maskedClientInstanceId': 'own-...7890',
                  'clientInstanceId': 'own-1234-secret-client-7890',
                  'deviceLabel': 'Tatuzin Owner Web',
                  'platform': 'web',
                  'appVersion': 'owner-web',
                  'status': 'ACTIVE',
                  'lastSeenAt': '2026-05-03T00:00:00.000Z',
                },
              ],
              'count': 1,
              'limits': {'maxDevices': 100},
            });
          }),
        ],
        child: const OwnerSettingsPage(),
      ),
    );
    await tester.pump();

    expect(find.text('Configurações'), findsOneWidget);
    expect(find.text('Dispositivos conectados'), findsOneWidget);
    expect(find.text('Painel da empresa'), findsOneWidget);
    expect(find.textContaining('Tatuzin Owner Web'), findsNothing);
    expect(find.textContaining('owner-web'), findsNothing);
    expect(find.textContaining('own-1234-secret-client'), findsNothing);
    expect(find.textContaining('own-...7890'), findsNothing);
  });
}

Widget _withProviders({
  required List<Override> overrides,
  required Widget child,
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: child,
        ),
      ),
    ),
  );
}

class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient(this.handler);

  final http.Response Function(http.BaseRequest request) handler;
  final List<http.BaseRequest> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    final response = handler(request);
    return http.StreamedResponse(
      Stream<List<int>>.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}

class _ReadyOwnerAuthController extends OwnerAuthController {
  _ReadyOwnerAuthController()
    : super(
        apiService: _dummyApiService(),
        authStorage: OwnerAuthStorage(),
        restoreOnStart: false,
      );

  @override
  OwnerSession? get session => OwnerSession.fromLoginResponse(_loginPayload());

  @override
  bool get isAuthenticated => true;

  @override
  bool get isRestoring => false;

  @override
  Future<void> logout() async {}
}

OwnerApiService _dummyApiService() {
  final storage = OwnerAuthStorage();
  return OwnerApiService(
    apiClient: OwnerApiClient(
      baseUrl: 'https://api.tatuzin.com.br/api',
      authStorage: storage,
      httpClient: _FakeHttpClient((request) => http.Response('', 204)),
    ),
    authStorage: storage,
  );
}

http.Response _jsonResponse(Map<String, dynamic> payload, {int status = 200}) {
  return http.Response(
    jsonEncode(payload),
    status,
    headers: const {'content-type': 'application/json'},
  );
}

Map<String, dynamic> _loginPayload() {
  return {
    'accessToken': 'access-token',
    'refreshToken': 'refresh-token',
    'tokenType': 'Bearer',
    'user': {
      'id': 'user-1',
      'email': 'owner@tatuzin.com',
      'name': 'Owner',
      'isPlatformAdmin': false,
    },
    'company': {
      'id': 'company-1',
      'name': 'Loja Tatuzin',
      'legalName': 'Loja Tatuzin LTDA',
      'documentNumber': null,
      'slug': 'loja-tatuzin',
      'license': {
        'id': 'license-1',
        'plan': 'PRO',
        'status': 'ACTIVE',
        'startsAt': '2026-05-01T00:00:00.000Z',
        'expiresAt': null,
        'maxDevices': 100,
        'syncEnabled': true,
      },
    },
    'membership': {'id': 'membership-1', 'role': 'OWNER', 'isDefault': true},
    'session': {'id': 'session-1'},
  };
}

Map<String, dynamic> _companyPayload() {
  return {
    'companyId': 'company-1',
    'name': 'Loja Tatuzin',
    'setupCompleted': true,
    'createdAt': '2026-05-01T00:00:00.000Z',
    'membership': {'id': 'membership-1', 'role': 'OWNER'},
    'license': {
      'plan': 'PRO',
      'rawPlan': 'PRO',
      'status': 'ACTIVE',
      'currentPeriodEnd': '2026-06-01T00:00:00.000Z',
      'nextPaymentDate': '2026-06-01T00:00:00.000Z',
      'cancelAtPeriodEnd': false,
      'pendingPlan': null,
      'billingSubscriptionStatus': 'ACTIVE',
    },
    'limits': {
      'maxDevices': 100,
      'maxEmployees': 100,
      'reportPeriods': ['daily', 'monthly'],
    },
    'features': {'ownerWebPanel': true},
  };
}

Map<String, dynamic> _billingPayload() {
  return {
    'companyId': 'company-1',
    'plan': 'PRO',
    'status': 'ACTIVE',
    'currentPeriodStart': '2026-05-01T00:00:00.000Z',
    'currentPeriodEnd': '2026-06-01T00:00:00.000Z',
    'provider': 'mercadopago',
    'hasProviderSubscription': true,
    'maskedProviderSubscriptionId': 'prea...9999',
    'nextPaymentDate': '2026-06-01T00:00:00.000Z',
    'cancelAtPeriodEnd': false,
    'pendingPlan': null,
    'billingSubscriptionStatus': 'ACTIVE',
    'limits': {'maxDevices': 100, 'maxEmployees': 100},
    'features': {'ownerWebPanel': true},
  };
}

Map<String, dynamic> _invoicesPayload() {
  return {
    'items': [
      {
        'id': 'invoice-1',
        'provider': 'mercadopago',
        'status': 'paid',
        'amountCents': 12990,
        'currency': 'BRL',
        'dueAt': '2026-05-10T00:00:00.000Z',
        'paidAt': '2026-05-09T00:00:00.000Z',
        'invoiceUrl': null,
        'createdAt': '2026-05-09T00:00:00.000Z',
      },
    ],
    'page': 1,
    'pageSize': 10,
    'total': 1,
    'count': 1,
    'hasNext': false,
    'hasPrevious': false,
  };
}

Map<String, dynamic> _employeesPayload() {
  return {
    'items': [],
    'count': 0,
    'available': false,
    'reason': 'EMPLOYEES_NOT_IMPLEMENTED',
  };
}

Map<String, dynamic> _devicesPayload() {
  return {
    'items': [
      {
        'id': 'device-1',
        'maskedClientInstanceId': 'own-...7890',
        'clientInstanceId': 'own-1234-secret-client-7890',
        'deviceLabel': 'PDV Principal',
        'platform': 'android',
        'appVersion': '1.0.0',
        'status': 'ACTIVE',
        'createdAt': '2026-05-01T00:00:00.000Z',
        'updatedAt': '2026-05-02T00:00:00.000Z',
        'lastSeenAt': '2026-05-03T00:00:00.000Z',
      },
    ],
    'count': 1,
    'limits': {'maxDevices': 100},
  };
}

Map<String, dynamic> _businessDashboardPayload() {
  return {
    'period': {
      'startDate': '2026-05-01',
      'endDate': '2026-05-30',
      'timezone': 'UTC',
    },
    'sales': {
      'todayAmountCents': 25000,
      'monthAmountCents': 425000,
      'todayCount': 2,
      'monthCount': 20,
      'averageTicketCents': 21250,
    },
    'receivables': {
      'openAmountCents': 19850,
      'overdueAmountCents': 0,
      'openCount': 1,
      'overdueCount': 0,
    },
    'customers': {
      'total': 12,
      'active': 8,
      'inactive': 4,
      'newThisMonth': 2,
      'topCustomers': [_crmCustomerItemPayload()],
    },
    'products': {
      'total': 30,
      'lowStock': 2,
      'outOfStock': 1,
      'topSelling': [_productSalesItemPayload()],
    },
    'employees': {
      'available': false,
      'reason': 'EMPLOYEE_REPORTS_NOT_AVAILABLE',
      'topPerformers': [],
    },
    'alerts': [
      {
        'key': 'OPEN_RECEIVABLES',
        'severity': 'info',
        'title': 'Contas a receber',
        'message': 'Há valores em aberto no fiado para acompanhar.',
        'count': 1,
      },
    ],
  };
}

Map<String, dynamic> _salesSummaryPayload() {
  return {
    'period': {
      'startDate': '2026-05-01',
      'endDate': '2026-05-30',
      'timezone': 'UTC',
    },
    'totalAmountCents': 19850,
    'totalCount': 2,
    'averageTicketCents': 9925,
    'series': [
      {
        'date': '2026-05-10',
        'totalAmountCents': 19850,
        'totalCount': 2,
        'averageTicketCents': 9925,
      },
    ],
    'byPaymentMethod': [
      {
        'key': 'dinheiro',
        'label': 'Dinheiro',
        'totalAmountCents': 19850,
        'count': 2,
      },
    ],
    'recentSales': {
      'items': [
        {
          'title': 'Venda recebida',
          'receiptNumber': 'sale-very-long-internal-id-123456',
          'customerName': 'Cliente Maria',
          'paymentMethod': 'Dinheiro',
          'totalAmountCents': 19850,
          'status': 'active',
          'soldAt': '2026-05-10T00:00:00.000Z',
          'canceledAt': null,
        },
      ],
      'page': 1,
      'pageSize': 10,
      'total': 1,
      'count': 1,
      'hasNext': false,
      'hasPrevious': false,
    },
  };
}

Map<String, dynamic> _productsReportPayload() {
  return {
    'period': {
      'startDate': '2026-05-01',
      'endDate': '2026-05-30',
      'timezone': 'UTC',
    },
    'topSellingProducts': [_productSalesItemPayload()],
    'lowSellingProducts': [],
    'byCategory': [
      {
        'categoryId': 'category-1',
        'categoryName': 'Bebidas',
        'quantityMil': 3000,
        'amountCents': 19850,
        'salesCount': 2,
      },
    ],
    'stockSummary': {
      'totalProducts': 30,
      'lowStockCount': 2,
      'outOfStockCount': 1,
      'totalEstimatedCostCents': 150000,
    },
  };
}

Map<String, dynamic> _stockSummaryPayload() {
  return {
    'totalProducts': 30,
    'lowStockCount': 2,
    'outOfStockCount': 1,
    'totalEstimatedCostCents': 150000,
    'lowStockThresholdMil': 1000,
    'itemsLowStock': [
      {
        'id': 'stock-1',
        'productId': 'product-1',
        'productVariantId': null,
        'name': 'Produto Baixo',
        'variantName': null,
        'sku': 'SKU-1',
        'currentStockMil': 500,
        'costPriceCents': 1000,
        'salePriceCents': 1990,
        'estimatedCostCents': 500,
      },
    ],
    'itemsOutOfStock': [
      {
        'id': 'stock-2',
        'productId': 'product-2',
        'productVariantId': null,
        'name': 'Produto Zerado',
        'variantName': null,
        'sku': 'SKU-2',
        'currentStockMil': 0,
        'costPriceCents': 1000,
        'salePriceCents': 1990,
        'estimatedCostCents': 0,
      },
    ],
  };
}

Map<String, dynamic> _crmSummaryPayload() {
  return {
    'inactiveAfterDays': 90,
    'totalCustomers': 12,
    'activeCustomers': 8,
    'inactiveCustomers': 4,
    'newCustomersThisMonth': 2,
    'customersWithReceivables': 1,
    'topCustomers': [_crmCustomerItemPayload()],
    'customersAtRisk': [],
  };
}

Map<String, dynamic> _crmCustomersPayload() {
  return {
    'items': [_crmCustomerItemPayload()],
    'page': 1,
    'pageSize': 20,
    'total': 1,
    'count': 1,
    'hasNext': false,
    'hasPrevious': false,
  };
}

Map<String, dynamic> _crmCustomerDetailPayload() {
  return {
    'customer': _crmCustomerItemPayload(),
    'topProducts': [_productSalesItemPayload()],
    'recentPurchases': [
      {
        'title': 'Venda recebida',
        'receiptNumber': '123',
        'paymentMethod': 'Dinheiro',
        'totalAmountCents': 19850,
        'status': 'active',
        'soldAt': '2026-05-10T00:00:00.000Z',
      },
    ],
    'receivables': {
      'openAmountCents': 19850,
      'overdueAmountCents': 0,
      'openCount': 1,
      'overdueCount': 0,
      'paidCount': 0,
    },
    'timeline': [],
  };
}

Map<String, dynamic> _receivablesPayload() {
  return {
    'summary': {
      'openAmountCents': 19850,
      'overdueAmountCents': 0,
      'openCount': 1,
      'overdueCount': 0,
      'paidCount': 0,
      'receivedThisMonthCents': 5000,
    },
    'items': {
      'items': [
        {
          'id': 'customer-1',
          'customerId': 'customer-1',
          'customerName': 'Cliente Maria',
          'openAmountCents': 19850,
          'overdueAmountCents': 0,
          'paidAmountCents': 5000,
          'totalAmountCents': 24850,
          'salesCount': 2,
          'dueDate': null,
          'status': 'open',
        },
      ],
      'page': 1,
      'pageSize': 20,
      'total': 1,
      'count': 1,
      'hasNext': false,
      'hasPrevious': false,
    },
  };
}

Map<String, dynamic> _employeeReportsPayload({bool available = true}) {
  return {
    'available': available,
    'reason': available ? null : 'EMPLOYEE_REPORTS_NOT_AVAILABLE',
    'period': {
      'startDate': '2026-05-01',
      'endDate': '2026-05-30',
      'timezone': 'UTC',
    },
    'topEmployees': available
        ? [
            {
              'employeeId': 'employee-1',
              'userId': 'user-1',
              'name': 'Ana Caixa',
              'role': 'CASHIER',
              'status': 'ACTIVE',
              'salesAmountCents': 19850,
              'salesCount': 2,
              'averageTicketCents': 9925,
              'lastSaleAt': '2026-05-10T00:00:00.000Z',
            },
          ]
        : [],
  };
}

Map<String, dynamic> _reportsCatalogPayload() {
  return {
    'items': [
      {
        'key': 'sales',
        'title': 'Vendas',
        'description': 'Resumo de vendas e formas de pagamento.',
        'available': true,
        'reason': null,
      },
      {
        'key': 'products',
        'title': 'Produtos',
        'description': 'Produtos mais vendidos e itens com pouca saída.',
        'available': true,
        'reason': null,
      },
      {
        'key': 'cash',
        'title': 'Caixa',
        'description': 'Indicadores de caixa.',
        'available': true,
        'reason': null,
      },
      {
        'key': 'stock',
        'title': 'Estoque',
        'description': 'Produtos zerados e baixo estoque.',
        'available': true,
        'reason': null,
      },
      {
        'key': 'customers',
        'title': 'Clientes',
        'description': 'CRM e relacionamento.',
        'available': true,
        'reason': null,
      },
      {
        'key': 'purchases',
        'title': 'Compras',
        'description': 'Compras por fornecedor.',
        'available': false,
        'reason': 'PURCHASE_REPORTS_NOT_AVAILABLE',
      },
      {
        'key': 'profitability',
        'title': 'Lucratividade',
        'description': 'Receita, custo e margem.',
        'available': true,
        'reason': null,
      },
      {
        'key': 'employees',
        'title': 'Funcionários',
        'description': 'Desempenho por funcionário.',
        'available': false,
        'reason': 'EMPLOYEE_REPORTS_NOT_AVAILABLE',
      },
    ],
  };
}

Map<String, dynamic> _crmCustomerItemPayload() {
  return {
    'id': 'customer-1',
    'name': 'Cliente Maria',
    'phone': '(11) 99999-0000',
    'totalPurchasedCents': 19850,
    'purchasesCount': 2,
    'averageTicketCents': 9925,
    'lastPurchaseAt': '2026-05-10T00:00:00.000Z',
    'openReceivableAmountCents': 19850,
    'status': 'active',
    'statusLabel': 'Ativo',
    'tags': [],
  };
}

Map<String, dynamic> _productSalesItemPayload() {
  return {
    'productId': 'product-1',
    'productName': 'Produto A',
    'quantityMil': 3000,
    'salesCount': 2,
    'amountCents': 19850,
    'salePriceCents': 1990,
  };
}

Map<String, dynamic> _dashboardPayload() {
  return {
    'company': {
      'companyId': 'company-1',
      'name': 'Loja Tatuzin',
      'setupCompleted': true,
    },
    'billing': {
      'plan': 'PRO',
      'status': 'ACTIVE',
      'nextPaymentDate': '2026-06-01T00:00:00.000Z',
      'cancelAtPeriodEnd': false,
      'pendingPlan': null,
    },
    'employees': {
      'active': 0,
      'invited': 0,
      'disabled': 0,
      'maxEmployees': 100,
      'available': false,
      'reason': 'EMPLOYEES_NOT_IMPLEMENTED',
    },
    'devices': {
      'active': 1,
      'blocked': 0,
      'pending': 0,
      'revoked': 0,
      'maxDevices': 100,
    },
    'sync': {'lastSyncAt': null, 'pendingEvents': 0, 'openConflicts': 0},
    'reports': null,
  };
}
