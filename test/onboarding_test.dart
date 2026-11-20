import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tatuzin/app/core/database/app_database.dart';
import 'package:tatuzin/app/core/network/real/remote_sign_up_request.dart';
import 'package:tatuzin/app/core/session/app_session.dart';
import 'package:tatuzin/app/core/session/app_user.dart';
import 'package:tatuzin/app/core/session/auth_token_storage.dart';
import 'package:tatuzin/app/core/session/company_context.dart';
import 'package:tatuzin/app/core/session/session_provider.dart';
import 'package:tatuzin/app/core/theme/app_theme.dart';
import 'package:tatuzin/modules/billing/domain/billing_models.dart';
import 'package:tatuzin/modules/billing/presentation/providers/billing_providers.dart';
import 'package:tatuzin/modules/billing/presentation/widgets/pro_trial_offer_gate.dart';
import 'package:tatuzin/modules/onboarding/data/onboarding_storage.dart';
import 'package:tatuzin/modules/onboarding/domain/onboarding_progress.dart';
import 'package:tatuzin/modules/onboarding/presentation/onboarding_checklist.dart';
import 'package:tatuzin/modules/onboarding/presentation/onboarding_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'offline pilot keeps onboarding active before its first server reconcile',
    () async {
      final companyId =
          'onboarding-offline-${DateTime.now().microsecondsSinceEpoch}';
      final container = ProviderContainer();
      container
          .read(appSessionProvider.notifier)
          .setAuthenticatedSession(
            scope: SessionScope.authenticatedRemote,
            user: const AppUser(
              localId: null,
              remoteId: 'owner',
              displayName: 'Dono',
              email: null,
              roleLabel: 'OWNER',
              kind: AppUserKind.remoteAuthenticated,
            ),
            company: CompanyContext(
              localId: null,
              remoteId: companyId,
              displayName: 'Loja',
              legalName: 'Loja',
              documentNumber: null,
              onboardingEnabled: true,
            ),
            clientInstanceId: 'offline-device',
            isOfflineFallback: true,
            membership: const AppMembershipContext(
              role: 'OWNER',
              permissions: {},
            ),
          );
      final isolationKey = SessionIsolation.keyFor(
        container.read(appSessionProvider),
      );
      addTearDown(() async {
        container.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await AppDatabase.deleteDatabaseForIsolationKeyForTesting(isolationKey);
      });
      // Offline entry requires the tenant database created by a prior online login.
      await AppDatabase.forIsolationKey(isolationKey).database;
      final progress = await container.read(companyOnboardingProvider.future);
      expect(progress!.enabled, true);
      expect(progress.completedSteps, 0);
      expect(progress.canOfferTrial(DateTime.now()), false);
      expect((await OnboardingStorage().read(companyId)).enabled, true);
    },
  );

  test(
    'automatic signup omits the slug and still supports explicit legacy slugs',
    () {
      const client = AuthClientContext(
        clientType: 'mobile_app',
        clientInstanceId: 'device',
      );
      const request = RemoteSignUpRequest(
        companyName: 'Loja',
        companySlug: '',
        userName: 'Dono',
        email: 'test@example.test',
        password: '12345678',
      );
      expect(request.toApiPayload(client).containsKey('companySlug'), false);
    },
  );

  test(
    'progress merges monotonically and rollout can be disabled explicitly',
    () {
      final completedAt = DateTime.utc(2026, 1, 1);
      final old = OnboardingProgress(enabled: true, completedAt: completedAt);
      final merged = old.merge(const OnboardingProgress());
      expect(merged.completedSteps, 3);
      expect(merged.completedAt, completedAt);
      expect(merged.productReady, true);
      expect(merged.cashReady, true);
      expect(
        old.merge(const OnboardingProgress(), enabled: false).enabled,
        false,
      );
      expect(
        OnboardingProgress.fromJson(merged.toJson()).completedAt,
        completedAt,
      );
    },
  );

  test('trial waits for a session after the first sale', () {
    final firstSale = DateTime.utc(2026, 1, 1, 12);
    final progress = OnboardingProgress(enabled: true, completedAt: firstSale);
    expect(
      progress.canOfferTrial(firstSale.subtract(const Duration(minutes: 5))),
      false,
    );
    expect(
      progress.canOfferTrial(firstSale.add(const Duration(minutes: 5))),
      true,
    );
    expect(
      const OnboardingProgress(enabled: true).canOfferTrial(firstSale),
      false,
    );
    expect(const OnboardingProgress().canOfferTrial(firstSale), true);
  });

  test(
    'progress survives storage recreation and stays isolated by company',
    () async {
      await OnboardingStorage().save(
        'a',
        const OnboardingProgress(enabled: true, productReady: true),
      );
      expect((await OnboardingStorage().read('a')).productReady, true);
      expect((await OnboardingStorage().read('b')).productReady, false);
      expect((await OnboardingStorage().read('b')).enabled, false);
    },
  );

  testWidgets('checklist offers real tasks and can be collapsed and resumed', (
    tester,
  ) async {
    var productClicks = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: OnboardingChecklist(
              progress: const OnboardingProgress(
                enabled: true,
                productReady: true,
              ),
              onProduct: () => productClicks++,
              onCash: () {},
              onSale: () {},
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('1. Cadastre seu primeiro produto'));
    expect(productClicks, 1);
    await tester.ensureVisible(find.text('Continuar depois'));
    await tester.tap(find.text('Continuar depois'));
    await tester.pumpAndSettle();
    expect(find.text('1 de 3 passos concluídos'), findsOneWidget);
    await tester.tap(find.text('Continuar configuração da loja'));
    await tester.pumpAndSettle();
    expect(find.text('3. Faça sua primeira venda'), findsOneWidget);
  });

  testWidgets('employees and completed companies do not see the checklist', (
    tester,
  ) async {
    for (final owner in [true, false]) {
      final container = _container(
        owner: owner,
        progress: owner
            ? OnboardingProgress(enabled: true, completedAt: DateTime.utc(2026))
            : const OnboardingProgress(enabled: true),
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CompanyOnboardingCard()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sua primeira venda começa aqui'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    }
  });

  testWidgets('trial dialog is suppressed until a later session', (
    tester,
  ) async {
    final container = _container(
      owner: true,
      progress: const OnboardingProgress(enabled: true),
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: ProTrialOfferGate(child: Scaffold(body: Text('Loja'))),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Teste gratis o PRO por 15 dias'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });
}

ProviderContainer _container({
  required bool owner,
  required OnboardingProgress progress,
}) {
  final container = ProviderContainer(
    overrides: [
      companyOnboardingProvider.overrideWith((ref) async => progress),
      billingStatusProvider.overrideWith(
        (ref) async =>
            BillingStatus.fromMap({'companyId': 'company', 'plan': 'FREE'}),
      ),
    ],
  );
  container
      .read(appSessionProvider.notifier)
      .setAuthenticatedSession(
        scope: SessionScope.authenticatedRemote,
        user: const AppUser(
          localId: null,
          remoteId: 'user',
          displayName: 'Dono',
          email: null,
          roleLabel: 'OWNER',
          kind: AppUserKind.remoteAuthenticated,
        ),
        company: const CompanyContext(
          localId: null,
          remoteId: 'company',
          displayName: 'Loja',
          legalName: 'Loja',
          documentNumber: null,
        ),
        clientInstanceId: 'device',
        membership: AppMembershipContext(
          role: owner ? 'OWNER' : 'OPERATOR',
          permissions: const {},
        ),
      );
  return container;
}
