import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_data_mode.dart';
import '../config/app_environment.dart';
import '../utils/app_logger.dart';
import 'app_session.dart';
import 'app_user.dart';
import 'company_context.dart';

final appSessionProvider = NotifierProvider<SessionController, AppSession>(
  SessionController.new,
);

final currentAppUserProvider = Provider<AppUser>((ref) {
  return ref.watch(appSessionProvider).user;
});

final currentCompanyContextProvider = Provider<CompanyContext>((ref) {
  return ref.watch(appSessionProvider).company;
});

final sessionIsolationKeyProvider = Provider<String>((ref) {
  return SessionIsolation.keyFor(ref.watch(appSessionProvider));
});

final sessionRuntimeKeyProvider = Provider<String>((ref) {
  return SessionIsolation.runtimeKeyFor(ref.watch(appSessionProvider));
});

final sessionGuardProvider = Provider<SessionGuardSnapshot>((ref) {
  final environment = ref.watch(appEnvironmentProvider);
  final session = ref.watch(appSessionProvider);

  return SessionGuardSnapshot(
    allowOperationalRoutes: session.hasOperationalIdentity,
    allowRemoteRoutes:
        environment.dataMode.allowsRemoteRead &&
        session.hasOperationalIdentity &&
        session.user.canUseRemoteFeatures,
    requiresAuthenticationBeforeRemote:
        environment.authEnabled && !session.hasOperationalIdentity,
  );
});

class SessionController extends Notifier<AppSession> {
  @override
  AppSession build() {
    return AppSession.localDefault();
  }

  void restoreLocalSession() {
    state = AppSession.localDefault();
  }

  void setAuthenticatedSession({
    required SessionScope scope,
    required AppUser user,
    required CompanyContext company,
    bool isOfflineFallback = false,
    String? clientInstanceId,
    AppMembershipContext? membership,
    AppEmployeeContext? employee,
    bool preserveRuntimeWhenSamePrincipal = false,
  }) {
    final previousState = state;
    final oldRuntimeKey = _safeRuntimeKeyFor(previousState);
    final nextStartedAt =
        _shouldPreserveRuntime(
          previousState: previousState,
          scope: scope,
          user: user,
          company: company,
          clientInstanceId: clientInstanceId,
          preserveRuntimeWhenSamePrincipal: preserveRuntimeWhenSamePrincipal,
        )
        ? previousState.startedAt
        : DateTime.now();
    final nextState = state.copyWith(
      scope: scope,
      user: user,
      company: company,
      startedAt: nextStartedAt,
      isOfflineFallback: isOfflineFallback,
      clientInstanceId: clientInstanceId,
      clearClientInstanceId: clientInstanceId == null,
      membership: membership,
      employee: employee,
      clearMembership: membership == null,
      clearEmployee: employee == null,
    );
    final newRuntimeKey = _safeRuntimeKeyFor(nextState);
    AppLogger.info(
      '[Session] runtime_key_resolved old=$oldRuntimeKey new=$newRuntimeKey',
    );
    state = nextState;
  }

  void signOutToLocalMode() {
    final oldRuntimeKey = _safeRuntimeKeyFor(state);
    final nextState = AppSession.localDefault();
    final newRuntimeKey = _safeRuntimeKeyFor(nextState);
    AppLogger.info(
      '[Session] runtime_key_resolved old=$oldRuntimeKey new=$newRuntimeKey',
    );
    state = nextState;
  }

  void updateCompany(CompanyContext company) {
    final previousState = state;
    final nextState = previousState.copyWith(company: company);
    if (_safeIsolationKeyFor(previousState) !=
        _safeIsolationKeyFor(nextState)) {
      state = nextState.copyWith(startedAt: DateTime.now());
      return;
    }
    state = nextState;
  }

  String _safeRuntimeKeyFor(AppSession session) {
    try {
      return SessionIsolation.runtimeKeyFor(session);
    } catch (_) {
      return 'invalid_session_runtime_key';
    }
  }

  bool _shouldPreserveRuntime({
    required AppSession previousState,
    required SessionScope scope,
    required AppUser user,
    required CompanyContext company,
    required String? clientInstanceId,
    required bool preserveRuntimeWhenSamePrincipal,
  }) {
    if (!preserveRuntimeWhenSamePrincipal) {
      return false;
    }
    final previousIsolationKey = _safeIsolationKeyFor(previousState);
    final nextPreview = previousState.copyWith(
      scope: scope,
      user: user,
      company: company,
      clientInstanceId: clientInstanceId,
      clearClientInstanceId: clientInstanceId == null,
    );
    return previousState.hasOperationalIdentity &&
        previousState.scope == scope &&
        previousState.user.remoteId == user.remoteId &&
        previousState.clientInstanceId == clientInstanceId &&
        previousIsolationKey != null &&
        previousIsolationKey == _safeIsolationKeyFor(nextPreview);
  }

  String? _safeIsolationKeyFor(AppSession session) {
    try {
      return SessionIsolation.keyFor(session);
    } catch (_) {
      return null;
    }
  }
}

abstract final class SessionIsolation {
  static const localKey = 'local_default';

  static String keyFor(AppSession session) {
    switch (session.scope) {
      case SessionScope.localDefault:
        return localKey;
      case SessionScope.authenticatedMock:
        return _companyScopedKey('mock', session);
      case SessionScope.authenticatedRemote:
        return _companyScopedKey('remote', session);
    }
  }

  static String runtimeKeyFor(AppSession session) {
    return '${keyFor(session)}:${session.startedAt.microsecondsSinceEpoch}';
  }

  static String _companyScopedKey(String prefix, AppSession session) {
    if (!session.user.hasRemoteIdentity) {
      throw StateError(
        'Sessao autenticada sem identificador remoto de usuario. '
        'O Tatuzin bloqueou o acesso local para evitar operacao sem dono.',
      );
    }
    final companyId = session.company.remoteId?.trim();
    if (companyId == null || companyId.isEmpty) {
      throw StateError(
        'Sessao autenticada sem identificador remoto de empresa. '
        'O Tatuzin bloqueou o acesso local para evitar mistura de tenants.',
      );
    }
    return '$prefix:$companyId';
  }
}

class SessionGuardSnapshot {
  const SessionGuardSnapshot({
    required this.allowOperationalRoutes,
    required this.allowRemoteRoutes,
    required this.requiresAuthenticationBeforeRemote,
  });

  final bool allowOperationalRoutes;
  final bool allowRemoteRoutes;
  final bool requiresAuthenticationBeforeRemote;
}
