import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../config/owner_env.dart';
import '../models/owner_models.dart';
import '../network/owner_api_client.dart';
import '../network/owner_api_service.dart';
import 'owner_auth_controller.dart';
import 'owner_auth_storage.dart';

final ownerAuthStorageProvider = Provider<OwnerAuthStorage>((ref) {
  final storage = OwnerAuthStorage();
  ref.onDispose(storage.dispose);
  return storage;
});

final ownerHttpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final ownerApiClientProvider = Provider<OwnerApiClient>((ref) {
  return OwnerApiClient(
    baseUrl: OwnerEnv.apiBaseUrl,
    authStorage: ref.watch(ownerAuthStorageProvider),
    httpClient: ref.watch(ownerHttpClientProvider),
  );
});

final ownerApiServiceProvider = Provider<OwnerApiService>((ref) {
  return OwnerApiService(
    apiClient: ref.watch(ownerApiClientProvider),
    authStorage: ref.watch(ownerAuthStorageProvider),
  );
});

final ownerAuthControllerProvider = ChangeNotifierProvider<OwnerAuthController>(
  (ref) {
    return OwnerAuthController(
      apiService: ref.watch(ownerApiServiceProvider),
      authStorage: ref.watch(ownerAuthStorageProvider),
    );
  },
);

final ownerRefreshTickProvider = StateProvider<int>((ref) => 0);

final ownerCompanyProvider = FutureProvider<OwnerCompanySummary>((ref) async {
  ref.watch(ownerRefreshTickProvider);
  return ref.watch(ownerApiServiceProvider).getCompany();
});

final ownerDashboardProvider = FutureProvider<OwnerBusinessDashboard>((
  ref,
) async {
  ref.watch(ownerRefreshTickProvider);
  return ref.watch(ownerApiServiceProvider).getBusinessDashboard();
});

final ownerReportStartDateProvider = StateProvider<String?>((ref) {
  return _dateOnly(DateTime.now().subtract(const Duration(days: 29)));
});

final ownerReportEndDateProvider = StateProvider<String?>((ref) {
  return _dateOnly(DateTime.now());
});

final ownerSalesGroupByProvider = StateProvider<String>((ref) => 'day');

final ownerSalesSummaryProvider = FutureProvider<OwnerSalesSummary>((
  ref,
) async {
  ref.watch(ownerRefreshTickProvider);
  final startDate = ref.watch(ownerReportStartDateProvider);
  final endDate = ref.watch(ownerReportEndDateProvider);
  final groupBy = ref.watch(ownerSalesGroupByProvider);
  return ref
      .watch(ownerApiServiceProvider)
      .getSalesSummary(
        query: OwnerSalesSummaryQuery(
          startDate: startDate,
          endDate: endDate,
          groupBy: groupBy,
          page: 1,
          pageSize: 10,
          limit: 10,
        ),
      );
});

final ownerProductsReportProvider = FutureProvider<OwnerProductsReport>((
  ref,
) async {
  ref.watch(ownerRefreshTickProvider);
  final startDate = ref.watch(ownerReportStartDateProvider);
  final endDate = ref.watch(ownerReportEndDateProvider);
  return ref
      .watch(ownerApiServiceProvider)
      .getProductsReport(
        query: OwnerDateReportQuery(
          startDate: startDate,
          endDate: endDate,
          limit: 10,
        ),
      );
});

final ownerStockSummaryProvider = FutureProvider<OwnerStockSummary>((
  ref,
) async {
  ref.watch(ownerRefreshTickProvider);
  return ref
      .watch(ownerApiServiceProvider)
      .getStockSummary(query: const OwnerStockSummaryQuery(pageSize: 20));
});

final ownerCrmSummaryProvider = FutureProvider<OwnerCrmSummary>((ref) async {
  ref.watch(ownerRefreshTickProvider);
  return ref.watch(ownerApiServiceProvider).getCrmSummary();
});

final ownerCrmSearchProvider = StateProvider<String>((ref) => '');
final ownerCrmStatusProvider = StateProvider<String>((ref) => 'all');
final ownerCrmPageProvider = StateProvider<int>((ref) => 1);

final ownerCrmCustomersProvider = FutureProvider<OwnerCrmCustomerPage>((
  ref,
) async {
  ref.watch(ownerRefreshTickProvider);
  final search = ref.watch(ownerCrmSearchProvider);
  final status = ref.watch(ownerCrmStatusProvider);
  final page = ref.watch(ownerCrmPageProvider);
  return ref
      .watch(ownerApiServiceProvider)
      .getCrmCustomers(
        query: OwnerCrmCustomersQuery(
          search: search,
          status: status,
          page: page,
          pageSize: 20,
        ),
      );
});

final ownerReceivablesStatusProvider = StateProvider<String>((ref) => 'open');
final ownerReceivablesPageProvider = StateProvider<int>((ref) => 1);

final ownerReceivablesProvider = FutureProvider<OwnerReceivablesReport>((
  ref,
) async {
  ref.watch(ownerRefreshTickProvider);
  final status = ref.watch(ownerReceivablesStatusProvider);
  final page = ref.watch(ownerReceivablesPageProvider);
  return ref
      .watch(ownerApiServiceProvider)
      .getReceivables(
        query: OwnerReceivablesQuery(status: status, page: page, pageSize: 20),
      );
});

final ownerEmployeeReportsProvider = FutureProvider<OwnerEmployeeReports>((
  ref,
) async {
  ref.watch(ownerRefreshTickProvider);
  final startDate = ref.watch(ownerReportStartDateProvider);
  final endDate = ref.watch(ownerReportEndDateProvider);
  return ref
      .watch(ownerApiServiceProvider)
      .getEmployeeReports(
        query: OwnerEmployeesReportQuery(
          startDate: startDate,
          endDate: endDate,
          limit: 10,
        ),
      );
});

final ownerCommissionsProvider = FutureProvider<OwnerCommissionsSummary>((
  ref,
) async {
  ref.watch(ownerRefreshTickProvider);
  final startDate = ref.watch(ownerReportStartDateProvider);
  final endDate = ref.watch(ownerReportEndDateProvider);
  return ref
      .watch(ownerApiServiceProvider)
      .getCommissions(
        query: OwnerDateReportQuery(startDate: startDate, endDate: endDate),
      );
});

final ownerReportsCatalogProvider = FutureProvider<OwnerReportsCatalog>((
  ref,
) async {
  ref.watch(ownerRefreshTickProvider);
  return ref.watch(ownerApiServiceProvider).getReportsCatalog();
});

final ownerBillingStatusProvider = FutureProvider<OwnerBillingStatus>((
  ref,
) async {
  ref.watch(ownerRefreshTickProvider);
  return ref.watch(ownerApiServiceProvider).getBillingStatus();
});

final ownerInvoiceStatusFilterProvider = StateProvider<String?>((ref) => null);
final ownerInvoicePageProvider = StateProvider<int>((ref) => 1);

final ownerBillingInvoicesProvider = FutureProvider<OwnerInvoicesPage>((
  ref,
) async {
  ref.watch(ownerRefreshTickProvider);
  final status = ref.watch(ownerInvoiceStatusFilterProvider);
  final page = ref.watch(ownerInvoicePageProvider);
  return ref
      .watch(ownerApiServiceProvider)
      .getBillingInvoices(
        query: OwnerInvoicesQuery(page: page, pageSize: 10, status: status),
      );
});

final ownerEmployeesProvider = FutureProvider<OwnerEmployeesOverview>((
  ref,
) async {
  ref.watch(ownerRefreshTickProvider);
  return ref.watch(ownerApiServiceProvider).getEmployees();
});

final ownerReceiptSettingsProvider = FutureProvider<OwnerReceiptSettings>((
  ref,
) async {
  ref.watch(ownerRefreshTickProvider);
  return ref.watch(ownerApiServiceProvider).getReceiptSettings();
});

final ownerDevicesProvider = FutureProvider<OwnerDevicesResult>((ref) async {
  ref.watch(ownerRefreshTickProvider);
  return ref.watch(ownerApiServiceProvider).getDevices();
});

final ownerSyncStatusProvider = FutureProvider<OwnerSyncStatus>((ref) async {
  ref.watch(ownerRefreshTickProvider);
  return ref.watch(ownerApiServiceProvider).getSyncStatus();
});

String _dateOnly(DateTime value) {
  final local = value.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}
