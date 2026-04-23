import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/admin_analytics_models.dart';
import '../models/admin_crm_models.dart';
import '../models/admin_hybrid_governance_models.dart';
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

final adminAuthControllerProvider = ChangeNotifierProvider<AdminAuthController>(
  (ref) {
    return AdminAuthController(
      apiService: ref.watch(adminApiServiceProvider),
      authStorage: ref.watch(adminAuthStorageProvider),
    );
  },
);

final adminRefreshTickProvider = StateProvider<int>((ref) => 0);

final adminDashboardProvider = FutureProvider<AdminDashboardSnapshot>((
  ref,
) async {
  ref.watch(adminRefreshTickProvider);
  return ref.watch(adminApiServiceProvider).fetchDashboard();
});

final adminCompaniesProvider =
    FutureProvider.family<
      AdminPaginatedResult<AdminCompanySummary>,
      AdminCompaniesQuery
    >((ref, query) async {
      ref.watch(adminRefreshTickProvider);
      return ref.watch(adminApiServiceProvider).fetchCompanies(query: query);
    });

final adminCompanyDetailProvider =
    FutureProvider.family<AdminCompanyDetail, String>((ref, companyId) async {
      ref.watch(adminRefreshTickProvider);
      return ref.watch(adminApiServiceProvider).fetchCompanyDetail(companyId);
    });

final adminLicensesProvider =
    FutureProvider.family<
      AdminPaginatedResult<AdminLicenseSnapshot>,
      AdminLicensesQuery
    >((ref, query) async {
      ref.watch(adminRefreshTickProvider);
      return ref.watch(adminApiServiceProvider).fetchLicenses(query: query);
    });

final adminAuditSummaryProvider =
    FutureProvider.family<AdminAuditSummary, AdminAuditQuery>((
      ref,
      query,
    ) async {
      ref.watch(adminRefreshTickProvider);
      return ref.watch(adminApiServiceProvider).fetchAuditSummary(query: query);
    });

final adminSyncSummaryProvider =
    FutureProvider.family<AdminSyncSummary, AdminSyncQuery>((ref, query) async {
      ref.watch(adminRefreshTickProvider);
      return ref.watch(adminApiServiceProvider).fetchSyncSummary(query: query);
    });

final adminSyncOperationalSummaryProvider =
    FutureProvider.family<
      AdminSyncOperationalSummary,
      AdminSyncOperationalQuery
    >((ref, query) async {
      ref.watch(adminRefreshTickProvider);
      return ref
          .watch(adminApiServiceProvider)
          .fetchSyncOperationalSummary(query: query);
    });

final adminManagementCompanyOptionsProvider =
    FutureProvider<List<AdminCompanySummary>>((ref) async {
      ref.watch(adminRefreshTickProvider);
      final response = await ref
          .watch(adminApiServiceProvider)
          .fetchCompanies(
            query: const AdminCompaniesQuery(
              page: 1,
              pageSize: 100,
              sortBy: 'name',
              sortDirection: 'asc',
            ),
          );
      return response.items;
    });

final adminManagementDashboardProvider =
    FutureProvider.family<
      AdminManagementDashboardSnapshot,
      AdminManagementScopeQuery
    >((ref, query) async {
      ref.watch(adminRefreshTickProvider);
      return ref
          .watch(adminApiServiceProvider)
          .fetchManagementDashboard(query: query);
    });

final adminManagementReportsBundleProvider =
    FutureProvider.family<
      AdminManagementReportsBundle,
      AdminManagementScopeQuery
    >((ref, query) async {
      ref.watch(adminRefreshTickProvider);
      final api = ref.watch(adminApiServiceProvider);
      final results = await Future.wait<dynamic>([
        api.fetchSalesByDayReport(query: query),
        api.fetchSalesByProductReport(query: query),
        api.fetchSalesByCustomerReport(query: query),
        api.fetchCashConsolidatedReport(query: query),
        api.fetchFinancialSummaryReport(query: query),
      ]);

      return AdminManagementReportsBundle(
        salesByDay: results[0] as AdminSalesByDayReport,
        salesByProduct: results[1] as AdminSalesByProductReport,
        salesByCustomer: results[2] as AdminSalesByCustomerReport,
        cashConsolidated: results[3] as AdminCashConsolidatedReport,
        financialSummary: results[4] as AdminFinancialSummaryReport,
      );
    });

final adminCrmCustomersProvider =
    FutureProvider.family<
      AdminPaginatedResult<AdminCrmCustomerSummary>,
      AdminCrmCustomersQuery
    >((ref, query) async {
      ref.watch(adminRefreshTickProvider);
      return ref.watch(adminApiServiceProvider).fetchCrmCustomers(query: query);
    });

final adminCrmCustomerDetailProvider =
    FutureProvider.family<AdminCrmCustomerDetail, AdminCrmCustomerKey>((
      ref,
      key,
    ) async {
      ref.watch(adminRefreshTickProvider);
      return ref
          .watch(adminApiServiceProvider)
          .fetchCrmCustomerDetail(key: key);
    });

final adminCrmCustomerTimelineProvider =
    FutureProvider.family<
      AdminPaginatedResult<AdminCrmTimelineEvent>,
      AdminCrmCustomerTimelineQuery
    >((ref, query) async {
      ref.watch(adminRefreshTickProvider);
      return ref
          .watch(adminApiServiceProvider)
          .fetchCrmCustomerTimeline(query: query);
    });

final adminHybridGovernanceOverviewProvider =
    FutureProvider.family<AdminHybridGovernanceOverview, String>((
      ref,
      companyId,
    ) async {
      ref.watch(adminRefreshTickProvider);
      return ref
          .watch(adminApiServiceProvider)
          .fetchHybridGovernanceOverview(
            query: AdminHybridGovernanceQuery(companyId: companyId),
          );
    });
