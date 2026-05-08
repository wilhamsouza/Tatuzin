import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/network/network_providers.dart';
import '../../../../app/core/entitlements/plan_entitlements.dart';
import '../../../../app/core/providers/app_data_refresh_provider.dart';
import '../../../../app/core/session/auth_provider.dart';
import '../../../../app/core/session/auth_token_storage.dart';
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

final billingInvoicesProvider = FutureProvider.autoDispose<BillingInvoicesPage>(
  (ref) async {
    ref.watch(appDataRefreshProvider);
    return ref.watch(billingRemoteDataSourceProvider).fetchInvoices();
  },
);

final billingPaymentMethodProvider =
    FutureProvider.autoDispose<BillingPaymentMethod>((ref) async {
      ref.watch(appDataRefreshProvider);
      return ref.watch(billingRemoteDataSourceProvider).fetchPaymentMethod();
    });

final billingControllerProvider =
    AsyncNotifierProvider<BillingController, void>(BillingController.new);

class BillingController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<BillingSubscribeResult> subscribe(PlanKey plan) async {
    state = const AsyncLoading();
    try {
      final result = await ref
          .read(billingRemoteDataSourceProvider)
          .subscribe(plan: plan.key);
      state = const AsyncData(null);
      return result;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<BillingActionResult> cancelSubscription({
    String effective = 'period_end',
  }) async {
    state = const AsyncLoading();
    try {
      final result = await ref
          .read(billingRemoteDataSourceProvider)
          .cancelSubscription(effective: effective);
      state = const AsyncData(null);
      return result;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<BillingActionResult> resumeSubscription() async {
    state = const AsyncLoading();
    try {
      final result = await ref
          .read(billingRemoteDataSourceProvider)
          .resumeSubscription();
      state = const AsyncData(null);
      return result;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<BillingActionResult> changePlan(PlanKey plan) async {
    state = const AsyncLoading();
    try {
      final result = await ref
          .read(billingRemoteDataSourceProvider)
          .changePlan(plan);
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
      final dataSource = ref.read(billingRemoteDataSourceProvider);
      await dataSource.refresh();
      final status = await dataSource.fetchStatus();
      await ref
          .read(authControllerProvider.notifier)
          .refreshAuthenticatedSession();
      ref.read(appDataRefreshProvider.notifier).state++;
      ref.invalidate(billingStatusProvider);
      ref.invalidate(billingInvoicesProvider);
      ref.invalidate(billingPaymentMethodProvider);
      state = const AsyncData(null);
      return status;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }
}
