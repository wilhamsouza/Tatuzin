import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_environment.dart';
import '../errors/app_exceptions.dart';
import '../network/contracts/auth_gateway.dart';
import '../network/fakes/fake_auth_gateway.dart';
import '../network/real/remote_auth_gateway.dart';
import '../network/network_providers.dart';
import 'app_session.dart';
import 'auth_token_storage.dart';
import 'session_provider.dart';

final mockAuthGatewayProvider = Provider<AuthGateway>((ref) {
  return FakeAuthGateway();
});

final remoteAuthGatewayProvider = Provider<AuthGateway>((ref) {
  return RemoteAuthGateway(
    apiClient: ref.watch(realApiClientProvider),
    tokenStorage: ref.watch(authTokenStorageProvider),
  );
});

final authControllerProvider = AsyncNotifierProvider<AuthController, void>(
  AuthController.new,
);

final authStatusProvider = Provider<AuthStatusSnapshot>((ref) {
  final session = ref.watch(appSessionProvider);
  final environment = ref.watch(appEnvironmentProvider);
  return AuthStatusSnapshot(
    isAuthenticated: session.isAuthenticated,
    isMockAuthenticated: session.isMockAuthenticated,
    isRemoteAuthenticated: session.isRemoteAuthenticated,
    isPlatformAdmin: session.user.isPlatformAdmin,
    sessionLabel: session.user.statusLabel,
    userLabel: session.user.displayName,
    companyLabel: session.company.displayName,
    email: session.user.email,
    canAttemptRemoteLogin:
        environment.authEnabled && environment.endpointConfig.isConfigured,
    endpointLabel: environment.endpointConfig.summaryLabel,
    licensePlanLabel: session.company.licensePlanLabel,
    licenseStatusLabel: session.company.licenseStatusLabel,
    licenseExpiresAt: session.company.licenseExpiresAt,
    cloudSyncEnabled: session.company.allowsCloudSync,
    cloudSyncLabel: session.company.cloudSyncLabel,
  );
});

class AuthController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() async {
    final environment = ref.watch(appEnvironmentProvider);
    if (!environment.authEnabled || !environment.endpointConfig.isConfigured) {
      return;
    }

    try {
      final session = await ref
          .read(remoteAuthGatewayProvider)
          .restoreSession();
      if (session != null) {
        _applySession(session);
      }
    } on AppException {
      ref.read(appSessionProvider.notifier).signOutToLocalMode();
    }
  }

  Future<AppSession> signInMock() async {
    state = const AsyncLoading();
    try {
      final session = await ref
          .read(mockAuthGatewayProvider)
          .signIn(
            identifier: 'mock.operator@simples.local',
            password: '123456',
          );
      _applySession(session);
      state = const AsyncData(null);
      return session;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<AppSession> signInRemote({
    required String email,
    required String password,
  }) async {
    final environment = ref.read(appEnvironmentProvider);
    if (!environment.authEnabled || !environment.endpointConfig.isConfigured) {
      throw const ValidationException(
        'Ative um modo com backend configurado para usar login remoto.',
      );
    }

    state = const AsyncLoading();
    try {
      final session = await ref
          .read(remoteAuthGatewayProvider)
          .signIn(identifier: email, password: password);
      _applySession(session);
      state = const AsyncData(null);
      return session;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<AppSession> signUpRemote({
    required String companyName,
    required String companySlug,
    required String userName,
    required String email,
    required String password,
  }) async {
    final environment = ref.read(appEnvironmentProvider);
    if (!environment.authEnabled || !environment.endpointConfig.isConfigured) {
      throw const ValidationException(
        'Ative um modo com backend configurado para usar cadastro remoto.',
      );
    }

    state = const AsyncLoading();
    try {
      final session = await ref
          .read(remoteAuthGatewayProvider)
          .signUp(
            companyName: companyName,
            companySlug: companySlug,
            userName: userName,
            email: email,
            password: password,
          );
      _applySession(session);
      state = const AsyncData(null);
      return session;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<AppSession?> restoreRemoteSession() async {
    state = const AsyncLoading();
    try {
      final session = await ref
          .read(remoteAuthGatewayProvider)
          .restoreSession();
      if (session != null) {
        _applySession(session);
      }
      state = const AsyncData(null);
      return session;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<String> forgotPasswordRemote({required String email}) async {
    final environment = ref.read(appEnvironmentProvider);
    if (!environment.authEnabled || !environment.endpointConfig.isConfigured) {
      throw const ValidationException(
        'Ative um modo com backend configurado para recuperar a senha remota.',
      );
    }

    state = const AsyncLoading();
    try {
      final message = await ref
          .read(remoteAuthGatewayProvider)
          .requestPasswordReset(email: email);
      state = const AsyncData(null);
      return message;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<String> resetPasswordRemote({
    required String token,
    required String newPassword,
  }) async {
    final environment = ref.read(appEnvironmentProvider);
    if (!environment.authEnabled || !environment.endpointConfig.isConfigured) {
      throw const ValidationException(
        'Ative um modo com backend configurado para redefinir a senha remota.',
      );
    }

    state = const AsyncLoading();
    try {
      final message = await ref
          .read(remoteAuthGatewayProvider)
          .resetPassword(token: token, newPassword: newPassword);
      state = const AsyncData(null);
      return message;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<void> signOutCurrentSession() async {
    state = const AsyncLoading();
    try {
      final session = ref.read(appSessionProvider);
      if (session.isRemoteAuthenticated) {
        await ref.read(remoteAuthGatewayProvider).signOut();
      } else if (session.isMockAuthenticated) {
        await ref.read(mockAuthGatewayProvider).signOut();
      }

      ref.read(appSessionProvider.notifier).signOutToLocalMode();
      state = const AsyncData(null);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<void> signOutMock() => signOutCurrentSession();

  Future<void> signOutRemote() => signOutCurrentSession();

  void resetStatus() {
    state = const AsyncData(null);
  }

  void _applySession(AppSession session) {
    ref
        .read(appSessionProvider.notifier)
        .setAuthenticatedSession(
          scope: session.scope,
          user: session.user,
          company: session.company,
          isOfflineFallback: session.isOfflineFallback,
        );
  }
}

class AuthStatusSnapshot {
  const AuthStatusSnapshot({
    required this.isAuthenticated,
    required this.isMockAuthenticated,
    required this.isRemoteAuthenticated,
    required this.isPlatformAdmin,
    required this.sessionLabel,
    required this.userLabel,
    required this.companyLabel,
    required this.email,
    required this.canAttemptRemoteLogin,
    required this.endpointLabel,
    required this.licensePlanLabel,
    required this.licenseStatusLabel,
    required this.licenseExpiresAt,
    required this.cloudSyncEnabled,
    required this.cloudSyncLabel,
  });

  final bool isAuthenticated;
  final bool isMockAuthenticated;
  final bool isRemoteAuthenticated;
  final bool isPlatformAdmin;
  final String sessionLabel;
  final String userLabel;
  final String companyLabel;
  final String? email;
  final bool canAttemptRemoteLogin;
  final String endpointLabel;
  final String licensePlanLabel;
  final String licenseStatusLabel;
  final DateTime? licenseExpiresAt;
  final bool cloudSyncEnabled;
  final String cloudSyncLabel;
}
