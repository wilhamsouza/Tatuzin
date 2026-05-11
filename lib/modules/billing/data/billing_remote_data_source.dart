import '../../../app/core/errors/app_exceptions.dart';
import '../../../app/core/network/contracts/api_client_contract.dart';
import '../../../app/core/session/auth_token_storage.dart';
import '../domain/billing_models.dart';

class BillingRemoteDataSource {
  const BillingRemoteDataSource({
    required ApiClientContract apiClient,
    required AuthTokenStorage tokenStorage,
  }) : _apiClient = apiClient,
       _tokenStorage = tokenStorage;

  final ApiClientContract _apiClient;
  final AuthTokenStorage _tokenStorage;

  Future<List<BillingPlan>> fetchPlans() async {
    final response = await _apiClient.getJson('/billing/plans');
    final rawItems = response.data['items'];
    if (rawItems is! Iterable) {
      return const <BillingPlan>[];
    }
    return rawItems
        .whereType<Map>()
        .map((item) => BillingPlan.fromMap(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  Future<BillingStatus> fetchStatus() async {
    final response = await _apiClient.getJson(
      '/billing/status',
      options: ApiRequestOptions(headers: await _authorizedHeaders()),
    );
    return BillingStatus.fromMap(response.data);
  }

  Future<BillingSubscribeResult> subscribe({
    required String plan,
    String billingCycle = 'monthly',
  }) async {
    final response = await _apiClient.postJson(
      '/billing/subscribe',
      body: <String, dynamic>{'plan': plan, 'billingCycle': billingCycle},
      options: ApiRequestOptions(headers: await _authorizedHeaders()),
    );
    return BillingSubscribeResult.fromMap(response.data);
  }

  Future<BillingStatus> refresh() async {
    final response = await _apiClient.postJson(
      '/billing/refresh',
      options: ApiRequestOptions(headers: await _authorizedHeaders()),
    );
    return BillingStatus.fromMap(response.data);
  }

  Future<Map<String, String>> _authorizedHeaders() async {
    final token = await _tokenStorage.readAccessToken();
    if (token == null || token.trim().isEmpty) {
      throw const AuthenticationException(
        'Sua sessão expirou. Entre novamente para gerenciar a assinatura.',
      );
    }
    return <String, String>{'Authorization': 'Bearer ${token.trim()}'};
  }
}
