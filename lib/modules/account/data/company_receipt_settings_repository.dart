import '../../../app/core/errors/app_exceptions.dart';
import '../../../app/core/network/contracts/api_client_contract.dart';
import '../../../app/core/session/auth_token_storage.dart';
import '../domain/company_receipt_settings.dart';

abstract interface class CompanyReceiptSettingsRepository {
  Future<CompanyReceiptSettingsSnapshot> fetch();

  Future<CompanyReceiptSettingsSnapshot> save(
    CompanyReceiptSettingsDraft draft,
  );
}

class RemoteCompanyReceiptSettingsRepository
    implements CompanyReceiptSettingsRepository {
  const RemoteCompanyReceiptSettingsRepository({
    required ApiClientContract apiClient,
    required AuthTokenStorage tokenStorage,
  }) : _apiClient = apiClient,
       _tokenStorage = tokenStorage;

  final ApiClientContract _apiClient;
  final AuthTokenStorage _tokenStorage;

  @override
  Future<CompanyReceiptSettingsSnapshot> fetch() async {
    final response = await _apiClient.getJson(
      '/app/company/settings',
      options: ApiRequestOptions(headers: await _headers()),
    );
    return CompanyReceiptSettingsSnapshot.fromJson(response.data);
  }

  @override
  Future<CompanyReceiptSettingsSnapshot> save(
    CompanyReceiptSettingsDraft draft,
  ) async {
    try {
      final response = await _apiClient.patchJson(
        '/app/company/settings',
        body: draft.toJson(),
        options: ApiRequestOptions(headers: await _headers()),
      );
      return CompanyReceiptSettingsSnapshot.fromJson(response.data);
    } on NetworkRequestException catch (error) {
      final message = error.message;
      if (error.cause == 403 ||
          message.contains('COMPANY_SETTINGS_FORBIDDEN') ||
          message.contains('dono/administrador')) {
        throw const ValidationException(
          'Somente o dono/administrador pode alterar dados da empresa.',
        );
      }
      throw ValidationException(_friendlyRemoteError(message), cause: error);
    }
  }

  Future<Map<String, String>> _headers() async {
    final token = await _tokenStorage.readAccessToken();
    final clientContext = await _tokenStorage.readClientContext();
    if (token == null || token.trim().isEmpty || clientContext == null) {
      throw const AuthenticationException(
        'Entre novamente para alterar dados da empresa.',
      );
    }
    return <String, String>{
      'Authorization': 'Bearer ${token.trim()}',
      'X-Client-Instance-Id': clientContext.clientInstanceId,
    };
  }

  String _friendlyRemoteError(String message) {
    const marker = ': ';
    final markerIndex = message.indexOf(marker);
    if (markerIndex >= 0 && markerIndex + marker.length < message.length) {
      return message.substring(markerIndex + marker.length).trim();
    }
    return 'Nao foi possivel salvar os dados da empresa agora.';
  }
}
