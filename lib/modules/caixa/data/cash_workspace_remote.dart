import '../../../app/core/errors/app_exceptions.dart';
import '../../../app/core/network/contracts/api_client_contract.dart';
import '../../../app/core/session/auth_token_storage.dart';

abstract interface class CashWorkspaceRemote {
  Future<Map<String, dynamic>> read();
  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body);
}

class ApiCashWorkspaceRemote implements CashWorkspaceRemote {
  const ApiCashWorkspaceRemote(this.api, this.tokens);
  final ApiClientContract api;
  final AuthTokenStorage tokens;
  Future<ApiRequestOptions> _options() async {
    final token = await tokens.readAccessToken();
    if (token == null || token.isEmpty) {
      throw const AuthenticationException(
        'Entre novamente para acessar o caixa do funcionário.',
      );
    }
    final client = await tokens.readClientContext();
    if (client == null || client.clientInstanceId.trim().isEmpty) {
      throw const AuthenticationException(
        'Conecte este aparelho à conta antes de acessar o caixa do funcionário.',
      );
    }
    return ApiRequestOptions(
      headers: {
        'Authorization': 'Bearer $token',
        'X-Client-Instance-Id': client.clientInstanceId,
      },
    );
  }

  @override
  Future<Map<String, dynamic>> read() async => (await api.getJson(
    '/app/cash/workspace',
    options: await _options(),
  )).data;
  @override
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body,
  ) async => (await api.postJson(
    '/app/cash/$path',
    body: body,
    options: await _options(),
  )).data;
}
