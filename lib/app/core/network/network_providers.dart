import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_data_mode.dart';
import '../config/app_environment.dart';
import '../session/auth_token_storage.dart';
import '../session/session_provider.dart';
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
