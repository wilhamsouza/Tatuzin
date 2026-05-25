import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/admin_access_models.dart';
import '../models/admin_analytics_models.dart';
import '../models/admin_billing_models.dart';
import '../models/admin_crm_models.dart';
import '../models/admin_hybrid_governance_models.dart';
import '../../config/admin_env.dart';
import '../models/admin_models.dart';
import '../models/admin_plan_models.dart';
import '../models/admin_sync_center_models.dart';
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

final adminPlansOverviewProvider = FutureProvider<AdminPlansOverview>((
  ref,
) async {
  ref.watch(adminRefreshTickProvider);
  return ref.watch(adminApiServiceProvider).fetchPlansOverview();
});

final adminCompanyAccessSummaryProvider =
    FutureProvider.family<AdminCompanyAccessSummary, String>((
      ref,
      companyId,
    ) async {
      ref.watch(adminRefreshTickProvider);
      return ref
          .watch(adminApiServiceProvider)
          .fetchCompanyAccessSummary(companyId);
    });

final adminCompanySyncHealthProvider =
    FutureProvider.family<AdminCompanySyncHealth, String>((
      ref,
      companyId,
    ) async {
      ref.watch(adminRefreshTickProvider);
      return ref
          .watch(adminApiServiceProvider)
          .fetchCompanySyncHealth(companyId);
    });

final adminCompanySyncDevicesProvider =
    FutureProvider.family<List<AdminCompanySyncDevice>, String>((
      ref,
      companyId,
    ) async {
      ref.watch(adminRefreshTickProvider);
      return ref
          .watch(adminApiServiceProvider)
          .fetchCompanySyncDevices(companyId);
    });

final adminCompanySyncEventsProvider =
    FutureProvider.family<
      AdminPaginatedResult<AdminSyncEventDiagnostic>,
      AdminCompanySyncEventsQuery
    >((ref, query) async {
      ref.watch(adminRefreshTickProvider);
      return ref
          .watch(adminApiServiceProvider)
          .fetchCompanySyncEvents(query: query);
    });

final adminCompanySyncConflictsProvider =
    FutureProvider.family<
      AdminPaginatedResult<AdminSyncConflictDiagnostic>,
      AdminCompanySyncConflictsQuery
    >((ref, query) async {
      ref.watch(adminRefreshTickProvider);
      return ref
          .watch(adminApiServiceProvider)
          .fetchCompanySyncConflicts(query: query);
    });

final adminCompanySyncIncidentsProvider =
    FutureProvider.family<
      AdminPaginatedResult<AdminSyncIncidentDiagnostic>,
      AdminCompanySyncIncidentsQuery
    >((ref, query) async {
      ref.watch(adminRefreshTickProvider);
      return ref
          .watch(adminApiServiceProvider)
          .fetchCompanySyncIncidents(query: query);
    });

final adminLicensesProvider =
    FutureProvider.family<
      AdminPaginatedResult<AdminLicenseSnapshot>,
      AdminLicensesQuery
    >((ref, query) async {
      ref.watch(adminRefreshTickProvider);
      return ref.watch(adminApiServiceProvider).fetchLicenses(query: query);
    });

final adminBillingCompaniesProvider =
    FutureProvider.family<
      AdminPaginatedResult<AdminBillingCompanySummary>,
      AdminBillingCompaniesQuery
    >((ref, query) async {
      ref.watch(adminRefreshTickProvider);
      return ref
          .watch(adminApiServiceProvider)
          .fetchBillingCompanies(query: query);
    });

final adminBillingCompanyStatusProvider =
    FutureProvider.family<AdminBillingCompanyStatus, String>((
      ref,
      companyId,
    ) async {
      ref.watch(adminRefreshTickProvider);
      return ref
          .watch(adminApiServiceProvider)
          .fetchBillingCompanyStatus(companyId);
    });

final adminBillingEventsProvider =
    FutureProvider.family<
      AdminPaginatedResult<AdminBillingEvent>,
      AdminBillingListQuery
    >((ref, query) async {
      ref.watch(adminRefreshTickProvider);
      return ref
          .watch(adminApiServiceProvider)
          .fetchBillingEvents(query: query);
    });

final adminBillingCheckoutSessionsProvider =
    FutureProvider.family<
      AdminPaginatedResult<AdminBillingCheckoutSession>,
      AdminBillingListQuery
    >((ref, query) async {
      ref.watch(adminRefreshTickProvider);
      return ref
          .watch(adminApiServiceProvider)
          .fetchBillingCheckoutSessions(query: query);
    });

final adminBillingAuditLogsProvider =
    FutureProvider.family<
      AdminPaginatedResult<AdminBillingAuditLog>,
      AdminBillingListQuery
    >((ref, query) async {
      ref.watch(adminRefreshTickProvider);
      return ref
          .watch(adminApiServiceProvider)
          .fetchBillingAuditLogs(query: query);
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

final adminSyncCenterCompaniesProvider =
    FutureProvider.family<
      AdminPaginatedResult<AdminSyncCenterCompany>,
      AdminSyncCenterCompaniesQuery
    >((ref, query) async {
      ref.watch(adminRefreshTickProvider);
      return ref
          .watch(adminApiServiceProvider)
          .fetchSyncCenterCompanies(query: query);
    });

final adminSyncCenterCompanySummaryProvider =
    FutureProvider.family<AdminSyncCenterCompanySummary, String>((
      ref,
      companyId,
    ) async {
      ref.watch(adminRefreshTickProvider);
      return ref
          .watch(adminApiServiceProvider)
          .fetchSyncCenterCompanySummary(companyId);
    });

final adminSyncCenterEventsProvider =
    FutureProvider.family<
      AdminPaginatedResult<AdminSyncCenterEvent>,
      AdminSyncCenterEventsQuery
    >((ref, query) async {
      ref.watch(adminRefreshTickProvider);
      return ref
          .watch(adminApiServiceProvider)
          .fetchSyncCenterEvents(query: query);
    });

final adminSyncCenterConflictsProvider =
    FutureProvider.family<
      AdminPaginatedResult<AdminSyncCenterConflict>,
      AdminSyncCenterConflictsQuery
    >((ref, query) async {
      ref.watch(adminRefreshTickProvider);
      return ref
          .watch(adminApiServiceProvider)
          .fetchSyncCenterConflicts(query: query);
    });

final adminSyncSupportDevicesProvider =
    FutureProvider.family<List<AdminSyncSupportDevice>, String>((
      ref,
      companyId,
    ) async {
      ref.watch(adminRefreshTickProvider);
      return ref
          .watch(adminApiServiceProvider)
          .fetchSyncSupportDevices(companyId: companyId);
    });

final adminSyncSupportDeviceDetailProvider =
    FutureProvider.family<
      AdminSyncSupportDeviceDetail,
      AdminSyncCenterDetailKey
    >((ref, key) async {
      ref.watch(adminRefreshTickProvider);
      return ref
          .watch(adminApiServiceProvider)
          .fetchSyncSupportDeviceDetail(
            companyId: key.companyId,
            deviceId: key.targetId,
          );
    });

final adminSyncCenterEventDetailProvider =
    FutureProvider.family<AdminSyncCenterEventDetail, AdminSyncCenterDetailKey>(
      (ref, key) async {
        ref.watch(adminRefreshTickProvider);
        return ref
            .watch(adminApiServiceProvider)
            .fetchSyncCenterEventDetail(
              companyId: key.companyId,
              eventId: key.targetId,
            );
      },
    );

final adminSyncCenterConflictDetailProvider =
    FutureProvider.family<
      AdminSyncCenterConflictDetail,
      AdminSyncCenterDetailKey
    >((ref, key) async {
      ref.watch(adminRefreshTickProvider);
      return ref
          .watch(adminApiServiceProvider)
          .fetchSyncCenterConflictDetail(
            companyId: key.companyId,
            conflictId: key.targetId,
          );
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
