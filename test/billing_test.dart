import 'package:erp_pdv_app/app/core/config/app_data_mode.dart';
import 'package:erp_pdv_app/app/core/config/app_environment.dart';
import 'package:erp_pdv_app/app/core/database/app_database.dart';
import 'package:erp_pdv_app/app/core/entitlements/plan_entitlements.dart';
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
      'hasProviderSubscription': true,
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

  testWidgets('SubscriptionPage mostra upgrades para Free', (tester) async {
    final fakeBilling = _FakeBillingRemoteDataSource(
      status: _status(PlanEntitlements.free),
    );
    await _pumpSubscriptionPage(tester, fakeBilling: fakeBilling);

    expect(find.text('Assinatura e planos'), findsWidgets);
    expect(find.text('Plano atual'), findsWidgets);
    expect(find.text('Assinar plano Básico'), findsOneWidget);
    expect(find.text('Assinar plano Pro'), findsOneWidget);
    expect(
      find.textContaining(RegExp('owner', caseSensitive: false)),
      findsNothing,
    );
    expect(find.text('Somente owner'), findsNothing);
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

    expect(find.text('Assinar plano Básico'), findsNothing);
    expect(find.text('Assinar plano Pro'), findsNothing);
    expect(find.text('Plano atual'), findsWidgets);
  });

  testWidgets('OWNER por membership consegue ver ação de assinatura', (
    tester,
  ) async {
    final fakeBilling = _FakeBillingRemoteDataSource(
      status: _status(PlanEntitlements.free, canManageBilling: false),
    );
    await _pumpSubscriptionPage(
      tester,
      fakeBilling: fakeBilling,
      session: _session(
        PlanEntitlements.free,
        membership: const AppMembershipContext(
          role: 'OWNER',
          permissions: <String>{},
        ),
      ),
    );

    expect(find.text('Assinar plano Básico'), findsOneWidget);
    expect(
      find.text('Apenas o dono da empresa pode gerenciar a assinatura.'),
      findsNothing,
    );
  });

  testWidgets('não-OWNER ve aviso amigável e não gerencia assinatura', (
    tester,
  ) async {
    final fakeBilling = _FakeBillingRemoteDataSource(
      status: _status(PlanEntitlements.free, canManageBilling: false),
    );
    await _pumpSubscriptionPage(tester, fakeBilling: fakeBilling);

    expect(
      find.text('Apenas o dono da empresa pode gerenciar a assinatura.'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(find.text('Básico'), 240);
    await tester.pumpAndSettle();
    final disabledPlanActions = find.text(
      'Apenas o dono da empresa pode alterar',
    );
    expect(disabledPlanActions, findsWidgets);
    expect(find.text('Assinar plano Básico'), findsNothing);
    expect(find.text('Assinar plano Pro'), findsNothing);
    expect(fakeBilling.subscribedPlans, isEmpty);
    expect(
      find.textContaining(RegExp('owner', caseSensitive: false)),
      findsNothing,
    );
    expect(find.text('Somente owner'), findsNothing);
  });

  testWidgets('assinar chama subscribe e abre checkout externo', (
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

    await tester.drag(find.byType(ListView), const Offset(0, -360));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Assinar plano Básico'));
    await tester.pumpAndSettle();

    expect(fakeBilling.subscribedPlans, ['BASIC']);
    expect(launcher.openedUrls, ['https://checkout.tatuzin.test/basic']);
    expect(
      find.text('Após o pagamento, seu plano será atualizado automaticamente.'),
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

    await tester.drag(find.byType(ListView), const Offset(0, -360));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Assinar plano Básico'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copiar link'));
    await tester.pumpAndSettle();

    expect(launcher.copiedUrls, ['https://checkout.tatuzin.test/basic']);
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
        membership: session?.membership,
        employee: session?.employee,
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

BillingStatus _status(
  PlanEntitlements entitlements, {
  bool canManageBilling = true,
}) {
  return BillingStatus(
    companyId: 'company-1',
    plan: entitlements.plan,
    status: 'ACTIVE',
    currentPeriodStart: null,
    currentPeriodEnd: null,
    expiresAt: null,
    provider: entitlements.plan == PlanKey.free ? null : 'mercadopago',
    hasProviderSubscription: entitlements.plan != PlanKey.free,
    maskedProviderSubscriptionId: entitlements.plan == PlanKey.free
        ? null
        : 'prea...1234',
    canManageBilling: canManageBilling,
    nextPaymentDate: null,
    entitlements: entitlements,
  );
}

AppSession _session(
  PlanEntitlements entitlements, {
  AppMembershipContext? membership,
}) {
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
    membership: membership,
  );
}

const _user = AppUser(
  localId: null,
  remoteId: 'user-1',
  displayName: 'Dona da empresa',
  email: 'dona@tatuzin.test',
  roleLabel: 'Dono da empresa',
  kind: AppUserKind.remoteAuthenticated,
);

class _FakeBillingRemoteDataSource extends BillingRemoteDataSource {
  _FakeBillingRemoteDataSource({
    required this.status,
    BillingStatus? refreshedStatus,
  }) : refreshedStatus = refreshedStatus ?? status,
       super(apiClient: _NoopApiClient(), tokenStorage: _NoopTokenStorage());

  final BillingStatus status;
  final BillingStatus refreshedStatus;
  final subscribedPlans = <String>[];
  int refreshCount = 0;

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
      name: 'Básico',
      priceCents: 3500,
      currency: 'BRL',
      billingCycle: 'monthly',
      description: 'Gestão individual.',
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
  Future<BillingStatus> fetchStatus() async => status;

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
  Future<AppSession> changeInitialPassword({required String newPassword}) {
    throw UnimplementedError();
  }

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
