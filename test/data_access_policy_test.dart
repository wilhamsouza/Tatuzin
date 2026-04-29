import 'package:erp_pdv_app/app/core/app_context/data_access_policy.dart';
import 'package:erp_pdv_app/app/core/config/app_data_mode.dart';
import 'package:erp_pdv_app/app/core/config/app_environment.dart';
import 'package:erp_pdv_app/app/core/app_context/app_operational_context.dart';
import 'package:erp_pdv_app/app/core/session/app_session.dart';
import 'package:erp_pdv_app/app/core/session/app_user.dart';
import 'package:erp_pdv_app/app/core/session/company_context.dart';
import 'package:erp_pdv_app/app/core/sync/sync_feature_keys.dart';
import 'package:erp_pdv_app/app/core/sync/sync_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('module strategies match current Tatuzin architecture', () {
    expect(strategyForModule(AppModule.pdv), DataSourceStrategy.localFirst);
    expect(strategyForModule(AppModule.erp), DataSourceStrategy.serverFirst);
    expect(strategyForModule(AppModule.crm), DataSourceStrategy.serverFirst);
  });

  test('remote ready mode no longer keeps local as global source of truth', () {
    expect(AppDataMode.localOnly.keepsLocalAsSourceOfTruth, isTrue);
    expect(AppDataMode.futureRemoteReady.keepsLocalAsSourceOfTruth, isFalse);
    expect(AppDataMode.futureHybridReady.keepsLocalAsSourceOfTruth, isFalse);
  });

  test('remote ready mode allows background cloud sync writes', () {
    final policy = DataAccessPolicy.fromMode(AppDataMode.futureRemoteReady);
    expect(policy.allowRemoteRead, isTrue);
    expect(policy.allowRemoteWrite, isTrue);
    expect(AppEnvironment.remoteDefault().remoteSyncEnabled, isTrue);
  });

  test(
    'authenticated remote context can use cloud writes in remote ready mode',
    () {
      final context = AppOperationalContext(
        environment: AppEnvironment.remoteDefault(),
        session: AppSession(
          scope: SessionScope.authenticatedRemote,
          user: const AppUser(
            localId: null,
            remoteId: 'user-1',
            displayName: 'Operador',
            email: 'operador@tatuzin.test',
            roleLabel: 'Operador',
            kind: AppUserKind.remoteAuthenticated,
          ),
          company: const CompanyContext(
            localId: null,
            remoteId: 'company-1',
            displayName: 'Empresa',
            legalName: 'Empresa LTDA',
            documentNumber: null,
            licensePlan: 'pro',
            licenseStatus: 'active',
            syncEnabled: true,
          ),
          startedAt: DateTime(2026, 4, 28),
          isOfflineFallback: false,
        ),
      );

      expect(context.canUseCloudWrites, isTrue);
    },
  );

  test('batch processor list includes PDV pending sync features', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final featureKeys = container
        .read(syncFeatureProcessorsProvider)
        .map((processor) => processor.featureKey)
        .toSet();

    expect(featureKeys, contains(SyncFeatureKeys.sales));
    expect(featureKeys, contains(SyncFeatureKeys.saleCancellations));
    expect(featureKeys, contains(SyncFeatureKeys.fiadoPayments));
    expect(featureKeys, contains(SyncFeatureKeys.cashEvents));
  });
}
