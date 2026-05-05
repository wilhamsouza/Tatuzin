import 'package:erp_pdv_app/app/app.dart';
import 'package:erp_pdv_app/app/core/config/app_data_mode.dart';
import 'package:erp_pdv_app/app/core/config/app_environment.dart';
import 'package:erp_pdv_app/app/core/database/app_database.dart';
import 'package:erp_pdv_app/app/core/errors/app_exceptions.dart';
import 'package:erp_pdv_app/app/core/network/contracts/auth_gateway.dart';
import 'package:erp_pdv_app/app/core/network/fakes/fake_auth_gateway.dart';
import 'package:erp_pdv_app/app/core/session/app_session.dart';
import 'package:erp_pdv_app/app/core/session/app_user.dart';
import 'package:erp_pdv_app/app/core/session/auth_provider.dart';
import 'package:erp_pdv_app/app/core/session/cached_session_storage.dart';
import 'package:erp_pdv_app/app/core/session/company_context.dart';
import 'package:erp_pdv_app/app/core/session/session_provider.dart';
import 'package:erp_pdv_app/app/core/session/session_reset.dart';
import 'package:erp_pdv_app/app/core/sync/sync_providers.dart';
import 'package:erp_pdv_app/modules/auth/presentation/pages/login_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('botao Continuar offline nao aparece no login', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialAppEnvironmentProvider.overrideWith(
            (ref) => _remoteEnvironment,
          ),
          sessionContextResetProvider.overrideWith((ref) {}),
          remoteAuthGatewayProvider.overrideWith((ref) => _NoSessionGateway()),
          appStartupProvider.overrideWith(
            (ref) async => const AppStartupState.success(),
          ),
        ],
        child: const ErpPdvApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.text('Continuar offline'), findsNothing);
  });

  test('FakeAuthGateway simula tenant completo, sem convidado', () async {
    final session = await FakeAuthGateway().signIn(
      identifier: 'mock.operator@tatuzin.test',
      password: '123456',
    );

    expect(session.hasOperationalIdentity, isTrue);
    expect(session.company.remoteId, isNotEmpty);
    expect(session.user.remoteId, isNotEmpty);
    expect(session.clientInstanceId, isNotEmpty);
    expect(session.company.licenseStatus, 'active');
    expect(session.isOfflineFallback, isFalse);
    expect(session.isLocalDefault, isFalse);
  });

  test('primeiro acesso sem internet e sem cache local e bloqueado', () async {
    final container = ProviderContainer(
      overrides: [
        initialAppEnvironmentProvider.overrideWith((ref) => _remoteEnvironment),
        remoteAuthGatewayProvider.overrideWith(
          (ref) => _NetworkFailureGateway(),
        ),
        cachedSessionStorageProvider.overrideWith(
          (ref) => _MemoryCachedSessionStorage(),
        ),
      ],
    );
    addTearDown(container.dispose);

    await expectLater(
      () => container
          .read(authControllerProvider.notifier)
          .signInRemote(email: 'owner@tatuzin.test', password: '12345678'),
      throwsA(
        isA<NetworkRequestException>().having(
          (error) => error.message,
          'message',
          firstAccessRequiresConnectionMessage,
        ),
      ),
    );
  });

  test('sessao local anterior com tenant permite entrada offline', () async {
    final cachedSession = _remoteSession().copyWith(isOfflineFallback: true);
    final container = ProviderContainer(
      overrides: [
        initialAppEnvironmentProvider.overrideWith((ref) => _remoteEnvironment),
        remoteAuthGatewayProvider.overrideWith(
          (ref) => _NetworkFailureGateway(),
        ),
        cachedSessionStorageProvider.overrideWith(
          (ref) => _MemoryCachedSessionStorage(cachedSession),
        ),
        tenantDatabaseExistsProvider.overrideWith((ref) {
          return (isolationKey) async => true;
        }),
        appStartupOpenDatabaseProvider.overrideWith((ref) {
          return (isolationKey) async {};
        }),
      ],
    );
    addTearDown(container.dispose);

    final session = await container
        .read(authControllerProvider.notifier)
        .restoreRemoteSession();

    expect(session, isNotNull);
    expect(session!.isOfflineFallback, isTrue);
    expect(container.read(appSessionProvider).company.remoteId, 'company-1');
    expect((await container.read(appStartupProvider.future)).isSuccess, isTrue);
  });

  test(
    'sync nao processa lote sem companyId userId e clientInstanceId',
    () async {
      final container = ProviderContainer(
        overrides: [
          appStartupProvider.overrideWith(
            (ref) async => const AppStartupState.success(),
          ),
          operationalSyncRunnerProvider.overrideWith((ref) {
            throw StateError('sync operacional nao deveria iniciar');
          }),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(appSessionProvider.notifier)
          .setAuthenticatedSession(
            scope: SessionScope.authenticatedRemote,
            user: _remoteUser(),
            company: _remoteCompany(),
            isOfflineFallback: false,
          );

      final result = await container
          .read(syncBatchRunnerProvider)
          .run(retryOnly: false);

      expect(result.processedCount, 0);
      expect(result.syncedCount, 0);
    },
  );

  test('sync nao inicia antes do TenantBootstrap pronto', () async {
    final container = ProviderContainer(
      overrides: [
        appStartupProvider.overrideWith(
          (ref) async =>
              AppStartupState.apiError(message: 'TenantBootstrap pendente'),
        ),
        operationalSyncRunnerProvider.overrideWith((ref) {
          throw StateError('sync operacional nao deveria iniciar');
        }),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(appSessionProvider.notifier)
        .setAuthenticatedSession(
          scope: SessionScope.authenticatedRemote,
          user: _remoteUser(),
          company: _remoteCompany(),
          isOfflineFallback: false,
          clientInstanceId: 'device-1',
        );

    final result = await container
        .read(syncBatchRunnerProvider)
        .run(retryOnly: false);

    expect(result.processedCount, 0);
    expect(result.syncedCount, 0);
  });

  test('banco operacional nao abre sem companyId', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      () => container.read(appDatabaseProvider),
      throwsA(isA<AppStartupException>()),
    );
  });
}

AppEnvironment get _remoteEnvironment {
  return AppEnvironment.remoteDefault().copyWith(
    dataMode: AppDataMode.futureHybridReady,
    remoteSyncEnabled: true,
  );
}

AppUser _remoteUser() {
  return const AppUser(
    localId: null,
    remoteId: 'user-1',
    displayName: 'Operador',
    email: 'operador@tatuzin.test',
    roleLabel: 'Operador',
    kind: AppUserKind.remoteAuthenticated,
  );
}

CompanyContext _remoteCompany() {
  return const CompanyContext(
    localId: null,
    remoteId: 'company-1',
    displayName: 'Cafe Oliveira',
    legalName: 'Cafe Oliveira LTDA',
    documentNumber: null,
    licensePlan: 'trial',
    licenseStatus: 'trial',
    syncEnabled: true,
  );
}

AppSession _remoteSession() {
  return AppSession(
    scope: SessionScope.authenticatedRemote,
    user: _remoteUser(),
    company: _remoteCompany(),
    startedAt: DateTime(2026, 5, 4, 12),
    isOfflineFallback: false,
    clientInstanceId: 'device-1',
  );
}

class _MemoryCachedSessionStorage implements CachedSessionStorage {
  _MemoryCachedSessionStorage([this.session]);

  AppSession? session;

  @override
  Future<void> clear() async {
    session = null;
  }

  @override
  Future<AppSession?> readSession() async => session;

  @override
  Future<void> saveSession(AppSession session) async {
    this.session = session;
  }
}

class _NoSessionGateway implements AuthGateway {
  @override
  Future<AppSession?> restoreSession() async => null;

  @override
  Future<AppSession> refreshSession() => throw UnimplementedError();

  @override
  Future<AppSession> signIn({
    required String identifier,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<AppSession> signUp({
    required String companyName,
    required String companySlug,
    required String userName,
    required String email,
    required String password,
  }) => throw UnimplementedError();

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

class _NetworkFailureGateway extends _NoSessionGateway {
  @override
  Future<AppSession?> restoreSession() async {
    throw const NetworkRequestException('backend offline');
  }

  @override
  Future<AppSession> signIn({
    required String identifier,
    required String password,
  }) async {
    throw const NetworkRequestException('backend offline');
  }
}
