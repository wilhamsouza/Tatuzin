import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_data_mode.dart';
import '../config/app_environment.dart';
import '../session/cached_session_storage.dart';
import '../session/auth_token_storage.dart';
import '../session/session_provider.dart';
import '../session/tenant_operational_block.dart';
import '../utils/app_logger.dart';
import 'contracts/api_client_contract.dart';
import 'fakes/fake_api_client.dart';
import 'real/real_api_client.dart';

final fakeApiClientProvider = Provider<ApiClientContract>((ref) {
  return FakeApiClient(ref.watch(appEnvironmentProvider).endpointConfig);
});

final realApiClientProvider = Provider<ApiClientContract>((ref) {
  final endpointConfig = ref.watch(appEnvironmentProvider).endpointConfig;
  AppLogger.info(
    '[API] baseUrl configurada: ${endpointConfig.baseUrl ?? 'nao configurada'}',
  );
  return RealApiClient(
    endpointConfig,
    tokenStorage: ref.watch(authTokenStorageProvider),
    onSessionInvalidated: () async {
      ref.read(appSessionProvider.notifier).signOutToLocalMode();
    },
    onTenantPendingDeletion: (exception) async {
      final currentSession = ref.read(appSessionProvider);
      var companyId =
          exception.companyId ?? currentSession.company.remoteId?.trim();
      var companyName = currentSession.company.displayName.trim();

      final isLoginRequest =
          exception.requestPath == '/auth/login' ||
          exception.requestPath == '/auth/register';
      if ((companyId == null || companyId.isEmpty) && !isLoginRequest) {
        final cachedSession = await ref
            .read(cachedSessionStorageProvider)
            .readSession();
        companyId = cachedSession?.company.remoteId?.trim();
        companyName = cachedSession?.company.displayName.trim() ?? '';
      }

      if (companyId != null && companyId.isNotEmpty) {
        final clientContext = await ref
            .read(authTokenStorageProvider)
            .readClientContext();
        await ref
            .read(tenantOperationalBlockControllerProvider.notifier)
            .markPendingDeletion(
              companyId: companyId,
              companyName: companyName.isEmpty ? null : companyName,
              acknowledgementToken: exception.acknowledgementToken,
              tenantDeletionRequestId: exception.tenantDeletionRequestId,
              clientInstanceId:
                  exception.clientInstanceId ?? clientContext?.clientInstanceId,
              deviceLabel: clientContext?.deviceLabel,
              platform: clientContext?.platform,
              appVersion: clientContext?.appVersion,
            );
      }

      await ref.read(cachedSessionStorageProvider).clear();
      ref.read(appSessionProvider.notifier).signOutToLocalMode();
    },
  );
});

final apiClientProvider = Provider<ApiClientContract>((ref) {
  final environment = ref.watch(appEnvironmentProvider);
  if (environment.dataMode.allowsRemoteRead &&
      environment.endpointConfig.isConfigured) {
    return ref.watch(realApiClientProvider);
  }

  return ref.watch(fakeApiClientProvider);
});
