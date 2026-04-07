import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/admin_env.dart';
import '../models/admin_models.dart';
import '../network/admin_api_client.dart';
import '../network/admin_api_service.dart';
import 'admin_auth_controller.dart';
import 'admin_auth_storage.dart';

final adminAuthStorageProvider = Provider<AdminAuthStorage>((ref) {
  return AdminAuthStorage();
});

final adminApiClientProvider = Provider<AdminApiClient>((ref) {
  return AdminApiClient(
    baseUrl: AdminEnv.apiBaseUrl,
    authStorage: ref.watch(adminAuthStorageProvider),
  );
});

final adminApiServiceProvider = Provider<AdminApiService>((ref) {
  return AdminApiService(
    apiClient: ref.watch(adminApiClientProvider),
    authStorage: ref.watch(adminAuthStorageProvider),
  );
});

final adminAuthControllerProvider =
    ChangeNotifierProvider<AdminAuthController>((ref) {
      return AdminAuthController(
        apiService: ref.watch(adminApiServiceProvider),
        authStorage: ref.watch(adminAuthStorageProvider),
      );
    });

final adminRefreshTickProvider = StateProvider<int>((ref) => 0);

final adminDashboardProvider = FutureProvider<AdminDashboardSnapshot>((ref) async {
  ref.watch(adminRefreshTickProvider);
  return ref.watch(adminApiServiceProvider).fetchDashboard();
});

final adminCompaniesProvider = FutureProvider<List<AdminCompanySummary>>((
  ref,
) async {
  ref.watch(adminRefreshTickProvider);
  return ref.watch(adminApiServiceProvider).fetchCompanies();
});

final adminCompanyDetailProvider =
    FutureProvider.family<AdminCompanyDetail, String>((ref, companyId) async {
      ref.watch(adminRefreshTickProvider);
      return ref.watch(adminApiServiceProvider).fetchCompanyDetail(companyId);
    });

final adminLicensesProvider = FutureProvider<List<AdminLicenseSnapshot>>((ref) async {
  ref.watch(adminRefreshTickProvider);
  return ref.watch(adminApiServiceProvider).fetchLicenses();
});

final adminAuditSummaryProvider = FutureProvider<AdminAuditSummary>((ref) async {
  ref.watch(adminRefreshTickProvider);
  return ref.watch(adminApiServiceProvider).fetchAuditSummary();
});

final adminSyncSummaryProvider = FutureProvider<AdminSyncSummary>((ref) async {
  ref.watch(adminRefreshTickProvider);
  return ref.watch(adminApiServiceProvider).fetchSyncSummary();
});
