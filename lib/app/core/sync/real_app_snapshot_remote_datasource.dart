import '../errors/app_exceptions.dart';
import '../network/contracts/api_client_contract.dart';
import '../session/auth_token_storage.dart';
import 'app_snapshot_remote_datasource.dart';

class RealAppSnapshotRemoteDataSource implements AppSnapshotRemoteDataSource {
  const RealAppSnapshotRemoteDataSource({
    required ApiClientContract apiClient,
    required AuthTokenStorage tokenStorage,
  }) : _apiClient = apiClient,
       _tokenStorage = tokenStorage;

  final ApiClientContract _apiClient;
  final AuthTokenStorage _tokenStorage;

  @override
  Future<AppSnapshotResponse> fetchSnapshot({
    Iterable<String> features = const <String>[],
  }) async {
    final response = await _apiClient.getJson(
      '/app/snapshot',
      options: await _authorizedOptions(
        queryParameters: <String, Object?>{
          if (features.isNotEmpty) 'features': features.join(','),
        },
      ),
    );
    return AppSnapshotResponse.fromJson(response.data);
  }

  Future<ApiRequestOptions> _authorizedOptions({
    Map<String, Object?> queryParameters = const <String, Object?>{},
  }) async {
    final token = await _tokenStorage.readAccessToken();
    final clientContext = await _tokenStorage.readClientContext();
    if (token == null || token.trim().isEmpty) {
      throw const AuthenticationException(
        'Faca login remoto para atualizar o cache da nuvem.',
      );
    }
    if (clientContext == null ||
        clientContext.clientInstanceId.trim().isEmpty) {
      throw const AuthenticationException(
        'Identificador deste aparelho ausente para atualizar o cache da nuvem.',
      );
    }

    return ApiRequestOptions(
      headers: <String, String>{
        'Authorization': 'Bearer $token',
        'X-Client-Instance-Id': clientContext.clientInstanceId,
      },
      queryParameters: queryParameters,
    );
  }
}
