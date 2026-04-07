import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_data_mode.dart';
import '../config/app_environment.dart';
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

final sessionGuardProvider = Provider<SessionGuardSnapshot>((ref) {
  final environment = ref.watch(appEnvironmentProvider);
  final session = ref.watch(appSessionProvider);

  return SessionGuardSnapshot(
    allowOperationalRoutes: true,
    allowRemoteRoutes:
        environment.dataMode.allowsRemoteRead &&
        session.user.canUseRemoteFeatures,
    requiresAuthenticationBeforeRemote:
        environment.authEnabled && !session.isAuthenticated,
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
  }) {
    state = state.copyWith(
      scope: scope,
      user: user,
      company: company,
      startedAt: DateTime.now(),
      isOfflineFallback: isOfflineFallback,
    );
  }

  void signOutToLocalMode() {
    state = AppSession.localDefault();
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
