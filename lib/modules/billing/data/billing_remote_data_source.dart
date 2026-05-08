import '../../../app/core/errors/app_exceptions.dart';
import '../../../app/core/entitlements/plan_entitlements.dart';
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

  Future<BillingInvoicesPage> fetchInvoices({
    String? status,
    DateTime? from,
    DateTime? to,
    int page = 1,
    int pageSize = 20,
  }) async {
    final response = await _runOwnerBillingRequest(
      () async => _apiClient.getJson(
        '/billing/invoices',
        options: ApiRequestOptions(
          headers: await _authorizedHeaders(),
          queryParameters: _withoutNulls(<String, Object?>{
            'status': status,
            'from': from?.toUtc().toIso8601String(),
            'to': to?.toUtc().toIso8601String(),
            'page': page,
            'pageSize': pageSize,
          }),
        ),
      ),
    );
    return BillingInvoicesPage.fromMap(response.data);
  }

  Future<BillingInvoice> fetchInvoice(String id) async {
    final response = await _runOwnerBillingRequest(
      () async => _apiClient.getJson(
        '/billing/invoices/${Uri.encodeComponent(id)}',
        options: ApiRequestOptions(headers: await _authorizedHeaders()),
      ),
    );
    return BillingInvoice.fromMap(response.data);
  }

  Future<BillingPaymentMethod> fetchPaymentMethod() async {
    final response = await _runOwnerBillingRequest(
      () async => _apiClient.getJson(
        '/billing/payment-method',
        options: ApiRequestOptions(headers: await _authorizedHeaders()),
      ),
    );
    return BillingPaymentMethod.fromMap(response.data);
  }

  Future<BillingActionResult> cancelSubscription({
    String effective = 'period_end',
  }) async {
    final response = await _runOwnerBillingRequest(
      () async => _apiClient.postJson(
        '/billing/cancel',
        body: <String, dynamic>{'effective': effective},
        options: ApiRequestOptions(headers: await _authorizedHeaders()),
      ),
    );
    return BillingActionResult.fromMap(response.data);
  }

  Future<BillingActionResult> resumeSubscription() async {
    final response = await _runOwnerBillingRequest(
      () async => _apiClient.postJson(
        '/billing/resume',
        options: ApiRequestOptions(headers: await _authorizedHeaders()),
      ),
    );
    return BillingActionResult.fromMap(response.data);
  }

  Future<BillingActionResult> changePlan(PlanKey plan) async {
    final response = await _runOwnerBillingRequest(
      () async => _apiClient.postJson(
        '/billing/change-plan',
        body: <String, dynamic>{'plan': plan.key},
        options: ApiRequestOptions(headers: await _authorizedHeaders()),
      ),
    );
    return BillingActionResult.fromMap(response.data);
  }

  Future<Map<String, String>> _authorizedHeaders() async {
    final token = await _tokenStorage.readAccessToken();
    if (token == null || token.trim().isEmpty) {
      throw const AuthenticationException(
        'Sessao remota nao encontrada. Entre novamente para gerenciar assinatura.',
      );
    }
    return <String, String>{'Authorization': 'Bearer ${token.trim()}'};
  }

  Map<String, Object?> _withoutNulls(Map<String, Object?> source) {
    return Map<String, Object?>.fromEntries(
      source.entries.where((entry) => entry.value != null),
    );
  }

  Future<T> _runOwnerBillingRequest<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on NetworkRequestException catch (error) {
      if (error.cause == 403) {
        throw const ValidationException(
          'Somente o dono/administrador pode gerenciar assinatura.',
        );
      }
      rethrow;
    }
  }
}
