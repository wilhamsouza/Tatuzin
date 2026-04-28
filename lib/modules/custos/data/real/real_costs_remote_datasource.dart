import '../../../../app/core/errors/app_exceptions.dart';
import '../../../../app/core/network/contracts/api_client_contract.dart';
import '../../../../app/core/session/auth_token_storage.dart';
import '../../domain/entities/cost_status.dart';
import '../../domain/entities/cost_type.dart';
import '../../domain/repositories/cost_repository.dart';
import '../datasources/costs_remote_datasource.dart';
import '../models/remote_cost_record.dart';

class RealCostsRemoteDatasource implements CostsRemoteDatasource {
  const RealCostsRemoteDatasource({
    required ApiClientContract apiClient,
    required AuthTokenStorage tokenStorage,
  }) : _apiClient = apiClient,
       _tokenStorage = tokenStorage;

  final ApiClientContract _apiClient;
  final AuthTokenStorage _tokenStorage;

  @override
  Future<RemoteCostRecord> cancel({
    required String remoteId,
    String? notes,
  }) async {
    final response = await _apiClient.postJson(
      '/costs/$remoteId/cancel',
      body: <String, dynamic>{'notes': notes},
      options: await _authorizedOptions(),
    );
    return _readCost(response.data);
  }

  @override
  Future<RemoteCostRecord> create(RemoteCostRecord record) async {
    final response = await _apiClient.postJson(
      '/costs',
      body: record.toCreateBody(),
      options: await _authorizedOptions(),
    );
    return _readCost(response.data);
  }

  @override
  Future<RemoteCostOverview> fetchSummary() async {
    final response = await _apiClient.getJson(
      '/costs/summary',
      options: await _authorizedOptions(),
    );
    final summary = response.data['summary'];
    if (summary is! Map<String, dynamic>) {
      throw const NetworkRequestException(
        'A API nao retornou o resumo de custos em formato valido.',
      );
    }
    return RemoteCostOverview.fromJson(summary);
  }

  @override
  Future<List<RemoteCostRecord>> list({
    required CostType type,
    String query = '',
    CostStatus? status,
    DateTime? from,
    DateTime? to,
    bool overdueOnly = false,
  }) async {
    final response = await _apiClient.getJson(
      '/costs',
      options: await _authorizedOptions(
        queryParameters: <String, Object?>{
          'type': type.dbValue,
          if (status != null) 'status': status.dbValue,
          if (from != null) 'startDate': from.toUtc().toIso8601String(),
          if (to != null) 'endDate': to.toUtc().toIso8601String(),
          if (overdueOnly) 'overdueOnly': true,
          'page': 1,
          'pageSize': 100,
        },
      ),
    );
    final items = response.data['items'];
    if (items is! List) {
      throw const NetworkRequestException(
        'A API nao retornou a lista de custos em formato valido.',
      );
    }
    return items
        .whereType<Map<String, dynamic>>()
        .map(RemoteCostRecord.fromJson)
        .where((cost) {
          if (query.trim().isEmpty) {
            return true;
          }
          final normalized = query.trim().toLowerCase();
          return cost.description.toLowerCase().contains(normalized) ||
              (cost.category ?? '').toLowerCase().contains(normalized) ||
              (cost.notes ?? '').toLowerCase().contains(normalized);
        })
        .toList(growable: false);
  }

  @override
  Future<RemoteCostRecord> pay({
    required String remoteId,
    required MarkCostPaidInput input,
  }) async {
    final response = await _apiClient.postJson(
      '/costs/$remoteId/pay',
      body: <String, dynamic>{
        'paidAt': input.paidAt.toUtc().toIso8601String(),
        'paymentMethod': RemoteCostRecord.paymentMethodToRemote(
          input.paymentMethod,
        ),
        'registerInCash': input.registerInCash,
        'notes': input.notes,
      },
      options: await _authorizedOptions(),
    );
    return _readCost(response.data);
  }

  @override
  Future<RemoteCostRecord> update({
    required String remoteId,
    required UpdateCostInput input,
  }) async {
    final response = await _apiClient.putJson(
      '/costs/$remoteId',
      body: <String, dynamic>{
        'description': input.description,
        'type': input.type.dbValue,
        'category': input.category,
        'amountCents': input.amountCents,
        'referenceDate': input.referenceDate.toUtc().toIso8601String(),
        'notes': input.notes,
        'isRecurring': input.isRecurring,
      },
      options: await _authorizedOptions(),
    );
    return _readCost(response.data);
  }

  RemoteCostRecord _readCost(Map<String, dynamic> data) {
    final cost = data['cost'];
    if (cost is! Map<String, dynamic>) {
      throw const NetworkRequestException(
        'A API nao retornou o custo em formato valido.',
      );
    }
    return RemoteCostRecord.fromJson(cost);
  }

  Future<ApiRequestOptions> _authorizedOptions({
    Map<String, Object?> queryParameters = const <String, Object?>{},
  }) async {
    final token = await _tokenStorage.readAccessToken();
    if (token == null || token.trim().isEmpty) {
      throw const AuthenticationException(
        'Faca login remoto para gerenciar custos.',
      );
    }
    return ApiRequestOptions(
      headers: <String, String>{'Authorization': 'Bearer $token'},
      queryParameters: queryParameters,
    );
  }
}
