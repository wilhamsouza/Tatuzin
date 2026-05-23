import 'package:tatuzin/app/core/database/app_database.dart';
import 'package:tatuzin/app/core/session/app_session.dart';
import 'package:tatuzin/app/core/session/app_user.dart';
import 'package:tatuzin/app/core/session/company_context.dart';
import 'package:tatuzin/app/core/session/session_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

List<Override> testTenantBootstrapOverrides() {
  return [
    appStartupProvider.overrideWith(
      (ref) async => const AppStartupState.success(),
    ),
  ];
}

void setTestTenantSession(
  ProviderContainer container, {
  String companyId = 'company-1',
  String userId = 'user-1',
  String clientInstanceId = 'device-1',
}) {
  container
      .read(appSessionProvider.notifier)
      .setAuthenticatedSession(
        scope: SessionScope.authenticatedRemote,
        user: AppUser(
          localId: 1,
          remoteId: userId,
          displayName: 'Operador',
          email: 'operador@tatuzin.test',
          roleLabel: 'Operador',
          kind: AppUserKind.remoteAuthenticated,
        ),
        company: CompanyContext(
          localId: 1,
          remoteId: companyId,
          displayName: 'Empresa',
          legalName: 'Empresa LTDA',
          documentNumber: null,
          licensePlan: 'trial',
          licenseStatus: 'active',
          syncEnabled: true,
        ),
        clientInstanceId: clientInstanceId,
      );
}
