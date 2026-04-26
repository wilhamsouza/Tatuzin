import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/app_context/app_operational_context.dart';
import '../../../../app/core/app_context/data_access_policy.dart';
import '../../../../app/core/config/app_environment.dart';
import '../../../../app/core/database/app_database.dart';
import '../../../../app/core/network/network_providers.dart';
import '../../../../app/core/providers/app_data_refresh_provider.dart';
import '../../../../app/core/providers/provider_guard.dart';
import '../../../../app/core/session/auth_token_storage.dart';
import '../../../../app/core/session/session_provider.dart';
import '../../data/cash_event_sync_processor.dart';
import '../../data/datasources/cash_remote_datasource.dart';
import '../../data/real/real_cash_remote_datasource.dart';
import '../../data/sqlite_cash_repository.dart';
import '../../domain/entities/cash_enums.dart';
import '../../domain/entities/cash_manual_movement_input.dart';
import '../../domain/entities/cash_movement.dart';
import '../../domain/entities/cash_session.dart';
import '../../domain/entities/cash_session_detail.dart';
import '../../domain/repositories/cash_repository.dart';
import '../../domain/usecases/close_cash_session_use_case.dart';
import '../../domain/usecases/open_cash_session_use_case.dart';

final localCashRepositoryProvider = Provider<SqliteCashRepository>((ref) {
  return SqliteCashRepository(
    ref.watch(appDatabaseProvider),
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

final currentCashOperatorNameProvider = Provider<String>((ref) {
  return ref.watch(appOperationalContextProvider).session.user.displayName;
});

final currentCashSessionProvider = FutureProvider<CashSession?>((ref) async {
  ref.watch(sessionRuntimeKeyProvider);
  ref.watch(appDataRefreshProvider);
  return runProviderGuarded(
    'currentCashSessionProvider',
    () => ref.watch(cashRepositoryProvider).getCurrentSession(),
    timeout: localProviderTimeout,
  );
});

final currentCashMovementsProvider = FutureProvider<List<CashMovement>>((
  ref,
) async {
  ref.watch(sessionRuntimeKeyProvider);
  ref.watch(appDataRefreshProvider);
  return runProviderGuarded(
    'currentCashMovementsProvider',
    () => ref.watch(cashRepositoryProvider).listCurrentSessionMovements(),
    timeout: localProviderTimeout,
  );
});

final cashSessionHistoryProvider = FutureProvider<List<CashSession>>((
  ref,
) async {
  ref.watch(sessionRuntimeKeyProvider);
  ref.watch(appDataRefreshProvider);
  return runProviderGuarded(
    'cashSessionHistoryProvider',
    () => ref.watch(cashRepositoryProvider).listSessions(),
    timeout: localProviderTimeout,
  );
});

final cashSessionDetailProvider = FutureProvider.family<CashSessionDetail, int>(
  (ref, sessionId) async {
    ref.watch(sessionRuntimeKeyProvider);
    ref.watch(appDataRefreshProvider);
    return runProviderGuarded(
      'cashSessionDetailProvider',
      () => ref.watch(cashRepositoryProvider).fetchSessionDetail(sessionId),
      timeout: localProviderTimeout,
    );
  },
);

final openCashSessionUseCaseProvider = Provider<OpenCashSessionUseCase>((ref) {
  return OpenCashSessionUseCase(ref.read(cashRepositoryProvider));
});

final closeCashSessionUseCaseProvider = Provider<CloseCashSessionUseCase>((
  ref,
) {
  return CloseCashSessionUseCase(ref.read(cashRepositoryProvider));
});

enum CashMovementFilter { all, sales, fiado, sangria, supply }

extension CashMovementFilterX on CashMovementFilter {
  String get label {
    switch (this) {
      case CashMovementFilter.all:
        return 'Todos';
      case CashMovementFilter.sales:
        return 'Vendas';
      case CashMovementFilter.fiado:
        return 'Fiado';
      case CashMovementFilter.sangria:
        return 'Sangria';
      case CashMovementFilter.supply:
        return 'Suprimento';
    }
  }
}

final cashMovementFilterProvider = StateProvider<CashMovementFilter>(
  (ref) => CashMovementFilter.all,
);

final cashMovementVisibleCountProvider = StateProvider<int>((ref) => 10);

final cashLastUpdatedAtProvider = StateProvider<DateTime?>((ref) => null);

final filteredCashMovementsProvider = Provider<List<CashMovement>>((ref) {
  final movements = ref.watch(currentCashMovementsProvider).value ?? const [];
  final filter = ref.watch(cashMovementFilterProvider);

  bool matches(CashMovement movement) {
    switch (filter) {
      case CashMovementFilter.all:
        return true;
      case CashMovementFilter.sales:
        return movement.type == CashMovementType.sale ||
            (movement.type == CashMovementType.cancellation &&
                movement.referenceType == 'venda');
      case CashMovementFilter.fiado:
        return movement.type == CashMovementType.fiadoReceipt ||
            (movement.type == CashMovementType.cancellation &&
                movement.referenceType == 'fiado');
      case CashMovementFilter.sangria:
        return movement.type == CashMovementType.sangria;
      case CashMovementFilter.supply:
        return movement.type == CashMovementType.supply;
    }
  }

  return movements.where(matches).toList(growable: false);
});

final visibleCashMovementsProvider = Provider<List<CashMovement>>((ref) {
  final filtered = ref.watch(filteredCashMovementsProvider);
  final visibleCount = ref.watch(cashMovementVisibleCountProvider);
  return filtered.take(visibleCount).toList(growable: false);
});

final cashMovementCountsProvider = Provider<Map<CashMovementFilter, int>>((
  ref,
) {
  final movements = ref.watch(currentCashMovementsProvider).value ?? const [];

  int countWhere(bool Function(CashMovement movement) test) {
    return movements.where(test).length;
  }

  return {
    CashMovementFilter.all: movements.length,
    CashMovementFilter.sales: countWhere(
      (movement) =>
          movement.type == CashMovementType.sale ||
          (movement.type == CashMovementType.cancellation &&
              movement.referenceType == 'venda'),
    ),
    CashMovementFilter.fiado: countWhere(
      (movement) =>
          movement.type == CashMovementType.fiadoReceipt ||
          (movement.type == CashMovementType.cancellation &&
              movement.referenceType == 'fiado'),
    ),
    CashMovementFilter.sangria: countWhere(
      (movement) => movement.type == CashMovementType.sangria,
    ),
    CashMovementFilter.supply: countWhere(
      (movement) => movement.type == CashMovementType.supply,
    ),
  };
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
      _notifyCashChanged();
      state = const AsyncData(null);
      return session;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<CashSession> confirmAutoOpenedSession({
    required int initialFloatCents,
  }) async {
    state = const AsyncLoading();
    try {
      final session = await ref
          .read(cashRepositoryProvider)
          .confirmAutoOpenedSession(initialFloatCents: initialFloatCents);
      _notifyCashChanged();
      state = const AsyncData(null);
      return session;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<CashSession> closeSession({
    required int countedBalanceCents,
    String? notes,
  }) async {
    state = const AsyncLoading();
    try {
      final session = await ref
          .read(closeCashSessionUseCaseProvider)
          .call(countedBalanceCents: countedBalanceCents, notes: notes);
      _notifyCashChanged();
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
      _notifyCashChanged();
      state = const AsyncData(null);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  void _notifyCashChanged() {
    ref.read(appDataRefreshProvider.notifier).state++;
    ref.read(cashLastUpdatedAtProvider.notifier).state = DateTime.now();
    ref.read(cashMovementVisibleCountProvider.notifier).state = 10;
  }
}
