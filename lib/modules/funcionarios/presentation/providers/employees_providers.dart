import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/database/app_database.dart';
import '../../../../app/core/entitlements/plan_entitlements.dart';
import '../../../../app/core/errors/app_exceptions.dart';
import '../../../../app/core/network/network_providers.dart';
import '../../../../app/core/providers/app_data_refresh_provider.dart';
import '../../../../app/core/session/auth_token_storage.dart';
import '../../../../app/core/session/session_provider.dart';
import '../../../../app/core/sync/sqlite_sync_metadata_repository.dart';
import '../../../../app/core/sync/sync_feature_keys.dart';
import '../../data/employees_remote_data_source.dart';
import '../../domain/employee_models.dart';

final employeesRemoteDataSourceProvider = Provider<EmployeesRemoteDataSource>((
  ref,
) {
  return EmployeesRemoteDataSource(
    apiClient: ref.watch(realApiClientProvider),
    tokenStorage: ref.watch(authTokenStorageProvider),
  );
});

final employeeSearchQueryProvider = StateProvider<String>((ref) => '');

final employeeStatusFilterProvider = StateProvider<EmployeeStatus?>(
  (ref) => null,
);

final employeeRoleFilterProvider = StateProvider<EmployeeRole?>((ref) => null);

final employeesPageNumberProvider = StateProvider<int>((ref) => 1);

final employeeActivityPeriodProvider = StateProvider<EmployeeActivityPeriod>(
  (ref) => EmployeeActivityPeriod.today(),
);

final canManageEmployeesProvider = Provider<bool>((ref) {
  final session = ref.watch(appSessionProvider);
  if (!session.hasFeature(FeatureKey.employees)) {
    return false;
  }
  return session.hasEffectivePermission(EmployeePermission.employeesManage.key);
});

final canViewEmployeeActivityProvider = Provider<bool>((ref) {
  final session = ref.watch(appSessionProvider);
  if (!session.hasFeature(FeatureKey.employees)) {
    return false;
  }
  return session.isCompanyOwner ||
      session.canAccessPermission(EmployeePermission.employeesManage.key) ||
      session.canAccessPermission(EmployeePermission.reportsAdvanced.key);
});

final canViewEmployeeCommissionsProvider = Provider<bool>((ref) {
  final session = ref.watch(appSessionProvider);
  if (!session.hasFeature(FeatureKey.employees)) {
    return false;
  }
  return session.isCompanyOwner ||
      session.canAccessPermission(EmployeePermission.employeesManage.key) ||
      session.canAccessPermission(EmployeePermission.reportsAdvanced.key);
});

final currentEmployeeDisabledProvider = Provider<bool>((ref) {
  return ref.watch(appSessionProvider).employee?.isDisabled ?? false;
});

final employeesListProvider = FutureProvider.autoDispose<EmployeesPageResult>((
  ref,
) async {
  ref.watch(appDataRefreshProvider);
  final search = ref.watch(employeeSearchQueryProvider);
  final status = ref.watch(employeeStatusFilterProvider);
  final role = ref.watch(employeeRoleFilterProvider);
  final page = ref.watch(employeesPageNumberProvider);
  return ref
      .watch(employeesRemoteDataSourceProvider)
      .getEmployees(search: search, status: status, role: role, page: page);
});

final employeeDetailProvider = FutureProvider.autoDispose
    .family<EmployeeProfile, String>((ref, id) async {
      ref.watch(appDataRefreshProvider);
      return ref.watch(employeesRemoteDataSourceProvider).getEmployee(id);
    });

final employeeActivitySummaryProvider =
    FutureProvider.autoDispose<EmployeeActivitySummary>((ref) async {
      ref.watch(appDataRefreshProvider);
      final period = ref.watch(employeeActivityPeriodProvider);
      return ref
          .watch(employeesRemoteDataSourceProvider)
          .getEmployeeActivitySummary(period: period);
    });

final employeeActivityDetailProvider = FutureProvider.autoDispose
    .family<EmployeeActivityDetail, String>((ref, id) async {
      ref.watch(appDataRefreshProvider);
      final period = ref.watch(employeeActivityPeriodProvider);
      return ref
          .watch(employeesRemoteDataSourceProvider)
          .getEmployeeActivityDetail(id, period: period);
    });

final employeeCommissionSettingsProvider = FutureProvider.autoDispose
    .family<EmployeeCommissionSettings, String>((ref, id) async {
      ref.watch(appDataRefreshProvider);
      return ref
          .watch(employeesRemoteDataSourceProvider)
          .getEmployeeCommissionSettings(id);
    });

final employeeCommissionsSummaryProvider =
    FutureProvider.autoDispose<EmployeeCommissionsSummary>((ref) async {
      ref.watch(appDataRefreshProvider);
      final period = ref.watch(employeeActivityPeriodProvider);
      return ref
          .watch(employeesRemoteDataSourceProvider)
          .getEmployeeCommissionsSummary(period: period);
    });

final employeeCommissionDetailProvider = FutureProvider.autoDispose
    .family<EmployeeCommissionDetail, String>((ref, id) async {
      ref.watch(appDataRefreshProvider);
      final period = ref.watch(employeeActivityPeriodProvider);
      return ref
          .watch(employeesRemoteDataSourceProvider)
          .getEmployeeCommissionDetail(id, period: period);
    });

final employeeActivitySaleLocalIdProvider = FutureProvider.autoDispose
    .family<int?, String>((ref, remoteSaleId) async {
      return _resolveLocalIdByRemoteId(
        ref,
        featureKey: SyncFeatureKeys.sales,
        remoteId: remoteSaleId,
      );
    });

final employeeActivityCashSessionLocalIdProvider = FutureProvider.autoDispose
    .family<int?, String>((ref, remoteCashSessionId) async {
      return _resolveLocalIdByRemoteId(
        ref,
        featureKey: SyncFeatureKeys.cashSessions,
        remoteId: remoteCashSessionId,
      );
    });

final employeeActionControllerProvider =
    AsyncNotifierProvider<EmployeeActionController, void>(
      EmployeeActionController.new,
    );

class EmployeeActionController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<EmployeeProfile> create(EmployeeMutationInput input) {
    return _runMutation(
      () => ref.read(employeesRemoteDataSourceProvider).createEmployee(input),
    );
  }

  Future<EmployeeProfile> updateEmployee(
    String id,
    EmployeeMutationInput input,
  ) {
    return _runMutation(
      () =>
          ref.read(employeesRemoteDataSourceProvider).updateEmployee(id, input),
      detailId: id,
    );
  }

  Future<void> delete(String id) {
    return _runVoidMutation(
      () => ref.read(employeesRemoteDataSourceProvider).deleteEmployee(id),
      detailId: id,
    );
  }

  Future<EmployeeActionResult> invite(String id) {
    return _runMutation(
      () => ref.read(employeesRemoteDataSourceProvider).inviteEmployee(id),
      detailId: id,
    );
  }

  Future<EmployeeTemporaryPasswordResult> generateTemporaryPassword(String id) {
    return _runMutation(
      () => ref
          .read(employeesRemoteDataSourceProvider)
          .generateTemporaryPassword(id),
      detailId: id,
    );
  }

  Future<EmployeeProfile> disable(String id) {
    return _runMutation(
      () => ref.read(employeesRemoteDataSourceProvider).disableEmployee(id),
      detailId: id,
    );
  }

  Future<EmployeeProfile> enable(String id) {
    return _runMutation(
      () => ref.read(employeesRemoteDataSourceProvider).enableEmployee(id),
      detailId: id,
    );
  }

  Future<EmployeeCommissionSettings> updateCommissionSettings(
    String id,
    EmployeeCommissionSettings settings,
  ) {
    return _runMutation(
      () => ref
          .read(employeesRemoteDataSourceProvider)
          .updateEmployeeCommissionSettings(id, settings),
      detailId: id,
    );
  }

  Future<T> _runMutation<T>(
    Future<T> Function() mutation, {
    String? detailId,
  }) async {
    state = const AsyncLoading();
    try {
      _assertCanManage();
      final result = await mutation();
      _invalidate(detailId);
      state = const AsyncData(null);
      return result;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<void> _runVoidMutation(
    Future<void> Function() mutation, {
    String? detailId,
  }) async {
    await _runMutation<void>(mutation, detailId: detailId);
  }

  void _assertCanManage() {
    if (!ref.read(canManageEmployeesProvider)) {
      throw const ValidationException(
        'Você não tem permissão para gerenciar funcionários.',
      );
    }
  }

  void _invalidate(String? detailId) {
    ref.read(appDataRefreshProvider.notifier).state++;
    ref.invalidate(employeesListProvider);
    if (detailId != null) {
      ref.invalidate(employeeDetailProvider(detailId));
      ref.invalidate(employeeCommissionSettingsProvider(detailId));
      ref.invalidate(employeeCommissionDetailProvider(detailId));
    }
    ref.invalidate(employeeCommissionsSummaryProvider);
    ref.invalidate(employeeActivitySummaryProvider);
  }
}

Future<int?> _resolveLocalIdByRemoteId(
  Ref ref, {
  required String featureKey,
  required String remoteId,
}) async {
  final trimmed = remoteId.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  final numericFallback = int.tryParse(trimmed);
  final database = await ref.read(appDatabaseProvider).database;
  final metadata = await SqliteSyncMetadataRepository(
    ref.read(appDatabaseProvider),
  ).findByRemoteId(database, featureKey: featureKey, remoteId: trimmed);
  return metadata?.identity.localId ?? numericFallback;
}
