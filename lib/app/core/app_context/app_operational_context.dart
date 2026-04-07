import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_data_mode.dart';
import '../config/app_environment.dart';
import '../session/app_session.dart';
import '../session/session_provider.dart';

class AppOperationalContext {
  const AppOperationalContext({
    required this.environment,
    required this.session,
  });

  final AppEnvironment environment;
  final AppSession session;

  int? get currentLocalUserId => session.user.localId;

  String? get currentRemoteUserId => session.user.remoteId;

  String? get currentRemoteCompanyId => session.company.remoteId;

  bool get isLocalOnly => environment.isLocalOnly;

  bool get hasRemoteSession =>
      session.isRemoteAuthenticated && currentRemoteCompanyId != null;

  bool get canUseCloudReads =>
      environment.dataMode != AppDataMode.localOnly &&
      hasRemoteSession &&
      session.company.allowsCloudSync;

  bool get canUseCloudWrites =>
      environment.dataMode == AppDataMode.futureHybridReady &&
      hasRemoteSession &&
      session.company.allowsCloudSync;

  String? get cloudSyncRestrictionReason {
    if (!hasRemoteSession) {
      return 'Faca login remoto antes de acessar os recursos cloud.';
    }
    return session.company.cloudSyncRestrictionReason;
  }
}

final appOperationalContextProvider = Provider<AppOperationalContext>((ref) {
  return AppOperationalContext(
    environment: ref.watch(appEnvironmentProvider),
    session: ref.watch(appSessionProvider),
  );
});
