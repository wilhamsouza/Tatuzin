import 'package:erp_pdv_app/app/core/entitlements/feature_gate.dart';
import 'package:erp_pdv_app/app/core/entitlements/plan_entitlements.dart';
import 'package:erp_pdv_app/app/core/session/app_session.dart';
import 'package:erp_pdv_app/app/core/session/app_user.dart';
import 'package:erp_pdv_app/app/core/session/cached_session_storage.dart';
import 'package:erp_pdv_app/app/core/session/company_context.dart';
import 'package:erp_pdv_app/app/core/session/session_provider.dart';
import 'package:erp_pdv_app/app/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('PlanEntitlements', () {
    test('parseia planos e features oficiais', () {
      final basic = PlanEntitlements.fromJson(<String, dynamic>{
        'plan': 'basic',
        'features': <String, bool>{
          'sales': true,
          'costs': true,
          'supplies': true,
          'fiadoManagement': true,
          'employees': false,
        },
        'limits': <String, dynamic>{
          'maxDevices': 1,
          'maxEmployees': 0,
          'reportPeriods': <String>['daily', 'weekly', 'monthly'],
        },
      });

      expect(basic.plan, PlanKey.basic);
      expect(basic.hasFeature(FeatureKey.costs), isTrue);
      expect(basic.hasFeature(FeatureKey.supplies), isTrue);
      expect(basic.hasFeature(FeatureKey.fiadoManagement), isTrue);
      expect(basic.hasFeature(FeatureKey.employees), isFalse);
      expect(basic.allowsReportPeriod(ReportPeriodKey.monthly), isTrue);
      expect(basic.allowsReportPeriod(ReportPeriodKey.yearly), isFalse);
    });

    test('payload antigo sem entitlements usa fallback FREE', () {
      final entitlements = PlanEntitlements.fromBootstrapJson(<String, dynamic>{
        'license': <String, dynamic>{'plan': 'pro'},
      });

      expect(entitlements.plan, PlanKey.free);
      expect(entitlements.hasFeature(FeatureKey.sales), isTrue);
      expect(entitlements.hasFeature(FeatureKey.costs), isFalse);
      expect(entitlements.limits.maxDevices, 1);
      expect(entitlements.allowsReportPeriod(ReportPeriodKey.daily), isTrue);
      expect(entitlements.allowsReportPeriod(ReportPeriodKey.monthly), isFalse);
    });

    test('trial e desconhecido normalizam para FREE', () {
      expect(PlanKey.normalize('trial'), PlanKey.free);
      expect(PlanKey.normalize('enterprise'), PlanKey.free);
    });
  });

  test('CachedSessionStorage persiste entitlements para uso offline', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final storage = SharedPreferencesCachedSessionStorage();
    final session = _remoteSession(PlanEntitlements.basic);

    await storage.saveSession(session);
    final restored = await storage.readSession();

    expect(restored, isNotNull);
    expect(restored!.isOfflineFallback, isTrue);
    expect(restored.company.plan, PlanKey.basic);
    expect(restored.company.hasFeature(FeatureKey.costs), isTrue);
    expect(restored.company.hasFeature(FeatureKey.employees), isFalse);
    expect(restored.membership?.role, 'OWNER');
    expect(restored.isCompanyOwner, isTrue);
    expect(restored.hasEffectivePermission('subscription.manage'), isTrue);
    expect(restored.company.limits.reportPeriods, {
      ReportPeriodKey.daily,
      ReportPeriodKey.weekly,
      ReportPeriodKey.monthly,
    });
  });

  testWidgets('FeatureGate bloqueia sem feature e libera com feature', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(appSessionProvider.notifier)
        .setAuthenticatedSession(
          scope: SessionScope.authenticatedRemote,
          user: _user,
          company: _company(PlanEntitlements.free),
          clientInstanceId: 'device-1',
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const FeatureGate(
            feature: FeatureKey.costs,
            child: Text('Custos liberados'),
          ),
        ),
      ),
    );

    expect(find.text('Recurso bloqueado'), findsWidgets);
    expect(find.text('Ver planos'), findsOneWidget);
    expect(
      find.text('Peça ao dono da empresa para alterar o plano.'),
      findsOneWidget,
    );
    expect(
      find.text('Este recurso está disponível no plano Básico.'),
      findsOneWidget,
    );
    expect(find.text('Custos liberados'), findsNothing);

    container
        .read(appSessionProvider.notifier)
        .setAuthenticatedSession(
          scope: SessionScope.authenticatedRemote,
          user: _user,
          company: _company(PlanEntitlements.basic),
          clientInstanceId: 'device-1',
        );
    await tester.pump();

    expect(find.text('Custos liberados'), findsOneWidget);
  });
}

AppSession _remoteSession(PlanEntitlements entitlements) {
  return AppSession(
    scope: SessionScope.authenticatedRemote,
    user: _user,
    company: _company(entitlements),
    startedAt: DateTime(2026, 5, 7),
    isOfflineFallback: false,
    clientInstanceId: 'device-1',
    membership: const AppMembershipContext(
      role: 'OWNER',
      permissions: {'subscription.manage'},
    ),
  );
}

const _user = AppUser(
  localId: null,
  remoteId: 'user-1',
  displayName: 'Operador',
  email: 'operador@tatuzin.test',
  roleLabel: 'Operador',
  kind: AppUserKind.remoteAuthenticated,
);

CompanyContext _company(PlanEntitlements entitlements) {
  return CompanyContext(
    localId: null,
    remoteId: 'company-1',
    displayName: 'Cafe Oliveira',
    legalName: 'Cafe Oliveira LTDA',
    documentNumber: null,
    licensePlan: entitlements.plan.key,
    licenseStatus: 'active',
    syncEnabled: true,
    entitlements: entitlements,
  );
}
