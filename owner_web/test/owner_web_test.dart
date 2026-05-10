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

    expect(billing.maskedProviderSubscriptionId, 'prea...9999');
    expect(invoice.amountCents, 12990);
    expect(device.maskedClientInstanceId, 'full...e-id');
    expect(employees.available, false);
    expect(employees.reason, 'EMPLOYEES_NOT_IMPLEMENTED');
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
            return OwnerDashboard.fromMap(_dashboardPayload());
          }),
        ],
        child: const OwnerDashboardPage(),
      ),
    );
    await tester.pump();

    expect(find.text('Dashboard da empresa'), findsOneWidget);
    expect(find.text('Vendas hoje'), findsOneWidget);
    expect(find.text('Faturamento do mês'), findsOneWidget);
    expect(find.text('Contas a receber'), findsOneWidget);
    expect(find.text('Top produtos'), findsOneWidget);
    expect(find.text('Vendas por funcionário'), findsOneWidget);
    expect(find.textContaining('Sync'), findsNothing);
    expect(find.textContaining('ownerWebPanel'), findsNothing);
  });

  testWidgets('business pages render friendly empty states', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                OwnerSalesPage(),
                OwnerClientsPage(),
                OwnerFinancePage(),
                OwnerProductsPage(),
                OwnerReportsPage(),
              ],
            ),
          ),
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
    expect(
      find.text(
        'Os indicadores de CRM serão liberados em uma próxima atualização.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('endpoint'), findsNothing);
    expect(find.textContaining('payload'), findsNothing);
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
          ownerEmployeesProvider.overrideWith((ref) async {
            return OwnerEmployeesPlaceholder.fromMap(_employeesPayload());
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
