import 'package:erp_pdv_app/app/core/config/app_data_mode.dart';
import 'package:erp_pdv_app/app/core/config/app_environment.dart';
import 'package:erp_pdv_app/app/core/database/app_database.dart';
import 'package:erp_pdv_app/app/core/entitlements/plan_entitlements.dart';
import 'package:erp_pdv_app/app/core/errors/app_exceptions.dart';
import 'package:erp_pdv_app/app/core/network/contracts/api_client_contract.dart';
import 'package:erp_pdv_app/app/core/network/contracts/auth_gateway.dart';
import 'package:erp_pdv_app/app/core/session/app_session.dart';
import 'package:erp_pdv_app/app/core/session/app_user.dart';
import 'package:erp_pdv_app/app/core/session/auth_provider.dart';
import 'package:erp_pdv_app/app/core/session/auth_token_storage.dart';
import 'package:erp_pdv_app/app/core/session/company_context.dart';
import 'package:erp_pdv_app/app/core/session/session_provider.dart';
import 'package:erp_pdv_app/app/core/sync/sync_queue_feature_summary.dart';
import 'package:erp_pdv_app/app/core/theme/app_theme.dart';
import 'package:erp_pdv_app/modules/billing/data/billing_remote_data_source.dart';
import 'package:erp_pdv_app/modules/billing/domain/billing_models.dart';
import 'package:erp_pdv_app/modules/billing/presentation/pages/subscription_page.dart';
import 'package:erp_pdv_app/modules/billing/presentation/providers/billing_providers.dart';
import 'package:erp_pdv_app/modules/billing/presentation/providers/checkout_launcher.dart';
import 'package:erp_pdv_app/modules/system/presentation/providers/system_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('BillingStatus parser nao expõe provider id completo', () {
    final status = BillingStatus.fromMap(<String, dynamic>{
      'companyId': 'company-1',
      'plan': 'PRO',
      'status': 'ACTIVE',
      'provider': 'mercadopago',
      'hasProviderSubscription': 'true',
      'maskedProviderSubscriptionId': 'prea...7890',
      'providerSubscriptionId': 'preapproval-1234567890',
      'canManageBilling': true,
      'features': <String, bool>{'employees': true},
      'limits': <String, dynamic>{
        'maxDevices': 100,
        'maxEmployees': 100,
        'reportPeriods': <String>['daily', 'monthly'],
      },
    });

    expect(status.plan, PlanKey.pro);
    expect(status.hasProviderSubscription, isTrue);
    expect(status.maskedProviderSubscriptionId, 'prea...7890');
    expect(status.entitlements.hasFeature(FeatureKey.employees), isTrue);
  });

  test('BillingInvoice parser aceita campos ausentes sem payload bruto', () {
    final invoice = BillingInvoice.fromMap(<String, dynamic>{
      'id': 'invoice-1',
      'status': 'paid',
      'amountCents': 3500,
      'payload': <String, dynamic>{'card_number': '4111111111111111'},
      'providerSubscriptionId': 'preapproval-full-id',
    });

    expect(invoice.id, 'invoice-1');
    expect(invoice.status, 'paid');
    expect(invoice.amountCents, 3500);
    expect(invoice.provider, isNull);
  });

  test('BillingStatus parser mantem pendingPlan separado do plano real', () {
    final status = BillingStatus.fromMap(<String, dynamic>{
      'companyId': 'company-1',
      'plan': 'BASIC',
      'status': 'ACTIVE',
      'pendingPlan': 'PRO',
      'cancelAtPeriodEnd': true,
      'features': <String, bool>{'employees': false},
      'limits': <String, dynamic>{
        'maxDevices': 1,
        'maxEmployees': 0,
        'reportPeriods': <String>['daily', 'monthly'],
      },
    });

    expect(status.plan, PlanKey.basic);
    expect(status.pendingPlan, PlanKey.pro);
    expect(status.entitlements.hasFeature(FeatureKey.employees), isFalse);
  });

  test('BillingPaymentMethod parser nao exige cartao completo', () {
    final method = BillingPaymentMethod.fromMap(<String, dynamic>{
      'provider': 'mercadopago',
      'hasPaymentMethod': true,
      'unavailable': true,
      'paymentMethodType': 'credit_card',
      'lastFour': '4242',
      'providerSubscriptionId': 'preapproval-full-id',
      'maskedProviderSubscriptionId': 'prea...4242',
    });

    expect(method.hasPaymentMethod, isTrue);
    expect(method.unavailable, isTrue);
    expect(method.lastFour, '4242');
    expect(method.maskedProviderSubscriptionId, 'prea...4242');
  });

  test(
    'BillingRemoteDataSource traduz 403 de gestao para mensagem amigavel',
    () {
      final dataSource = BillingRemoteDataSource(
        apiClient: _ForbiddenBillingApiClient(),
        tokenStorage: _NoopTokenStorage(),
      );

      expect(
        dataSource.fetchInvoices(),
        throwsA(
          isA<ValidationException>().having(
            (error) => error.message,
            'message',
            'Somente o dono/administrador pode gerenciar assinatura.',
          ),
        ),
      );
    },
  );

  test('BillingRemoteDataSource chama endpoints da Fase B2', () async {
    final apiClient = _RecordingApiClient();
    final dataSource = BillingRemoteDataSource(
      apiClient: apiClient,
      tokenStorage: _NoopTokenStorage(),
    );

    await dataSource.fetchInvoices(status: 'paid', page: 2, pageSize: 5);
    await dataSource.fetchInvoice('invoice 1');
    await dataSource.fetchPaymentMethod();
    await dataSource.cancelSubscription();
    await dataSource.resumeSubscription();
    await dataSource.changePlan(PlanKey.pro);

    expect(apiClient.calls.map((call) => call.method).toList(), [
      'GET',
      'GET',
      'GET',
      'POST',
      'POST',
      'POST',
    ]);
    expect(apiClient.calls.map((call) => call.path).toList(), [
      '/billing/invoices',
      '/billing/invoices/invoice%201',
      '/billing/payment-method',
      '/billing/cancel',
      '/billing/resume',
      '/billing/change-plan',
    ]);
    expect(apiClient.calls.first.queryParameters['status'], 'paid');
    expect(apiClient.calls.last.body, <String, dynamic>{'plan': 'PRO'});
  });

  testWidgets('SubscriptionPage mostra upgrades para Free', (tester) async {
    final fakeBilling = _FakeBillingRemoteDataSource(
      status: _status(PlanEntitlements.free),
    );
    await _pumpSubscriptionPage(tester, fakeBilling: fakeBilling);

    expect(find.text('Assinatura'), findsWidgets);
    expect(find.text('Plano atual'), findsWidgets);
    await _scrollUntilTextVisible(tester, 'Assinar Basico');
    expect(find.text('Assinar Basico'), findsOneWidget);
    expect(find.text('Assinar Pro'), findsOneWidget);
  });

  testWidgets('SubscriptionPage mostra Pro como plano atual', (tester) async {
    final fakeBilling = _FakeBillingRemoteDataSource(
      status: _status(PlanEntitlements.pro),
    );
    await _pumpSubscriptionPage(
      tester,
      fakeBilling: fakeBilling,
      session: _session(PlanEntitlements.pro),
    );

    expect(find.text('Assinar Basico'), findsNothing);
    expect(find.text('Assinar Pro'), findsNothing);
    expect(find.text('Plano atual'), findsWidgets);
  });

  testWidgets('trocar plano chama change-plan e abre checkout externo', (
    tester,
  ) async {
    final fakeBilling = _FakeBillingRemoteDataSource(
      status: _status(PlanEntitlements.free),
    );
    final launcher = _FakeCheckoutLauncher();
    await _pumpSubscriptionPage(
      tester,
      fakeBilling: fakeBilling,
      launcher: launcher,
    );

    await _scrollUntilTextVisible(tester, 'Assinar Basico');
    await tester.tap(find.text('Assinar Basico'));
    await tester.pumpAndSettle();

    expect(fakeBilling.changedPlans, ['BASIC']);
    expect(launcher.openedUrls, ['https://checkout.tatuzin.test/basic']);
    expect(fakeBilling.refreshCount, 1);
    expect(
      find.text('Apos o pagamento, seu plano sera atualizado automaticamente.'),
      findsOneWidget,
    );
  });

  testWidgets('falha ao abrir checkout mostra opcao de copiar link', (
    tester,
  ) async {
    final fakeBilling = _FakeBillingRemoteDataSource(
      status: _status(PlanEntitlements.free),
    );
    final launcher = _FakeCheckoutLauncher(shouldOpen: false);
    await _pumpSubscriptionPage(
      tester,
      fakeBilling: fakeBilling,
      launcher: launcher,
    );

    await _scrollUntilTextVisible(tester, 'Assinar Basico');
    await tester.tap(find.text('Assinar Basico'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copiar link'));
    await tester.pumpAndSettle();

    expect(launcher.copiedUrls, ['https://checkout.tatuzin.test/basic']);
  });

  testWidgets('SubscriptionPage renderiza pendingPlan e cobrancas seguras', (
    tester,
  ) async {
    final fakeBilling = _FakeBillingRemoteDataSource(
      status: _status(
        PlanEntitlements.basic,
        pendingPlan: PlanKey.pro,
        cancelAtPeriodEnd: true,
        currentPeriodEnd: DateTime(2026, 5, 31),
      ),
      invoicesPage: BillingInvoicesPage(
        items: [
          BillingInvoice(
            id: 'invoice-1',
            provider: 'mercadopago',
            status: 'paid',
            amountCents: 3500,
            currency: 'BRL',
            periodStart: DateTime(2026, 5),
            periodEnd: DateTime(2026, 5, 31),
            dueAt: null,
            paidAt: DateTime(2026, 5, 7),
            failedAt: null,
            invoiceUrl: 'https://safe-invoice.tatuzin.test/1',
            createdAt: DateTime(2026, 5, 7),
            updatedAt: DateTime(2026, 5, 7),
          ),
        ],
        page: 1,
        pageSize: 20,
        total: 1,
        count: 1,
        hasNext: false,
        hasPrevious: false,
      ),
    );
    await _pumpSubscriptionPage(
      tester,
      fakeBilling: fakeBilling,
      session: _session(PlanEntitlements.basic),
    );

    expect(find.textContaining('Upgrade para Pro solicitado'), findsOneWidget);
    expect(find.textContaining('Cancelamento agendado'), findsOneWidget);
    await _scrollUntilTextVisible(tester, 'Historico de cobrancas');
    expect(find.text('Historico de cobrancas'), findsOneWidget);
    expect(find.text('R\$ 35,00'), findsOneWidget);
    expect(find.textContaining('preapproval-full-id'), findsNothing);
    expect(find.textContaining('card_number'), findsNothing);
  });

  testWidgets('falha ao abrir cobranca nao copia nem exibe URL completa', (
    tester,
  ) async {
    final fakeBilling = _FakeBillingRemoteDataSource(
      status: _status(PlanEntitlements.basic),
      invoicesPage: BillingInvoicesPage(
        items: [
          BillingInvoice(
            id: 'invoice-1',
            provider: 'mercadopago',
            status: 'paid',
            amountCents: 3500,
            currency: 'BRL',
            periodStart: null,
            periodEnd: null,
            dueAt: null,
            paidAt: null,
            failedAt: null,
            invoiceUrl: 'https://safe-invoice.tatuzin.test/tokenized/1',
            createdAt: DateTime(2026, 5, 7),
            updatedAt: DateTime(2026, 5, 7),
          ),
        ],
        page: 1,
        pageSize: 20,
        total: 1,
        count: 1,
        hasNext: false,
        hasPrevious: false,
      ),
    );
    final launcher = _FakeCheckoutLauncher(shouldOpen: false);
    await _pumpSubscriptionPage(
      tester,
      fakeBilling: fakeBilling,
      launcher: launcher,
      session: _session(PlanEntitlements.basic),
    );

    await _scrollUntilTextVisible(tester, 'Ver cobranca');
    await tester.tap(find.text('Ver cobranca'));
    await tester.pumpAndSettle();

    expect(launcher.openedUrls, [
      'https://safe-invoice.tatuzin.test/tokenized/1',
    ]);
    expect(launcher.copiedUrls, isEmpty);
    expect(
      find.textContaining('safe-invoice.tatuzin.test/tokenized'),
      findsNothing,
    );
    expect(
      find.text('Nao foi possivel abrir a cobranca agora.'),
      findsOneWidget,
    );
  });

  testWidgets('cancelar chama action e depois refresh/bootstrap', (
    tester,
  ) async {
    final fakeBilling = _FakeBillingRemoteDataSource(
      status: _status(
        PlanEntitlements.basic,
        currentPeriodEnd: DateTime(2026, 5, 31),
      ),
    );
    final container = await _pumpSubscriptionPage(
      tester,
      fakeBilling: fakeBilling,
      session: _session(PlanEntitlements.basic),
      authGateway: _FakeAuthGateway(
        refreshSession: _session(PlanEntitlements.basic),
      ),
    );

    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar assinatura').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar assinatura').last);
    await tester.pumpAndSettle();

    expect(fakeBilling.cancelCount, 1);
    expect(fakeBilling.refreshCount, 1);
    expect(container.read(appSessionProvider).plan, PlanKey.basic);
  });

  testWidgets('change-plan BASIC para PRO nao libera PRO localmente', (
    tester,
  ) async {
    final fakeBilling = _FakeBillingRemoteDataSource(
      status: _status(PlanEntitlements.basic),
      refreshedStatus: _status(
        PlanEntitlements.basic,
        pendingPlan: PlanKey.pro,
      ),
    );
    final container = await _pumpSubscriptionPage(
      tester,
      fakeBilling: fakeBilling,
      session: _session(PlanEntitlements.basic),
      authGateway: _FakeAuthGateway(
        refreshSession: _session(PlanEntitlements.basic),
      ),
    );

    await _scrollUntilTextVisible(tester, 'Assinar Pro');
    await tester.tap(find.text('Assinar Pro'));
    await tester.pumpAndSettle();

    expect(fakeBilling.changedPlans, ['PRO']);
    expect(container.read(appSessionProvider).plan, PlanKey.basic);
    expect(
      container.read(appSessionProvider).hasFeature(FeatureKey.employees),
      isFalse,
    );
  });

  testWidgets('retomar chama action e refresh/status/bootstrap', (
    tester,
  ) async {
    final fakeBilling = _FakeBillingRemoteDataSource(
      status: _status(
        PlanEntitlements.basic,
        cancelAtPeriodEnd: true,
        currentPeriodEnd: DateTime(2026, 5, 31),
      ),
    );
    await _pumpSubscriptionPage(
      tester,
      fakeBilling: fakeBilling,
      session: _session(PlanEntitlements.basic),
    );

    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retomar assinatura'));
    await tester.pumpAndSettle();

    expect(fakeBilling.resumeCount, 1);
    expect(fakeBilling.refreshCount, 1);
  });

  testWidgets(
    'Atualizar status chama refresh antes de atualizar entitlements',
    (tester) async {
      final fakeBilling = _FakeBillingRemoteDataSource(
        status: _status(PlanEntitlements.free),
        refreshedStatus: _status(PlanEntitlements.pro),
      );
      final container = await _pumpSubscriptionPage(
        tester,
        fakeBilling: fakeBilling,
        authGateway: _FakeAuthGateway(
          refreshSession: _session(PlanEntitlements.pro),
        ),
      );

      await tester.tap(find.text('Atualizar status'));
      await tester.pumpAndSettle();

      expect(fakeBilling.refreshCount, 1);
      expect(container.read(appSessionProvider).plan, PlanKey.pro);
    },
  );
}

Future<ProviderContainer> _pumpSubscriptionPage(
  WidgetTester tester, {
  required _FakeBillingRemoteDataSource fakeBilling,
  _FakeCheckoutLauncher? launcher,
  _FakeAuthGateway? authGateway,
  AppSession? session,
}) async {
  final container = ProviderContainer(
    overrides: [
      initialAppEnvironmentProvider.overrideWith(
        (ref) => AppEnvironment.remoteDefault().copyWith(
          dataMode: AppDataMode.futureHybridReady,
        ),
      ),
      billingRemoteDataSourceProvider.overrideWithValue(fakeBilling),
      checkoutLauncherProvider.overrideWithValue(
        launcher ?? _FakeCheckoutLauncher(),
      ),
      remoteAuthGatewayProvider.overrideWith(
        (ref) => authGateway ?? _FakeAuthGateway(),
      ),
      appStartupProvider.overrideWith(
        (ref) async => const AppStartupState.success(),
      ),
      backendConnectionStatusProvider.overrideWith(
        (ref) async => BackendConnectionStatus(
          isConfigured: true,
          isReachable: true,
          companyLookupSucceeded: true,
          endpointLabel: 'https://api.tatuzin.test/api',
          message: 'online',
          checkedAt: DateTime(2026, 5, 7),
          remoteCompanyName: 'Cafe Oliveira',
        ),
      ),
      syncQueueFeatureSummariesProvider.overrideWith(
        (ref) async => const <SyncQueueFeatureSummary>[],
      ),
    ],
  );
  addTearDown(container.dispose);
  container
      .read(appSessionProvider.notifier)
      .setAuthenticatedSession(
        scope: SessionScope.authenticatedRemote,
        user: _user,
        company: (session ?? _session(PlanEntitlements.free)).company,
        clientInstanceId: 'device-1',
      );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const SubscriptionPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _scrollUntilTextVisible(WidgetTester tester, String text) async {
  await tester.scrollUntilVisible(
    find.text(text),
    220,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 20,
  );
  await tester.pumpAndSettle();
}

BillingStatus _status(
  PlanEntitlements entitlements, {
  PlanKey? pendingPlan,
  bool cancelAtPeriodEnd = false,
  DateTime? currentPeriodEnd,
}) {
  return BillingStatus(
    companyId: 'company-1',
    plan: entitlements.plan,
    status: 'ACTIVE',
    currentPeriodStart: null,
    currentPeriodEnd: currentPeriodEnd,
    expiresAt: null,
    provider: entitlements.plan == PlanKey.free ? null : 'mercadopago',
    hasProviderSubscription: entitlements.plan != PlanKey.free,
    maskedProviderSubscriptionId: entitlements.plan == PlanKey.free
        ? null
        : 'prea...1234',
    canManageBilling: true,
    nextPaymentDate: null,
    entitlements: entitlements,
    pendingPlan: pendingPlan,
    pendingPlanRequestedAt: pendingPlan == null ? null : DateTime(2026, 5, 7),
    cancelAtPeriodEnd: cancelAtPeriodEnd,
    cancelRequestedAt: cancelAtPeriodEnd ? DateTime(2026, 5, 7) : null,
  );
}

AppSession _session(PlanEntitlements entitlements) {
  return AppSession(
    scope: SessionScope.authenticatedRemote,
    user: _user,
    company: CompanyContext(
      localId: null,
      remoteId: 'company-1',
      displayName: 'Cafe Oliveira',
      legalName: 'Cafe Oliveira LTDA',
      documentNumber: null,
      licensePlan: entitlements.plan.key,
      licenseStatus: 'active',
      syncEnabled: true,
      entitlements: entitlements,
    ),
    startedAt: DateTime(2026, 5, 7),
    isOfflineFallback: true,
    clientInstanceId: 'device-1',
  );
}

const _user = AppUser(
  localId: null,
  remoteId: 'user-1',
  displayName: 'Owner',
  email: 'owner@tatuzin.test',
  roleLabel: 'Owner',
  kind: AppUserKind.remoteAuthenticated,
);

class _FakeBillingRemoteDataSource extends BillingRemoteDataSource {
  _FakeBillingRemoteDataSource({
    required this.status,
    BillingStatus? refreshedStatus,
    BillingInvoicesPage? invoicesPage,
    BillingPaymentMethod? paymentMethod,
  }) : refreshedStatus = refreshedStatus ?? status,
       invoicesPage =
           invoicesPage ??
           const BillingInvoicesPage(
             items: <BillingInvoice>[],
             page: 1,
             pageSize: 20,
             total: 0,
             count: 0,
             hasNext: false,
             hasPrevious: false,
           ),
       paymentMethod =
           paymentMethod ??
           const BillingPaymentMethod(
             provider: null,
             hasPaymentMethod: false,
             unavailable: false,
             status: null,
             paymentMethodId: null,
             paymentMethodType: null,
             lastFour: null,
             nextPaymentDate: null,
             maskedProviderSubscriptionId: null,
             message: null,
           ),
       super(apiClient: _NoopApiClient(), tokenStorage: _NoopTokenStorage());

  final BillingStatus status;
  final BillingStatus refreshedStatus;
  final BillingInvoicesPage invoicesPage;
  final BillingPaymentMethod paymentMethod;
  final subscribedPlans = <String>[];
  final changedPlans = <String>[];
  int refreshCount = 0;
  int cancelCount = 0;
  int resumeCount = 0;

  @override
  Future<List<BillingPlan>> fetchPlans() async => const [
    BillingPlan(
      key: PlanKey.free,
      name: 'Free',
      priceCents: 0,
      currency: 'BRL',
      billingCycle: 'free',
      description: 'Comece vendendo.',
      featuresSummary: ['PDV e caixa'],
    ),
    BillingPlan(
      key: PlanKey.basic,
      name: 'Basico',
      priceCents: 3500,
      currency: 'BRL',
      billingCycle: 'monthly',
      description: 'Gestao individual.',
      featuresSummary: ['Custos e insumos'],
    ),
    BillingPlan(
      key: PlanKey.pro,
      name: 'Pro',
      priceCents: 8500,
      currency: 'BRL',
      billingCycle: 'monthly',
      description: 'Equipe e dispositivos.',
      featuresSummary: ['Funcionarios'],
    ),
  ];

  @override
  Future<BillingStatus> fetchStatus() async =>
      refreshCount > 0 ? refreshedStatus : status;

  @override
  Future<BillingInvoicesPage> fetchInvoices({
    String? status,
    DateTime? from,
    DateTime? to,
    int page = 1,
    int pageSize = 20,
  }) async => invoicesPage;

  @override
  Future<BillingPaymentMethod> fetchPaymentMethod() async => paymentMethod;

  @override
  Future<BillingSubscribeResult> subscribe({
    required String plan,
    String billingCycle = 'monthly',
  }) async {
    subscribedPlans.add(plan);
    return BillingSubscribeResult(
      checkoutUrl: plan == 'BASIC'
          ? 'https://checkout.tatuzin.test/basic'
          : 'https://checkout.tatuzin.test/pro',
      provider: 'mercadopago',
      plan: PlanKey.normalize(plan),
      checkoutSessionId: 'checkout-1',
      expiresAt: DateTime(2026, 5, 7, 12, 30),
    );
  }

  @override
  Future<BillingStatus> refresh() async {
    refreshCount += 1;
    return refreshedStatus;
  }

  @override
  Future<BillingActionResult> cancelSubscription({
    String effective = 'period_end',
  }) async {
    cancelCount += 1;
    return BillingActionResult(
      status: refreshedStatus,
      providerCancelled: true,
      effective: effective,
      requiresNewCheckout: false,
      checkoutUrl: null,
      checkoutSessionId: null,
      message: 'Cancelamento solicitado.',
      pendingPlan: refreshedStatus.pendingPlan,
    );
  }

  @override
  Future<BillingActionResult> resumeSubscription() async {
    resumeCount += 1;
    return BillingActionResult(
      status: refreshedStatus,
      providerCancelled: false,
      effective: null,
      requiresNewCheckout: false,
      checkoutUrl: null,
      checkoutSessionId: null,
      message: 'Assinatura retomada.',
      pendingPlan: refreshedStatus.pendingPlan,
    );
  }

  @override
  Future<BillingActionResult> changePlan(PlanKey plan) async {
    changedPlans.add(plan.key);
    return BillingActionResult(
      status: refreshedStatus,
      providerCancelled: false,
      effective: null,
      requiresNewCheckout: false,
      checkoutUrl: plan == PlanKey.basic
          ? 'https://checkout.tatuzin.test/basic'
          : plan == PlanKey.pro
          ? 'https://checkout.tatuzin.test/pro'
          : null,
      checkoutSessionId: 'checkout-1',
      message: 'Apos o pagamento, seu plano sera atualizado automaticamente.',
      pendingPlan: refreshedStatus.pendingPlan,
    );
  }
}

class _FakeCheckoutLauncher implements CheckoutLauncher {
  _FakeCheckoutLauncher({this.shouldOpen = true});

  final bool shouldOpen;
  final openedUrls = <String>[];
  final copiedUrls = <String>[];

  @override
  Future<bool> openExternal(String url) async {
    openedUrls.add(url);
    return shouldOpen;
  }

  @override
  Future<void> copyLink(String url) async {
    copiedUrls.add(url);
  }
}

class _FakeAuthGateway implements AuthGateway {
  _FakeAuthGateway({AppSession? refreshSession})
    : refreshSessionResult = refreshSession ?? _session(PlanEntitlements.free);

  final AppSession refreshSessionResult;

  @override
  Future<AppSession> refreshSession() async => refreshSessionResult;

  @override
  Future<AppSession?> restoreSession() async => null;

  @override
  Future<AppSession> signIn({
    required String identifier,
    required String password,
  }) async => refreshSessionResult;

  @override
  Future<AppSession> signUp({
    required String companyName,
    required String companySlug,
    required String userName,
    required String email,
    required String password,
  }) async => refreshSessionResult;

  @override
  Future<String> requestPasswordReset({required String email}) async => 'ok';

  @override
  Future<String> resetPassword({
    required String token,
    required String newPassword,
  }) async => 'ok';

  @override
  Future<void> signOut() async {}
}

class _NoopTokenStorage implements AuthTokenStorage {
  @override
  Future<void> clear() async {}

  @override
  Future<AuthClientContext> ensureClientContext({
    required String clientType,
    String? deviceLabel,
    String? platform,
    String? appVersion,
  }) async =>
      AuthClientContext(clientType: clientType, clientInstanceId: 'device-1');

  @override
  Future<String?> readAccessToken() async => 'token';

  @override
  Future<AuthClientContext?> readClientContext() async =>
      const AuthClientContext(
        clientType: 'mobile_app',
        clientInstanceId: 'device-1',
      );

  @override
  Future<String?> readRefreshToken() async => 'refresh';

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {}
}

class _RecordedApiCall {
  const _RecordedApiCall({
    required this.method,
    required this.path,
    required this.queryParameters,
    required this.body,
  });

  final String method;
  final String path;
  final Map<String, Object?> queryParameters;
  final Map<String, dynamic>? body;
}

class _RecordingApiClient extends _NoopApiClient {
  final calls = <_RecordedApiCall>[];

  @override
  Future<ApiResponse<Map<String, dynamic>>> getJson(
    String path, {
    ApiRequestOptions options = const ApiRequestOptions(),
  }) async {
    calls.add(
      _RecordedApiCall(
        method: 'GET',
        path: path,
        queryParameters: options.queryParameters,
        body: null,
      ),
    );
    if (path == '/billing/invoices') {
      return const ApiResponse<Map<String, dynamic>>(
        statusCode: 200,
        data: <String, dynamic>{
          'items': <Map<String, dynamic>>[],
          'page': 1,
          'pageSize': 20,
          'total': 0,
          'count': 0,
        },
        headers: <String, String>{},
      );
    }
    if (path.startsWith('/billing/invoices/')) {
      return const ApiResponse<Map<String, dynamic>>(
        statusCode: 200,
        data: <String, dynamic>{'id': 'invoice-1', 'status': 'paid'},
        headers: <String, String>{},
      );
    }
    if (path == '/billing/payment-method') {
      return const ApiResponse<Map<String, dynamic>>(
        statusCode: 200,
        data: <String, dynamic>{'hasPaymentMethod': false},
        headers: <String, String>{},
      );
    }
    return super.getJson(path, options: options);
  }

  @override
  Future<ApiResponse<Map<String, dynamic>>> postJson(
    String path, {
    Map<String, dynamic>? body,
    ApiRequestOptions options = const ApiRequestOptions(),
  }) async {
    calls.add(
      _RecordedApiCall(
        method: 'POST',
        path: path,
        queryParameters: options.queryParameters,
        body: body,
      ),
    );
    return const ApiResponse<Map<String, dynamic>>(
      statusCode: 200,
      data: <String, dynamic>{
        'status': <String, dynamic>{
          'companyId': 'company-1',
          'plan': 'FREE',
          'status': 'ACTIVE',
          'features': <String, bool>{},
          'limits': <String, dynamic>{
            'maxDevices': 1,
            'maxEmployees': 0,
            'reportPeriods': <String>['daily'],
          },
        },
        'message': 'ok',
      },
      headers: <String, String>{},
    );
  }
}

class _ForbiddenBillingApiClient extends _NoopApiClient {
  @override
  Future<ApiResponse<Map<String, dynamic>>> getJson(
    String path, {
    ApiRequestOptions options = const ApiRequestOptions(),
  }) async {
    throw const NetworkRequestException('Forbidden', cause: 403);
  }
}

class _NoopApiClient implements ApiClientContract {
  @override
  Future<ApiResponse<void>> delete(
    String path, {
    ApiRequestOptions options = const ApiRequestOptions(),
  }) async => const ApiResponse<void>(
    statusCode: 204,
    data: null,
    headers: <String, String>{},
  );

  @override
  Future<ApiResponse<Map<String, dynamic>>> getJson(
    String path, {
    ApiRequestOptions options = const ApiRequestOptions(),
  }) async => const ApiResponse<Map<String, dynamic>>(
    statusCode: 200,
    data: <String, dynamic>{},
    headers: <String, String>{},
  );

  @override
  Future<ApiResponse<Map<String, dynamic>>> postJson(
    String path, {
    Map<String, dynamic>? body,
    ApiRequestOptions options = const ApiRequestOptions(),
  }) async => const ApiResponse<Map<String, dynamic>>(
    statusCode: 200,
    data: <String, dynamic>{},
    headers: <String, String>{},
  );

  @override
  Future<ApiResponse<Map<String, dynamic>>> putJson(
    String path, {
    Map<String, dynamic>? body,
    ApiRequestOptions options = const ApiRequestOptions(),
  }) async => const ApiResponse<Map<String, dynamic>>(
    statusCode: 200,
    data: <String, dynamic>{},
    headers: <String, String>{},
  );

  @override
  Future<ApiResponse<Map<String, dynamic>>> patchJson(
    String path, {
    Map<String, dynamic>? body,
    ApiRequestOptions options = const ApiRequestOptions(),
  }) async => const ApiResponse<Map<String, dynamic>>(
    statusCode: 200,
    data: <String, dynamic>{},
    headers: <String, String>{},
  );
}
