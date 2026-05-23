import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/database/app_database.dart';
import '../../../../app/core/network/network_providers.dart';
import '../../../../app/core/entitlements/plan_entitlements.dart';
import '../../../../app/core/errors/app_exceptions.dart';
import '../../../../app/core/providers/app_data_refresh_provider.dart';
import '../../../../app/core/session/auth_provider.dart';
import '../../../../app/core/session/auth_token_storage.dart';
import '../../../../app/core/utils/app_logger.dart';
import '../../../dashboard/presentation/providers/dashboard_providers.dart';
import '../../data/billing_remote_data_source.dart';
import '../../domain/billing_models.dart';
import 'checkout_launcher.dart';

final billingRemoteDataSourceProvider = Provider<BillingRemoteDataSource>((
  ref,
) {
  return BillingRemoteDataSource(
    apiClient: ref.watch(realApiClientProvider),
    tokenStorage: ref.watch(authTokenStorageProvider),
  );
});

final checkoutLauncherProvider = Provider<CheckoutLauncher>((ref) {
  return const UrlLauncherCheckoutLauncher();
});

final billingPlansProvider = FutureProvider<List<BillingPlan>>((ref) async {
  ref.watch(appDataRefreshProvider);
  return ref.watch(billingRemoteDataSourceProvider).fetchPlans();
});

final billingStatusProvider = FutureProvider<BillingStatus>((ref) async {
  ref.watch(appDataRefreshProvider);
  return ref.watch(billingRemoteDataSourceProvider).fetchStatus();
});

final billingControllerProvider =
    AsyncNotifierProvider<BillingController, void>(BillingController.new);

class BillingController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<BillingSubscribeResult> subscribe(PlanKey plan) async {
    state = const AsyncLoading();
    try {
      final result = await _withRemoteSessionRestored(
        () =>
            ref.read(billingRemoteDataSourceProvider).subscribe(plan: plan.key),
      );
      state = const AsyncData(null);
      return result;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<BillingStatus> refreshStatus() async {
    state = const AsyncLoading();
    try {
      final status = await _withRemoteSessionRestored(
        () => ref.read(billingRemoteDataSourceProvider).refresh(),
      );
      await ref
          .read(authControllerProvider.notifier)
          .refreshAuthenticatedSession();
      await _reloadAppStateAfterBillingRefresh();
      state = const AsyncData(null);
      return status;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<T> _withRemoteSessionRestored<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on AuthenticationException {
      final restored = await ref
          .read(authControllerProvider.notifier)
          .restoreRemoteSession();
      if (restored == null) {
        throw const AuthenticationException(
          'Sua sessão expirou. Entre novamente para gerenciar a assinatura.',
        );
      }
      return action();
    }
  }

  Future<void> _reloadAppStateAfterBillingRefresh() async {
    AppLogger.info('[Billing] post_refresh_app_reload_started');
    ref.invalidate(appStartupProvider);
    try {
      await ref.read(appStartupProvider.future);
    } catch (error, stackTrace) {
      AppLogger.error(
        '[Billing] post_refresh_bootstrap_reload_failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
    ref.invalidate(billingStatusProvider);
    ref.read(appDataRefreshProvider.notifier).state++;
    ref.invalidate(operationalDashboardSnapshotProvider);
    AppLogger.info('[Billing] post_refresh_app_reload_finished');
  }
}
