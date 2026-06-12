import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_data_mode.dart';
import '../config/app_environment.dart';
import '../errors/app_exceptions.dart';
import '../session/app_session.dart';
import '../session/session_provider.dart';
import '../session/tenant_operational_block.dart';

class AppOperationalContext {
  const AppOperationalContext({
    required this.environment,
    required this.session,
    this.tenantBlock,
  });

  final AppEnvironment environment;
  final AppSession session;
  final TenantOperationalBlock? tenantBlock;

  int? get currentLocalUserId => session.user.localId;

  String? get currentRemoteUserId => session.user.remoteId;

  String? get currentRemoteCompanyId => session.company.remoteId;

  bool get isLocalOnly => environment.isLocalOnly;

  bool get hasRemoteSession =>
      session.isRemoteAuthenticated && session.hasOperationalIdentity;

  bool get isTenantPendingDeletion => tenantBlock?.appliesTo(session) ?? false;

  bool get canUseCloudReads =>
      environment.dataMode != AppDataMode.localOnly &&
      hasRemoteSession &&
      !isTenantPendingDeletion &&
      session.company.allowsCloudSync;

  bool get canUseCloudWrites =>
      environment.dataMode != AppDataMode.localOnly &&
      hasRemoteSession &&
      !isTenantPendingDeletion &&
      session.company.allowsCloudSync;

  String? get cloudSyncRestrictionReason {
    if (isTenantPendingDeletion) {
      return tenantPendingDeletionMessage;
    }
    if (!hasRemoteSession) {
      return 'Faca login remoto antes de acessar os recursos cloud.';
    }
    return session.company.cloudSyncRestrictionReason;
  }

  void ensureOperationalWriteAllowed() {
    ensureTenantOperationalWriteAllowed(tenantBlock, session);
  }
}

final appOperationalContextProvider = Provider<AppOperationalContext>((ref) {
  return AppOperationalContext(
    environment: ref.watch(appEnvironmentProvider),
    session: ref.watch(appSessionProvider),
    tenantBlock: ref.read(tenantOperationalBlockControllerProvider).valueOrNull,
  );
});
