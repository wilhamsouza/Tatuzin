import '../../../app/core/errors/app_exceptions.dart';
import '../../../app/core/network/contracts/api_client_contract.dart';
import '../../../app/core/session/auth_token_storage.dart';
import '../domain/employee_models.dart';

class EmployeesRemoteDataSource {
  const EmployeesRemoteDataSource({
    required ApiClientContract apiClient,
    required AuthTokenStorage tokenStorage,
  }) : _apiClient = apiClient,
       _tokenStorage = tokenStorage;

  final ApiClientContract _apiClient;
  final AuthTokenStorage _tokenStorage;

  Future<EmployeesPageResult> getEmployees({
    EmployeeStatus? status,
    EmployeeRole? role,
    String? search,
    int page = 1,
    int pageSize = 20,
  }) async {
    final response = await _runEmployeeRequest(
      () async => _apiClient.getJson(
        '/employees',
        options: ApiRequestOptions(
          headers: await _authorizedHeaders(),
          queryParameters: _withoutNulls(<String, Object?>{
            'status': status == null || status == EmployeeStatus.unknown
                ? null
                : status.key,
            'role': role == null || role == EmployeeRole.unknown
                ? null
                : role.key,
            'search': _nullableTrim(search),
            'page': page,
            'pageSize': pageSize,
          }),
        ),
      ),
    );
    return EmployeesPageResult.fromMap(response.data);
  }

  Future<EmployeeProfile> getEmployee(String id) async {
    final response = await _runEmployeeRequest(
      () async => _apiClient.getJson(
        '/employees/${Uri.encodeComponent(id)}',
        options: ApiRequestOptions(headers: await _authorizedHeaders()),
      ),
    );
    return _readEmployee(response.data);
  }

  Future<EmployeeProfile> createEmployee(EmployeeMutationInput input) async {
    final response = await _runEmployeeRequest(
      () async => _apiClient.postJson(
        '/employees',
        body: input.toCreateBody(),
        options: ApiRequestOptions(headers: await _authorizedHeaders()),
      ),
    );
    return _readEmployee(response.data);
  }

  Future<EmployeeProfile> updateEmployee(
    String id,
    EmployeeMutationInput input,
  ) async {
    final response = await _runEmployeeRequest(
      () async => _apiClient.patchJson(
        '/employees/${Uri.encodeComponent(id)}',
        body: input.toUpdateBody(),
        options: ApiRequestOptions(headers: await _authorizedHeaders()),
      ),
    );
    return _readEmployee(response.data);
  }

  Future<void> deleteEmployee(String id) async {
    await _runEmployeeRequest(
      () async => _apiClient.delete(
        '/employees/${Uri.encodeComponent(id)}',
        options: ApiRequestOptions(headers: await _authorizedHeaders()),
      ),
    );
  }

  Future<EmployeeActionResult> inviteEmployee(String id) async {
    final response = await _runEmployeeRequest(
      () async => _apiClient.postJson(
        '/employees/${Uri.encodeComponent(id)}/invite',
        options: ApiRequestOptions(headers: await _authorizedHeaders()),
      ),
    );
    return EmployeeActionResult.fromMap(response.data);
  }

  Future<EmployeeTemporaryPasswordResult> generateTemporaryPassword(
    String id,
  ) async {
    final response = await _runEmployeeRequest(
      () async => _apiClient.postJson(
        '/employees/${Uri.encodeComponent(id)}/access/temporary-password',
        options: ApiRequestOptions(headers: await _authorizedHeaders()),
      ),
    );
    return EmployeeTemporaryPasswordResult.fromMap(response.data);
  }

  Future<EmployeeProfile> disableEmployee(String id) async {
    final response = await _runEmployeeRequest(
      () async => _apiClient.postJson(
        '/employees/${Uri.encodeComponent(id)}/disable',
        options: ApiRequestOptions(headers: await _authorizedHeaders()),
      ),
    );
    return _readEmployee(response.data);
  }

  Future<EmployeeProfile> enableEmployee(String id) async {
    final response = await _runEmployeeRequest(
      () async => _apiClient.postJson(
        '/employees/${Uri.encodeComponent(id)}/enable',
        options: ApiRequestOptions(headers: await _authorizedHeaders()),
      ),
    );
    return _readEmployee(response.data);
  }

  Future<Map<String, String>> _authorizedHeaders() async {
    final token = await _tokenStorage.readAccessToken();
    if (token == null || token.trim().isEmpty) {
      throw const AuthenticationException(
        'Sessão remota não encontrada. Entre novamente para gerenciar funcionários.',
      );
    }
    return <String, String>{'Authorization': 'Bearer ${token.trim()}'};
  }

  EmployeeProfile _readEmployee(Map<String, dynamic> data) {
    final rawEmployee = data['employee'];
    if (rawEmployee is! Map) {
      throw const NetworkRequestException(
        'A API não retornou o funcionário em formato válido.',
      );
    }
    return EmployeeProfile.fromMap(Map<String, dynamic>.from(rawEmployee));
  }

  Future<T> _runEmployeeRequest<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on NetworkRequestException catch (error) {
      throw ValidationException(_friendlyMessage(error), cause: error);
    }
  }

  String _friendlyMessage(NetworkRequestException error) {
    final code = _extractCode(error.cause) ?? _extractCode(error.message);
    switch (code) {
      case 'FEATURE_NOT_AVAILABLE':
      case 'FEATURE_DISABLED':
      case 'FEATURE_REQUIRED':
        return 'Funcionários está disponível no plano PRO.';
      case 'EMPLOYEE_PERMISSION_DENIED':
      case 'EMPLOYEE_PERMISSION_REQUIRED':
        return 'Você não tem permissão para gerenciar funcionários.';
      case 'EMPLOYEE_LIMIT_REACHED':
        return 'Limite de funcionários atingido para o plano atual.';
      case 'EMPLOYEE_NOT_FOUND':
        return 'Funcionário não encontrado.';
      case 'EMPLOYEE_EMAIL_REQUIRED_FOR_ACCESS':
        return 'Informe um e-mail para gerar acesso. Login por telefone fica para uma melhoria futura.';
      case 'EMPLOYEE_ACCESS_EMAIL_CONFLICT':
      case 'EMPLOYEE_ACCESS_EMAIL_LOCKED':
        return 'Já existe uma conta com este e-mail. Use outro e-mail para evitar mistura de acesso.';
      case 'EMPLOYEE_DISABLED':
        return 'Reative o funcionário antes de redefinir a senha.';
    }

    if (error.cause == 403 || error.message.contains('403')) {
      final normalized = error.message.toLowerCase();
      if (normalized.contains('feature') ||
          normalized.contains('plano') ||
          normalized.contains('disponivel') ||
          normalized.contains('disponível')) {
        return 'Funcionários está disponível no plano PRO.';
      }
      return 'Você não tem permissão para gerenciar funcionários.';
    }

    if (error.cause == 409 || error.message.contains('409')) {
      return 'Limite de funcionários atingido para o plano atual.';
    }

    return error.message;
  }

  String? _extractCode(Object? source) {
    if (source is Map) {
      final direct = source['code'];
      if (direct is String && direct.trim().isNotEmpty) {
        return direct.trim().toUpperCase();
      }
      final body = source['body'];
      if (body is Map) {
        return _extractCode(body);
      }
      final error = source['error'];
      if (error is Map) {
        return _extractCode(error);
      }
    }
    if (source is String) {
      for (final code in const <String>[
        'FEATURE_NOT_AVAILABLE',
        'FEATURE_DISABLED',
        'FEATURE_REQUIRED',
        'EMPLOYEE_PERMISSION_DENIED',
        'EMPLOYEE_PERMISSION_REQUIRED',
        'EMPLOYEE_LIMIT_REACHED',
        'EMPLOYEE_NOT_FOUND',
        'EMPLOYEE_EMAIL_REQUIRED_FOR_ACCESS',
        'EMPLOYEE_ACCESS_EMAIL_CONFLICT',
        'EMPLOYEE_ACCESS_EMAIL_LOCKED',
        'EMPLOYEE_DISABLED',
      ]) {
        if (source.contains(code)) {
          return code;
        }
      }
    }
    return null;
  }

  Map<String, Object?> _withoutNulls(Map<String, Object?> source) {
    return Map<String, Object?>.fromEntries(
      source.entries.where((entry) => entry.value != null),
    );
  }

  String? _nullableTrim(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
