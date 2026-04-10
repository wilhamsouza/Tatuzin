import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/app_context/app_operational_context.dart';
import '../../../../app/core/app_context/data_access_policy.dart';
import '../../../../app/core/config/app_environment.dart';
import '../../../../app/core/database/app_database.dart';
import '../../../../app/core/network/network_providers.dart';
import '../../../../app/core/providers/app_data_refresh_provider.dart';
import '../../../../app/core/session/auth_token_storage.dart';
import '../../data/datasources/fiado_remote_datasource.dart';
import '../../data/fiado_payment_sync_processor.dart';
import '../../data/real/real_fiado_remote_datasource.dart';
import '../../data/sqlite_fiado_repository.dart';
import '../../domain/entities/fiado_account.dart';
import '../../domain/entities/fiado_detail.dart';
import '../../domain/entities/fiado_payment_input.dart';
import '../../domain/repositories/fiado_repository.dart';
import '../../domain/usecases/register_fiado_payment_use_case.dart';

final localFiadoRepositoryProvider = Provider<SqliteFiadoRepository>((ref) {
  return SqliteFiadoRepository(
    ref.read(appDatabaseProvider),
    ref.watch(appOperationalContextProvider),
  );
});

final fiadoRemoteDatasourceProvider = Provider<FiadoRemoteDatasource>((ref) {
  return RealFiadoRemoteDatasource(
    apiClient: ref.read(realApiClientProvider),
    tokenStorage: ref.read(authTokenStorageProvider),
    environment: ref.watch(appEnvironmentProvider),
    operationalContext: ref.watch(appOperationalContextProvider),
  );
});

final fiadoRepositoryProvider = Provider<FiadoRepository>((ref) {
  return ref.read(localFiadoRepositoryProvider);
});

final fiadoPaymentSyncProcessorProvider = Provider<FiadoPaymentSyncProcessor>((
  ref,
) {
  return FiadoPaymentSyncProcessor(
    localRepository: ref.read(localFiadoRepositoryProvider),
    remoteDatasource: ref.read(fiadoRemoteDatasourceProvider),
    operationalContext: ref.watch(appOperationalContextProvider),
    dataAccessPolicy: ref.watch(appDataAccessPolicyProvider),
  );
});

final fiadoSearchQueryProvider = StateProvider<String>((ref) => '');
final fiadoStatusFilterProvider = StateProvider<String?>((ref) => null);
final fiadoOverdueOnlyProvider = StateProvider<bool>((ref) => false);

final fiadoListProvider = FutureProvider<List<FiadoAccount>>((ref) async {
  ref.watch(appDataRefreshProvider);
  return ref
      .watch(fiadoRepositoryProvider)
      .search(
        query: ref.watch(fiadoSearchQueryProvider),
        status: ref.watch(fiadoStatusFilterProvider),
        overdueOnly: ref.watch(fiadoOverdueOnlyProvider),
      );
});

final fiadoDetailProvider = FutureProvider.family<FiadoDetail, int>((
  ref,
  fiadoId,
) async {
  ref.watch(appDataRefreshProvider);
  return ref.watch(fiadoRepositoryProvider).fetchDetail(fiadoId);
});

final registerFiadoPaymentUseCaseProvider =
    Provider<RegisterFiadoPaymentUseCase>((ref) {
      return RegisterFiadoPaymentUseCase(ref.read(fiadoRepositoryProvider));
    });

final fiadoPaymentControllerProvider =
    AsyncNotifierProvider<FiadoPaymentController, void>(
      FiadoPaymentController.new,
    );

class FiadoPaymentController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<FiadoDetail> registerPayment(FiadoPaymentInput input) async {
    state = const AsyncLoading();
    try {
      final detail = await ref
          .read(registerFiadoPaymentUseCaseProvider)
          .call(input);
      ref.read(appDataRefreshProvider.notifier).state++;
      state = const AsyncData(null);
      return detail;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }
}
