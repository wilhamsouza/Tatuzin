import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_environment.dart';
import '../session/auth_token_storage.dart';
import '../session/session_provider.dart';
import 'contracts/api_client_contract.dart';
import 'fakes/fake_api_client.dart';
import 'real/real_api_client.dart';

final fakeApiClientProvider = Provider<ApiClientContract>((ref) {
  return FakeApiClient(ref.watch(appEnvironmentProvider).endpointConfig);
});

final realApiClientProvider = Provider<ApiClientContract>((ref) {
  return RealApiClient(
    ref.watch(appEnvironmentProvider).endpointConfig,
    tokenStorage: ref.watch(authTokenStorageProvider),
    onSessionInvalidated: () async {
      ref.read(appSessionProvider.notifier).signOutToLocalMode();
    },
  );
});

final apiClientProvider = Provider<ApiClientContract>((ref) {
  return ref.read(fakeApiClientProvider);
});
