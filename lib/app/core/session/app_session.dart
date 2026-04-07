import 'app_user.dart';
import 'company_context.dart';

enum SessionScope { localDefault, authenticatedMock, authenticatedRemote }

class AppSession {
  const AppSession({
    required this.scope,
    required this.user,
    required this.company,
    required this.startedAt,
    required this.isOfflineFallback,
  });

  factory AppSession.localDefault() {
    return AppSession(
      scope: SessionScope.localDefault,
      user: const AppUser.localDefault(),
      company: const CompanyContext.localDefault(),
      startedAt: DateTime.now(),
      isOfflineFallback: true,
    );
  }

  final SessionScope scope;
  final AppUser user;
  final CompanyContext company;
  final DateTime startedAt;
  final bool isOfflineFallback;

  bool get isAuthenticated => scope != SessionScope.localDefault;

  bool get isLocalDefault => scope == SessionScope.localDefault;

  bool get isMockAuthenticated => scope == SessionScope.authenticatedMock;

  bool get isRemoteAuthenticated => scope == SessionScope.authenticatedRemote;

  AppSession copyWith({
    SessionScope? scope,
    AppUser? user,
    CompanyContext? company,
    DateTime? startedAt,
    bool? isOfflineFallback,
  }) {
    return AppSession(
      scope: scope ?? this.scope,
      user: user ?? this.user,
      company: company ?? this.company,
      startedAt: startedAt ?? this.startedAt,
      isOfflineFallback: isOfflineFallback ?? this.isOfflineFallback,
    );
  }
}
