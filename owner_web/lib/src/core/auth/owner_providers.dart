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

final ownerDashboardProvider = FutureProvider<OwnerDashboard>((ref) async {
  ref.watch(ownerRefreshTickProvider);
  return ref.watch(ownerApiServiceProvider).getDashboard();
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

final ownerEmployeesProvider = FutureProvider<OwnerEmployeesPlaceholder>((
  ref,
) async {
  ref.watch(ownerRefreshTickProvider);
  return ref.watch(ownerApiServiceProvider).getEmployees();
});

final ownerDevicesProvider = FutureProvider<OwnerDevicesResult>((ref) async {
  ref.watch(ownerRefreshTickProvider);
  return ref.watch(ownerApiServiceProvider).getDevices();
});
