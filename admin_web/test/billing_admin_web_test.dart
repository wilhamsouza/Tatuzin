import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/testing.dart';
import 'package:tatuzin_admin_web/src/core/auth/admin_auth_storage.dart';
import 'package:tatuzin_admin_web/src/core/auth/admin_debug_log.dart';
import 'package:tatuzin_admin_web/src/core/auth/admin_providers.dart';
import 'package:tatuzin_admin_web/src/core/models/admin_billing_models.dart';
import 'package:tatuzin_admin_web/src/core/models/admin_models.dart';
import 'package:tatuzin_admin_web/src/core/network/admin_api_client.dart';
import 'package:tatuzin_admin_web/src/core/network/admin_api_service.dart';
import 'package:tatuzin_admin_web/src/features/billing/presentation/billing_admin_page.dart';
import 'package:tatuzin_admin_web/src/features/billing/presentation/billing_company_detail_page.dart';
import 'package:tatuzin_admin_web/src/features/licenses/presentation/licenses_page.dart';

void main() {
  test('sanitiza payloads defensivamente e mascara URLs de checkout', () {
    final sanitized = sanitizeAdminBillingValue({
      'Authorization': 'Bearer very-secret-token',
      'access_token': 'mp-access-token',
      'x-signature': 'signature',
      'checkoutUrl':
          'https://www.mercadopago.com.br/checkout/v1/redirect?token=abc',
      'init_point': 'https://www.mercadopago.com/init?token=abc',
      'sandbox_init_point': 'https://sandbox.mercadopago.com/init?token=def',
      'nested': [
        {'card_number': '4111111111111111', 'status': 'ok'},
      ],
    });

    final rendered = formatSanitizedAdminJson(sanitized);
    expect(rendered, contains('[redacted]'));
    expect(rendered, isNot(contains('very-secret-token')));
    expect(rendered, isNot(contains('mp-access-token')));
    expect(rendered, isNot(contains('4111111111111111')));
    expect(rendered, isNot(contains('token=abc')));
    expect(rendered, isNot(contains('token=def')));
  });

  test('logs nao exibem preview de token', () {
    expect(summarizeToken('abcdef1234567890'), 'present');
    expect(summarizeToken(''), 'empty');
  });

  test('router nao registra rota owner', () {
    final routerSource = File(
      'lib/src/app/admin_web_router.dart',
    ).readAsStringSync();
    expect(routerSource, isNot(contains("path: '/owner'")));
    expect(routerSource, isNot(contains('path: "/owner"')));
  });

  test('AdminApiService bloqueia actions billing sem reason antes da rede', () {
    final service = _FakeAdminApiService();

    expect(
      () => service.refreshBillingCompany(companyId: 'company-1', reason: ''),
      throwsA(isA<AdminApiException>()),
    );
    expect(
      () => service.forceBillingPlan(
        companyId: 'company-1',
        plan: 'PRO',
        reason: ' ',
      ),
      throwsA(isA<AdminApiException>()),
    );
    expect(
      () => service.cancelBillingLocal(
        companyId: 'company-1',
        reason: '',
        effective: 'period_end',
      ),
      throwsA(isA<AdminApiException>()),
    );
  });

  testWidgets('Billing Admin lista empresas com provider mascarado', (
    tester,
  ) async {
    _setLargeViewport(tester);
    await tester.pumpWidget(
      _adminTestApp(
        service: _FakeAdminApiService(),
        child: const BillingAdminPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Billing Admin'), findsOneWidget);
    expect(find.text('Loja Moda Sul'), findsOneWidget);
    expect(find.text('pre_..._7890'), findsOneWidget);
    expect(find.textContaining('preapproval-secret-full-id'), findsNothing);
  });

  testWidgets('Billing Admin abre detalhe ao clicar na empresa', (
    tester,
  ) async {
    _setLargeViewport(tester);
    final service = _FakeAdminApiService();
    await tester.pumpWidget(
      _adminRouterTestApp(service: service, initialLocation: '/billing'),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Loja Moda Sul').first);
    await tester.pumpAndSettle();

    expect(find.text('Billing de Loja Moda Sul'), findsOneWidget);
    expect(service.statusFetchCount, greaterThanOrEqualTo(1));
  });

  testWidgets('Billing Admin renderiza detalhe acessado por deep link', (
    tester,
  ) async {
    _setLargeViewport(tester);
    await tester.pumpWidget(
      _adminRouterTestApp(
        service: _FakeAdminApiService(),
        initialLocation: '/billing/company-1',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Billing de Loja Moda Sul'), findsOneWidget);
    expect(find.text('Dashboard Plataforma'), findsNothing);
  });

  testWidgets('Billing detalhe sanitiza eventos e exige reason no cancel-local', (
    tester,
  ) async {
    _setLargeViewport(tester);
    await tester.pumpWidget(
      _adminTestApp(
        service: _FakeAdminApiService(),
        child: const BillingCompanyDetailPage(companyId: 'company-1'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dado interno de plataforma'), findsOneWidget);
    expect(find.textContaining('preapproval-secret-full-id'), findsOneWidget);

    await tester.tap(find.textContaining('payment.created'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Bearer secret'), findsNothing);
    expect(find.textContaining('token=abc'), findsNothing);
    expect(find.textContaining('[redacted]'), findsWidgets);

    await tester.tap(find.text('Cancel-local'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Esta ação não cancela Mercado Pago. Ela aplica apenas correção local administrativa.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(find.text('Informe um motivo.'), findsOneWidget);
  });

  testWidgets('Billing refresh exige reason', (tester) async {
    _setLargeViewport(tester);
    await tester.pumpWidget(
      _adminTestApp(
        service: _FakeAdminApiService(),
        child: const BillingCompanyDetailPage(companyId: 'company-1'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    expect(find.text('Informe um motivo.'), findsOneWidget);
  });

  testWidgets('Billing force-plan exige reason', (tester) async {
    _setLargeViewport(tester);
    await tester.pumpWidget(
      _adminTestApp(
        service: _FakeAdminApiService(),
        child: const BillingCompanyDetailPage(companyId: 'company-1'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Force-plan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    expect(find.text('Informe um motivo.'), findsOneWidget);
  });

  testWidgets('Billing force-plan permite PRO e recarrega detalhe', (
    tester,
  ) async {
    _setLargeViewport(tester);
    final service = _FakeAdminApiService();
    await tester.pumpWidget(
      _adminTestApp(
        service: service,
        child: const BillingCompanyDetailPage(companyId: 'company-1'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Force-plan'));
    await tester.pumpAndSettle();
    expect(find.text('PRO'), findsWidgets);
    await tester.enterText(find.byType(TextField).last, 'ajuste suporte PRO');
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aplicar force-plan'));
    await tester.pumpAndSettle();

    expect(service.forcePlanCalls, 1);
    expect(service.lastForcePlan, 'PRO');
    expect(service.lastForcePlanStatus, 'ACTIVE');
    expect(service.lastForcePlanReason, 'ajuste suporte PRO');
    expect(service.statusFetchCount, greaterThanOrEqualTo(2));
  });

  testWidgets('/licenses mostra aviso legado e continua acessivel', (
    tester,
  ) async {
    _setLargeViewport(tester);
    await tester.pumpWidget(
      _adminTestApp(
        service: _FakeAdminApiService(),
        child: const LicensesPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Licenças'), findsOneWidget);
    expect(
      find.text(
        'Esta tela usa fluxo legado de licença. Para assinaturas Mercado Pago, use Billing Admin.',
      ),
      findsOneWidget,
    );
  });
}

void _setLargeViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 1200);
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
        path: '/billing',
        builder: (context, state) => const BillingAdminPage(),
      ),
      GoRoute(
        path: '/billing/:companyId',
        builder: (context, state) => BillingCompanyDetailPage(
          companyId: state.pathParameters['companyId'] ?? '',
        ),
      ),
    ],
  );

  return ProviderScope(
    overrides: [adminApiServiceProvider.overrideWithValue(service)],
    child: MaterialApp.router(routerConfig: router),
  );
}

class _FakeAdminApiService extends AdminApiService {
  _FakeAdminApiService()
    : super(
        apiClient: AdminApiClient(
          baseUrl: 'https://api.test/api',
          authStorage: AdminAuthStorage(),
          httpClient: MockClient((request) async {
            throw UnimplementedError(request.url.toString());
          }),
        ),
        authStorage: AdminAuthStorage(),
      );

  int statusFetchCount = 0;
  int forcePlanCalls = 0;
  String? lastForcePlan;
  String? lastForcePlanStatus;
  String? lastForcePlanReason;

  @override
  Future<AdminPaginatedResult<AdminBillingCompanySummary>>
  fetchBillingCompanies({AdminBillingCompaniesQuery? query}) async {
    return AdminPaginatedResult<AdminBillingCompanySummary>(
      items: [
        AdminBillingCompanySummary.fromMap({
          'companyId': 'company-1',
          'companyName': 'Loja Moda Sul',
          'plan': 'PRO',
          'licenseStatus': 'ACTIVE',
          'billingProvider': 'mercadopago',
          'hasProviderSubscription': true,
          'maskedProviderSubscriptionId': 'pre_..._7890',
          'pendingPlan': null,
          'cancelAtPeriodEnd': false,
        }),
      ],
      pagination: const AdminPaginationMeta(
        page: 1,
        pageSize: 20,
        total: 1,
        count: 1,
        hasNext: false,
        hasPrevious: false,
      ),
      filters: const {},
      sort: const AdminSortMeta(by: 'updatedAt', direction: 'desc'),
    );
  }

  @override
  Future<AdminBillingCompanyStatus> fetchBillingCompanyStatus(
    String companyId,
  ) async {
    statusFetchCount += 1;
    return AdminBillingCompanyStatus.fromMap({
      'company': {'id': companyId, 'name': 'Loja Moda Sul'},
      'license': {
        'plan': 'PRO',
        'status': 'ACTIVE',
        'providerSubscriptionId': 'preapproval-secret-full-id',
      },
      'billing': {
        'provider': 'mercadopago',
        'providerSubscriptionId': 'preapproval-secret-full-id',
        'maskedProviderSubscriptionId': 'pre_..._7890',
        'hasProviderSubscription': true,
      },
      'checkoutSessions': const [],
      'events': const [],
      'invoices': const [],
    });
  }

  @override
  Future<AdminPaginatedResult<AdminBillingEvent>> fetchBillingEvents({
    required AdminBillingListQuery query,
  }) async {
    return AdminPaginatedResult<AdminBillingEvent>(
      items: [
        AdminBillingEvent.fromMap({
          'id': 'event-1',
          'provider': 'mercadopago',
          'eventType': 'payment.created',
          'status': 'processed',
          'payload': {
            'Authorization': 'Bearer secret',
            'checkoutUrl':
                'https://www.mercadopago.com.br/checkout/v1/redirect?token=abc',
            'card': {'card_number': '4111111111111111'},
            'public': 'ok',
          },
        }),
      ],
      pagination: const AdminPaginationMeta(
        page: 1,
        pageSize: 10,
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
  Future<AdminPaginatedResult<AdminBillingCheckoutSession>>
  fetchBillingCheckoutSessions({required AdminBillingListQuery query}) async {
    return AdminPaginatedResult<AdminBillingCheckoutSession>(
      items: [
        AdminBillingCheckoutSession.fromMap({
          'id': 'session-1',
          'plan': 'PRO',
          'status': 'created',
          'provider': 'mercadopago',
          'checkoutUrl':
              'https://www.mercadopago.com.br/checkout/v1/redirect?token=abc',
        }),
      ],
      pagination: const AdminPaginationMeta(
        page: 1,
        pageSize: 10,
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
    return const AdminPaginatedResult<AdminLicenseSnapshot>(
      items: [],
      pagination: AdminPaginationMeta(
        page: 1,
        pageSize: 20,
        total: 0,
        count: 0,
        hasNext: false,
        hasPrevious: false,
      ),
      filters: {},
      sort: AdminSortMeta(by: 'updatedAt', direction: 'desc'),
    );
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
    if (reason.trim().isEmpty) {
      throw const AdminApiException(
        message: 'Informe o motivo da ação administrativa.',
        code: 'ADMIN_REASON_REQUIRED',
      );
    }
    forcePlanCalls += 1;
    lastForcePlan = plan;
    lastForcePlanStatus = status;
    lastForcePlanReason = reason;
    return AdminBillingActionResult.fromMap({
      'message': 'Force-plan aplicado.',
      'status': {
        'companyId': companyId,
        'plan': plan,
        'status': status ?? 'ACTIVE',
      },
    });
  }
}
