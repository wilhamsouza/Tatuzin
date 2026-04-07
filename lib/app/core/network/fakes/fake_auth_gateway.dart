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
  Future<void> signOut() async {}

  AppSession _buildMockSession({
    String identifier = 'mock.operator@simples.local',
    String passwordHint = '123456',
  }) {
    final sanitizedIdentifier = identifier.trim().isEmpty
        ? 'mock.operator@simples.local'
        : identifier.trim();

    return AppSession(
      scope: SessionScope.authenticatedMock,
      user: AppUser(
        localId: null,
        remoteId: 'usr_mock_operator_001',
        displayName: 'Operador SaaS Mock',
        email: sanitizedIdentifier,
        roleLabel: 'Administrador mock',
        kind: AppUserKind.mockAuthenticated,
        isPlatformAdmin: true,
      ),
      company: const CompanyContext(
        localId: null,
        remoteId: 'cmp_mock_demo_001',
        displayName: 'Empresa Demo SaaS',
        legalName: 'Empresa Demo SaaS LTDA',
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
