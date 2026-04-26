import 'dart:async';

import 'package:erp_pdv_app/app/core/config/app_data_mode.dart';
import 'package:erp_pdv_app/app/core/config/app_environment.dart';
import 'package:erp_pdv_app/app/core/database/app_database.dart';
import 'package:erp_pdv_app/app/core/errors/app_exceptions.dart';
import 'package:erp_pdv_app/app/core/network/contracts/auth_gateway.dart';
import 'package:erp_pdv_app/app/core/session/app_session.dart';
import 'package:erp_pdv_app/app/core/session/app_user.dart';
import 'package:erp_pdv_app/app/core/session/auth_provider.dart';
import 'package:erp_pdv_app/app/core/session/company_context.dart';
import 'package:erp_pdv_app/app/core/session/session_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('signInRemote with trial company completes bootstrap', () async {
    final session = _remoteSession(licenseStatus: 'trial');
    final syncKickoffs = <String>[];
    final container = ProviderContainer(
      overrides: [
        initialAppEnvironmentProvider.overrideWith((ref) => _remoteEnvironment),
        remoteAuthGatewayProvider.overrideWith((ref) {
          return _FakeAuthGateway(signInSession: session);
        }),
        appStartupOpenDatabaseProvider.overrideWith((ref) {
          return (isolationKey) async {};
        }),
        appStartupSyncKickoffProvider.overrideWith((ref) {
          return (bootSession) async {
            syncKickoffs.add(bootSession.company.remoteId ?? 'missing');
          };
        }),
      ],
    );
    addTearDown(container.dispose);

    final result = await container
        .read(authControllerProvider.notifier)
        .signInRemote(email: 'operador@tatuzin.test', password: '12345678');

    expect(result.company.isTrialLicense, isTrue);
    expect(
      container.read(appSessionProvider).company.remoteId,
      session.company.remoteId,
    );
    expect(syncKickoffs, [session.company.remoteId]);
    expect((await container.read(appStartupProvider.future)).isSuccess, isTrue);
  });

  test('signUpRemote with trial company completes bootstrap', () async {
    final session = _remoteSession(licenseStatus: 'trial');
    final container = ProviderContainer(
      overrides: [
        initialAppEnvironmentProvider.overrideWith((ref) => _remoteEnvironment),
        remoteAuthGatewayProvider.overrideWith((ref) {
          return _FakeAuthGateway(signUpSession: session);
        }),
        appStartupOpenDatabaseProvider.overrideWith((ref) {
          return (isolationKey) async {};
        }),
        appStartupSyncKickoffProvider.overrideWith((ref) {
          return (bootSession) async {};
        }),
      ],
    );
    addTearDown(container.dispose);

    final result = await container
        .read(authControllerProvider.notifier)
        .signUpRemote(
          companyName: 'Cafe Oliveira',
          companySlug: 'cafe-oliveira',
          userName: 'Oliveira',
          email: 'oliveira@tatuzin.test',
          password: '12345678',
        );

    expect(result.company.isTrialLicense, isTrue);
    expect((await container.read(appStartupProvider.future)).isSuccess, isTrue);
  });

  test('startup returns needsCompany when company remoteId is null', () async {
    final container = ProviderContainer(
      overrides: [
        appStartupOpenDatabaseProvider.overrideWith((ref) {
          return (isolationKey) async {};
        }),
      ],
    );
    addTearDown(container.dispose);

    container
        .read(appSessionProvider.notifier)
        .setAuthenticatedSession(
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
            remoteId: null,
            displayName: 'Sem tenant',
            legalName: 'Sem tenant',
            documentNumber: null,
            licensePlan: 'trial',
            licenseStatus: 'trial',
            syncEnabled: true,
          ),
          isOfflineFallback: false,
        );

    final state = await container.read(appStartupProvider.future);
    expect(state.status, AppStartupStatus.needsCompany);
  });

  test('startup shell does not block when sqlite open fails', () async {
    final container = ProviderContainer(
      overrides: [
        appStartupOpenDatabaseProvider.overrideWith((ref) {
          return (isolationKey) async {
            throw const DatabaseInitializationException('sqlite exploded');
          };
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

    final state = await container.read(appStartupProvider.future);
    expect(state.status, AppStartupStatus.success);
    expect(state.lastCompletedStep, 'navigation_shell_ready');
  });

  test('startup shell does not wait for sqlite open timeout', () async {
    final container = ProviderContainer(
      overrides: [
        appStartupLocalDatabaseTimeoutProvider.overrideWith((ref) {
          return const Duration(milliseconds: 50);
        }),
        appStartupOpenDatabaseProvider.overrideWith((ref) {
          return (isolationKey) => Completer<void>().future;
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

    final state = await container.read(appStartupProvider.future);
    expect(state.status, AppStartupStatus.success);
    expect(state.lastCompletedStep, 'navigation_shell_ready');
    expect(state.pendingStep, isNull);
  });

  test('startup returns apiError when post-login API responds 500', () async {
    final container = ProviderContainer(
      overrides: [
        appStartupRemotePreflightProvider.overrideWith((ref) {
          return (session) async {
            throw const NetworkRequestException('http 500');
          };
        }),
        appStartupOpenDatabaseProvider.overrideWith((ref) {
          return (isolationKey) async {};
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

    final state = await container.read(appStartupProvider.future);
    expect(state.status, AppStartupStatus.apiError);
  });

  test('startup returns apiError when post-login API responds 401', () async {
    final container = ProviderContainer(
      overrides: [
        appStartupRemotePreflightProvider.overrideWith((ref) {
          return (session) async {
            throw const AuthenticationException('http 401');
          };
        }),
        appStartupOpenDatabaseProvider.overrideWith((ref) {
          return (isolationKey) async {};
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

    final state = await container.read(appStartupProvider.future);
    expect(state.status, AppStartupStatus.apiError);
  });

  test(
    'startup returns timeout when bootstrap exceeds the guard window',
    () async {
      final container = ProviderContainer(
        overrides: [
          appStartupTimeoutProvider.overrideWith((ref) {
            return const Duration(milliseconds: 50);
          }),
          appStartupRemotePreflightProvider.overrideWith((ref) {
            return (session) => Completer<void>().future;
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

      final state = await container.read(appStartupProvider.future);
      expect(state.status, AppStartupStatus.timeout);
    },
  );

  test(
    'bootstrap does not depend on appDatabaseProvider to open tenant',
    () async {
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWith((ref) {
            throw StateError('appDatabaseProvider should not be read here');
          }),
          appStartupOpenDatabaseProvider.overrideWith((ref) {
            return (isolationKey) async {};
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

      final state = await container.read(appStartupProvider.future);
      expect(state.isSuccess, isTrue);
    },
  );
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

CompanyContext _remoteCompany({String licenseStatus = 'active'}) {
  return CompanyContext(
    localId: null,
    remoteId: 'company-1',
    displayName: 'Cafe Oliveira',
    legalName: 'Cafe Oliveira LTDA',
    documentNumber: '123456789',
    licensePlan: 'trial',
    licenseStatus: licenseStatus,
    syncEnabled: true,
  );
}

AppSession _remoteSession({required String licenseStatus}) {
  return AppSession(
    scope: SessionScope.authenticatedRemote,
    user: _remoteUser(),
    company: _remoteCompany(licenseStatus: licenseStatus),
    startedAt: DateTime(2026, 4, 23, 12),
    isOfflineFallback: false,
  );
}

class _FakeAuthGateway implements AuthGateway {
  _FakeAuthGateway({this.signInSession, this.signUpSession});

  final AppSession? signInSession;
  final AppSession? signUpSession;

  @override
  Future<AppSession?> restoreSession() async => null;

  @override
  Future<AppSession> refreshSession() async {
    throw const AuthenticationException('missing restore session');
  }

  @override
  Future<AppSession> signIn({
    required String identifier,
    required String password,
  }) async {
    final session = signInSession;
    if (session == null) {
      throw const AuthenticationException('missing sign-in session');
    }
    return session;
  }

  @override
  Future<AppSession> signUp({
    required String companyName,
    required String companySlug,
    required String userName,
    required String email,
    required String password,
  }) async {
    final session = signUpSession;
    if (session == null) {
      throw const AuthenticationException('missing sign-up session');
    }
    return session;
  }

  @override
  Future<String> requestPasswordReset({required String email}) async {
    return 'ok';
  }

  @override
  Future<String> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    return 'ok';
  }

  @override
  Future<void> signOut() async {}
}
