import '../../../../app/core/errors/app_exceptions.dart';
import '../../../../app/core/network/contracts/api_client_contract.dart';
import '../../../../app/core/session/auth_token_storage.dart';
import '../datasources/inventory_remote_datasource.dart';
import '../models/remote_inventory_item.dart';

class RealInventoryRemoteDatasource implements InventoryRemoteDatasource {
  const RealInventoryRemoteDatasource({
    required ApiClientContract apiClient,
    required AuthTokenStorage tokenStorage,
  }) : _apiClient = apiClient,
       _tokenStorage = tokenStorage;

  final ApiClientContract _apiClient;
  final AuthTokenStorage _tokenStorage;

  @override
  Future<RemoteInventorySummary> fetchSummary() async {
    final response = await _apiClient.getJson(
      '/inventory/summary',
      options: await _authorizedOptions(),
    );
    final summary = response.data['summary'];
    if (summary is! Map<String, dynamic>) {
      throw const NetworkRequestException(
        'A API nao retornou o resumo de estoque em formato valido.',
      );
    }
    return RemoteInventorySummary.fromJson(summary);
  }

  @override
  Future<List<RemoteInventoryItem>> listItems({
    String query = '',
    String filter = 'all',
  }) async {
    final response = await _apiClient.getJson(
      '/inventory',
      options: await _authorizedOptions(
        queryParameters: <String, Object?>{
          if (query.trim().isNotEmpty) 'query': query.trim(),
          'filter': filter,
          'page': 1,
          'pageSize': 100,
        },
      ),
    );
    final items = response.data['items'];
    if (items is! List) {
      throw const NetworkRequestException(
        'A API nao retornou a lista de estoque em formato valido.',
      );
    }
    return items
        .whereType<Map<String, dynamic>>()
        .map(RemoteInventoryItem.fromJson)
        .toList(growable: false);
  }

  Future<ApiRequestOptions> _authorizedOptions({
    Map<String, Object?> queryParameters = const <String, Object?>{},
  }) async {
    final token = await _tokenStorage.readAccessToken();
    if (token == null || token.trim().isEmpty) {
      throw const AuthenticationException(
        'Faca login remoto para consultar o estoque gerencial.',
      );
    }
    return ApiRequestOptions(
      headers: <String, String>{'Authorization': 'Bearer $token'},
      queryParameters: queryParameters,
    );
  }
}
