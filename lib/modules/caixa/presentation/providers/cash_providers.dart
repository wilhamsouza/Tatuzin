import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/app_context/app_operational_context.dart';
import '../../../../app/core/app_context/data_access_policy.dart';
import '../../../../app/core/config/app_environment.dart';
import '../../../../app/core/database/app_database.dart';
import '../../../../app/core/network/network_providers.dart';
import '../../../../app/core/providers/app_data_refresh_provider.dart';
import '../../../../app/core/session/auth_token_storage.dart';
import '../../data/cash_event_sync_processor.dart';
import '../../data/datasources/cash_remote_datasource.dart';
import '../../data/real/real_cash_remote_datasource.dart';
import '../../data/sqlite_cash_repository.dart';
import '../../domain/entities/cash_manual_movement_input.dart';
import '../../domain/entities/cash_movement.dart';
import '../../domain/entities/cash_session.dart';
import '../../domain/entities/cash_session_detail.dart';
import '../../domain/repositories/cash_repository.dart';
import '../../domain/usecases/close_cash_session_use_case.dart';
import '../../domain/usecases/open_cash_session_use_case.dart';

final localCashRepositoryProvider = Provider<SqliteCashRepository>((ref) {
  return SqliteCashRepository(
    ref.read(appDatabaseProvider),
    ref.watch(appOperationalContextProvider),
  );
});

final cashRemoteDatasourceProvider = Provider<CashRemoteDatasource>((ref) {
  return RealCashRemoteDatasource(
    apiClient: ref.read(realApiClientProvider),
    tokenStorage: ref.read(authTokenStorageProvider),
    environment: ref.watch(appEnvironmentProvider),
    operationalContext: ref.watch(appOperationalContextProvider),
  );
});

final cashRepositoryProvider = Provider<CashRepository>((ref) {
  return ref.read(localCashRepositoryProvider);
});

final cashEventSyncProcessorProvider = Provider<CashEventSyncProcessor>((ref) {
  return CashEventSyncProcessor(
    localRepository: ref.read(localCashRepositoryProvider),
    remoteDatasource: ref.read(cashRemoteDatasourceProvider),
    operationalContext: ref.watch(appOperationalContextProvider),
    dataAccessPolicy: ref.watch(appDataAccessPolicyProvider),
  );
});

final currentCashSessionProvider = FutureProvider<CashSession?>((ref) async {
  ref.watch(appDataRefreshProvider);
  return ref.watch(cashRepositoryProvider).getCurrentSession();
});

final currentCashMovementsProvider = FutureProvider<List<CashMovement>>((
  ref,
) async {
  ref.watch(appDataRefreshProvider);
  return ref.watch(cashRepositoryProvider).listCurrentSessionMovements();
});

final cashSessionHistoryProvider = FutureProvider<List<CashSession>>((
  ref,
) async {
  ref.watch(appDataRefreshProvider);
  return ref.watch(cashRepositoryProvider).listSessions();
});

final cashSessionDetailProvider =
    FutureProvider.family<CashSessionDetail, int>((ref, sessionId) async {
      ref.watch(appDataRefreshProvider);
      return ref.watch(cashRepositoryProvider).fetchSessionDetail(sessionId);
    });

final openCashSessionUseCaseProvider = Provider<OpenCashSessionUseCase>((ref) {
  return OpenCashSessionUseCase(ref.read(cashRepositoryProvider));
});

final closeCashSessionUseCaseProvider = Provider<CloseCashSessionUseCase>((
  ref,
) {
  return CloseCashSessionUseCase(ref.read(cashRepositoryProvider));
});

final cashActionControllerProvider =
    AsyncNotifierProvider<CashActionController, void>(CashActionController.new);

class CashActionController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<CashSession> openSession({
    required int initialFloatCents,
    String? notes,
  }) async {
    state = const AsyncLoading();
    try {
      final session = await ref
          .read(openCashSessionUseCaseProvider)
          .call(initialFloatCents: initialFloatCents, notes: notes);
      state = const AsyncData(null);
      return session;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<CashSession> closeSession({String? notes}) async {
    state = const AsyncLoading();
    try {
      final session = await ref
          .read(closeCashSessionUseCaseProvider)
          .call(notes: notes);
      state = const AsyncData(null);
      return session;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<void> registerManualMovement(CashManualMovementInput input) async {
    state = const AsyncLoading();
    try {
      await ref.read(cashRepositoryProvider).registerManualMovement(input);
      state = const AsyncData(null);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }
}
