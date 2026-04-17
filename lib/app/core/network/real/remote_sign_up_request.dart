import '../../session/auth_token_storage.dart';

class RemoteSignUpRequest {
  const RemoteSignUpRequest({
    required this.companyName,
    required this.companySlug,
    required this.userName,
    required this.email,
    required this.password,
  });

  final String companyName;
  final String companySlug;
  final String userName;
  final String email;
  final String password;

  Map<String, dynamic> toApiPayload(AuthClientContext clientContext) {
    return <String, dynamic>{
      'companyName': companyName.trim(),
      'companySlug': companySlug.trim().toLowerCase(),
      'userName': userName.trim(),
      'email': email.trim(),
      'password': password,
      ...clientContext.toApiPayload(),
    };
  }
}
