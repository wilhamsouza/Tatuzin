import '../constants/app_constants.dart';

enum AppUserKind { localOperator, mockAuthenticated, remoteAuthenticated }

class AppUser {
  const AppUser({
    required this.localId,
    required this.remoteId,
    required this.displayName,
    required this.email,
    required this.roleLabel,
    required this.kind,
    this.isPlatformAdmin = false,
  });

  const AppUser.localDefault()
    : localId = null,
      remoteId = null,
      displayName = AppConstants.defaultLocalOperatorName,
      email = null,
      roleLabel = 'Operacao local',
      kind = AppUserKind.localOperator,
      isPlatformAdmin = false;

  final int? localId;
  final String? remoteId;
  final String displayName;
  final String? email;
  final String roleLabel;
  final AppUserKind kind;
  final bool isPlatformAdmin;

  bool get hasRemoteIdentity => remoteId != null && remoteId!.isNotEmpty;

  bool get canUseRemoteFeatures => hasRemoteIdentity;

  String get statusLabel {
    switch (kind) {
      case AppUserKind.localOperator:
        return 'Sessao local';
      case AppUserKind.mockAuthenticated:
        return 'Sessao mock';
      case AppUserKind.remoteAuthenticated:
        return 'Sessao remota';
    }
  }

  String get adminLabel =>
      isPlatformAdmin ? 'Administrador interno' : 'Operador';
}
