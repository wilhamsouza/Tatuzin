import '../../session/app_session.dart';

abstract interface class AuthGateway {
  Future<AppSession?> restoreSession();

  Future<AppSession> signIn({
    required String identifier,
    required String password,
  });

  Future<AppSession> signUp({
    required String companyName,
    required String companySlug,
    required String userName,
    required String email,
    required String password,
  });

  Future<String> requestPasswordReset({required String email});

  Future<String> resetPassword({
    required String token,
    required String newPassword,
  });

  Future<AppSession> refreshSession();

  Future<void> signOut();
}
