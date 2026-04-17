import '../../session/app_session.dart';
import '../../session/app_user.dart';
import '../../session/company_context.dart';
import '../contracts/auth_gateway.dart';

class FakeAuthGateway implements AuthGateway {
  @override
  Future<AppSession?> restoreSession() async {
    return null;
  }

  @override
  Future<AppSession> refreshSession() async {
    return _buildMockSession();
  }

  @override
  Future<AppSession> signIn({
    required String identifier,
    required String password,
  }) async {
    return _buildMockSession(identifier: identifier, passwordHint: password);
  }

  @override
  Future<AppSession> signUp({
    required String companyName,
    required String companySlug,
    required String userName,
    required String email,
    required String password,
  }) async {
    return _buildMockSession(
      identifier: email,
      passwordHint: password,
      displayName: userName,
      companyName: companyName,
      isPlatformAdmin: false,
      roleLabel: 'Proprietario',
    );
  }

  @override
  Future<String> requestPasswordReset({required String email}) async {
    return 'Se existir uma conta com este e-mail, enviaremos as instrucoes para redefinir sua senha.';
  }

  @override
  Future<String> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    return 'Sua senha foi redefinida com sucesso. Entre novamente para continuar.';
  }

  @override
  Future<void> signOut() async {}

  AppSession _buildMockSession({
    String identifier = 'mock.operator@simples.local',
    String passwordHint = '123456',
    String displayName = 'Operador SaaS Mock',
    String companyName = 'Empresa Demo SaaS',
    bool isPlatformAdmin = true,
    String roleLabel = 'Administrador mock',
  }) {
    final sanitizedIdentifier = identifier.trim().isEmpty
        ? 'mock.operator@simples.local'
        : identifier.trim();

    return AppSession(
      scope: SessionScope.authenticatedMock,
      user: AppUser(
        localId: null,
        remoteId: 'usr_mock_operator_001',
        displayName: displayName,
        email: sanitizedIdentifier,
        roleLabel: roleLabel,
        kind: AppUserKind.mockAuthenticated,
        isPlatformAdmin: isPlatformAdmin,
      ),
      company: CompanyContext(
        localId: null,
        remoteId: 'cmp_mock_demo_001',
        displayName: companyName,
        legalName: '$companyName LTDA',
        documentNumber: '00.000.000/0001-00',
        licensePlan: 'demo',
        licenseStatus: 'active',
        syncEnabled: true,
      ),
      startedAt: DateTime.now(),
      isOfflineFallback: passwordHint == 'offline',
    );
  }
}
