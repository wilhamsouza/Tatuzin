import 'app_user.dart';
import 'company_context.dart';
import '../entitlements/plan_entitlements.dart';

enum SessionScope { localDefault, authenticatedMock, authenticatedRemote }

class AppSession {
  const AppSession({
    required this.scope,
    required this.user,
    required this.company,
    required this.startedAt,
    required this.isOfflineFallback,
    this.clientInstanceId,
    this.membership,
    this.employee,
  });

  factory AppSession.localDefault() {
    return AppSession(
      scope: SessionScope.localDefault,
      user: const AppUser.localDefault(),
      company: const CompanyContext.localDefault(),
      startedAt: DateTime.now(),
      isOfflineFallback: false,
    );
  }

  final SessionScope scope;
  final AppUser user;
  final CompanyContext company;
  final DateTime startedAt;
  final bool isOfflineFallback;
  final String? clientInstanceId;
  final AppMembershipContext? membership;
  final AppEmployeeContext? employee;

  bool get isAuthenticated => scope != SessionScope.localDefault;

  bool get isLocalDefault => scope == SessionScope.localDefault;

  bool get isMockAuthenticated => scope == SessionScope.authenticatedMock;

  bool get isRemoteAuthenticated => scope == SessionScope.authenticatedRemote;

  PlanKey get plan => company.plan;

  Set<FeatureKey> get features => company.features;

  PlanLimits get limits => company.limits;

  bool hasFeature(FeatureKey feature) => company.hasFeature(feature);

  Set<String> get effectivePermissions {
    final employeeSnapshot = employee;
    if (employeeSnapshot != null) {
      if (employeeSnapshot.isDisabled) {
        return const <String>{};
      }
      return employeeSnapshot.permissions;
    }
    return membership?.permissions ?? const <String>{};
  }

  bool hasEffectivePermission(String permission) {
    return effectivePermissions.contains(permission);
  }

  bool get hasClientInstanceId {
    final value = clientInstanceId?.trim();
    return value != null && value.isNotEmpty;
  }

  bool get hasOperationalIdentity {
    return isAuthenticated &&
        user.hasRemoteIdentity &&
        company.hasRemoteIdentity &&
        hasClientInstanceId;
  }

  bool get canStartSync {
    return isRemoteAuthenticated &&
        hasOperationalIdentity &&
        !isOfflineFallback;
  }

  AppSession copyWith({
    SessionScope? scope,
    AppUser? user,
    CompanyContext? company,
    DateTime? startedAt,
    bool? isOfflineFallback,
    String? clientInstanceId,
    AppMembershipContext? membership,
    AppEmployeeContext? employee,
    bool clearClientInstanceId = false,
    bool clearMembership = false,
    bool clearEmployee = false,
  }) {
    return AppSession(
      scope: scope ?? this.scope,
      user: user ?? this.user,
      company: company ?? this.company,
      startedAt: startedAt ?? this.startedAt,
      isOfflineFallback: isOfflineFallback ?? this.isOfflineFallback,
      clientInstanceId: clearClientInstanceId
          ? null
          : clientInstanceId ?? this.clientInstanceId,
      membership: clearMembership ? null : membership ?? this.membership,
      employee: clearEmployee ? null : employee ?? this.employee,
    );
  }
}

class AppMembershipContext {
  const AppMembershipContext({required this.role, required this.permissions});

  final String role;
  final Set<String> permissions;

  bool hasPermission(String permission) => permissions.contains(permission);
}

class AppEmployeeContext {
  const AppEmployeeContext({
    required this.id,
    required this.role,
    required this.status,
    required this.permissions,
  });

  final String id;
  final String role;
  final String status;
  final Set<String> permissions;

  bool get isDisabled => status.trim().toUpperCase() == 'DISABLED';

  bool hasPermission(String permission) {
    if (isDisabled) {
      return false;
    }
    return permissions.contains(permission);
  }
}
