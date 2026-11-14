import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/core/database/app_database.dart';
import '../../../app/core/database/table_names.dart';
import '../../../app/core/network/contracts/api_client_contract.dart';
import '../../../app/core/network/network_providers.dart';
import '../../../app/core/providers/app_data_refresh_provider.dart';
import '../../../app/core/providers/tenant_bootstrap_gate.dart';
import '../../../app/core/session/auth_token_storage.dart';
import '../../../app/core/session/session_provider.dart';
import '../data/onboarding_storage.dart';
import '../domain/onboarding_progress.dart';

final onboardingStorageProvider = Provider<OnboardingStorage>(
  (ref) => OnboardingStorage(),
);

final companyOnboardingProvider = FutureProvider<OnboardingProgress?>((
  ref,
) async {
  final session = ref.watch(appSessionProvider);
  final runtimeKey = ref.watch(sessionRuntimeKeyProvider);
  ref.watch(appDataRefreshProvider);
  if (!session.isCompanyOwner || !session.hasOperationalIdentity) return null;
  if (!session.company.onboardingEnabled) return const OnboardingProgress();
  await requireTenantBootstrapReady(ref, 'companyOnboardingProvider');
  final database = await ref.watch(appDatabaseProvider).database;
  final rows = await database.rawQuery('''
    SELECT
      EXISTS(SELECT 1 FROM ${TableNames.produtos} WHERE ativo = 1 AND deletado_em IS NULL) AS product_ready,
      EXISTS(SELECT 1 FROM ${TableNames.caixaSessoes}
        WHERE aguardando_confirmacao_troco_inicial = 0) AS cash_ready,
      (SELECT MIN(data_venda) FROM ${TableNames.vendas} WHERE status = 'ativa') AS first_sale
  ''');
  final local = OnboardingProgress(
    enabled: session.company.onboardingEnabled,
    productReady: rows.first['product_ready'] == 1,
    cashReady: rows.first['cash_ready'] == 1,
    completedAt: DateTime.tryParse(rows.first['first_sale'] as String? ?? ''),
  );
  final companyId = session.company.remoteId!;
  final storage = ref.read(onboardingStorageProvider);
  var progress = (await storage.read(companyId)).merge(local);
  if (ref.read(sessionRuntimeKeyProvider) != runtimeKey) return null;

  if (session.isRemoteAuthenticated && !session.isOfflineFallback) {
    try {
      final token = await ref.read(authTokenStorageProvider).readAccessToken();
      if (token != null && ref.read(sessionRuntimeKeyProvider) == runtimeKey) {
        final response = await ref
            .read(realApiClientProvider)
            .postJson(
              '/app/onboarding/reconcile',
              body: const {},
              options: ApiRequestOptions(
                timeout: const Duration(seconds: 3),
                headers: {
                  'Authorization': 'Bearer $token',
                  'X-Client-Instance-Id': session.clientInstanceId!,
                },
              ),
            );
        final remote = OnboardingProgress.fromJson(response.data);
        progress = progress.merge(remote, enabled: remote.enabled);
      }
    } catch (_) {
      // Optional onboarding stays usable from local records and the company cache.
    }
  }
  if (ref.read(sessionRuntimeKeyProvider) != runtimeKey) return null;
  try {
    await storage.save(companyId, progress);
  } catch (_) {
    // A preference-write failure cannot block a sale or the home screen.
  }
  return progress;
});
