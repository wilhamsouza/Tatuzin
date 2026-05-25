import 'admin_billing_models.dart';

class AdminCompanyAccessSummary {
  const AdminCompanyAccessSummary({
    required this.company,
    required this.summary,
    required this.users,
    required this.employees,
    required this.permissionsCatalog,
    required this.devices,
    required this.audit,
  });

  final AdminAccessCompany company;
  final AdminAccessCounts summary;
  final List<AdminCompanyAccessUser> users;
  final List<AdminCompanyAccessEmployee> employees;
  final List<AdminCompanyAccessPermission> permissionsCatalog;
  final List<AdminCompanyAccessDevice> devices;
  final List<AdminCompanyAccessAuditEvent> audit;

  factory AdminCompanyAccessSummary.fromMap(Map<String, dynamic> map) {
    return AdminCompanyAccessSummary(
      company: AdminAccessCompany.fromMap(_readMap(map, 'company')),
      summary: AdminAccessCounts.fromMap(_readMap(map, 'summary')),
      users: _readList(
        map,
        'users',
      ).map(AdminCompanyAccessUser.fromMap).toList(growable: false),
      employees: _readList(
        map,
        'employees',
      ).map(AdminCompanyAccessEmployee.fromMap).toList(growable: false),
      permissionsCatalog: _readList(
        map,
        'permissionsCatalog',
      ).map(AdminCompanyAccessPermission.fromMap).toList(growable: false),
      devices: _readList(
        map,
        'devices',
      ).map(AdminCompanyAccessDevice.fromMap).toList(growable: false),
      audit: _readList(
        map,
        'audit',
      ).map(AdminCompanyAccessAuditEvent.fromMap).toList(growable: false),
    );
  }
}

class AdminAccessCompany {
  const AdminAccessCompany({
    required this.id,
    required this.name,
    required this.slug,
    required this.licensePlan,
    required this.licenseStatus,
    required this.pendingPlan,
  });

  final String id;
  final String name;
  final String slug;
  final String? licensePlan;
  final String? licenseStatus;
  final String? pendingPlan;

  factory AdminAccessCompany.fromMap(Map<String, dynamic> map) {
    final license = _readMap(map, 'license');
    return AdminAccessCompany(
      id: _readString(map, 'id'),
      name: _readString(map, 'name', fallback: 'Empresa'),
      slug: _readString(map, 'slug'),
      licensePlan: _readOptionalString(license, 'plan'),
      licenseStatus: _readOptionalString(license, 'status'),
      pendingPlan: _readOptionalString(license, 'pendingPlan'),
    );
  }
}

class AdminAccessCounts {
  const AdminAccessCounts({
    required this.totalUsers,
    required this.totalEmployees,
    required this.activeEmployees,
    required this.invitedEmployees,
    required this.disabledEmployees,
    required this.owners,
    required this.admins,
    required this.operators,
    required this.usersWithoutEmployeeProfile,
    required this.employeeProfilesWithoutUser,
    required this.lastSeenAt,
    required this.lastPermissionChangeAt,
  });

  final int totalUsers;
  final int totalEmployees;
  final int activeEmployees;
  final int invitedEmployees;
  final int disabledEmployees;
  final int owners;
  final int admins;
  final int operators;
  final int usersWithoutEmployeeProfile;
  final int employeeProfilesWithoutUser;
  final DateTime? lastSeenAt;
  final DateTime? lastPermissionChangeAt;

  factory AdminAccessCounts.fromMap(Map<String, dynamic> map) {
    return AdminAccessCounts(
      totalUsers: _readInt(map, 'totalUsers') ?? 0,
      totalEmployees: _readInt(map, 'totalEmployees') ?? 0,
      activeEmployees: _readInt(map, 'activeEmployees') ?? 0,
      invitedEmployees: _readInt(map, 'invitedEmployees') ?? 0,
      disabledEmployees: _readInt(map, 'disabledEmployees') ?? 0,
      owners: _readInt(map, 'owners') ?? 0,
      admins: _readInt(map, 'admins') ?? 0,
      operators: _readInt(map, 'operators') ?? 0,
      usersWithoutEmployeeProfile:
          _readInt(map, 'usersWithoutEmployeeProfile') ?? 0,
      employeeProfilesWithoutUser:
          _readInt(map, 'employeeProfilesWithoutUser') ?? 0,
      lastSeenAt: _readDate(map, 'lastSeenAt'),
      lastPermissionChangeAt: _readDate(map, 'lastPermissionChangeAt'),
    );
  }
}

class AdminCompanyAccessUser {
  const AdminCompanyAccessUser({
    required this.userId,
    required this.membershipId,
    required this.employeeProfileId,
    required this.name,
    required this.email,
    required this.membershipRole,
    required this.employeeRole,
    required this.status,
    required this.accountStatus,
    required this.effectivePermissions,
    required this.isOwner,
    required this.isProtectedOwner,
    required this.hasUserAccount,
    required this.hasEmployeeProfile,
    required this.invitationStatus,
    required this.invitationSentAt,
    required this.lastSeenAt,
    required this.createdAt,
    required this.updatedAt,
    required this.devices,
  });

  final String userId;
  final String membershipId;
  final String? employeeProfileId;
  final String name;
  final String email;
  final String membershipRole;
  final String employeeRole;
  final String status;
  final String accountStatus;
  final List<String> effectivePermissions;
  final bool isOwner;
  final bool isProtectedOwner;
  final bool hasUserAccount;
  final bool hasEmployeeProfile;
  final String? invitationStatus;
  final DateTime? invitationSentAt;
  final DateTime? lastSeenAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<AdminCompanyAccessDevice> devices;

  factory AdminCompanyAccessUser.fromMap(Map<String, dynamic> map) {
    return AdminCompanyAccessUser(
      userId: _readString(map, 'userId'),
      membershipId: _readString(map, 'membershipId'),
      employeeProfileId: _readOptionalString(map, 'employeeProfileId'),
      name: _readString(map, 'name', fallback: 'Usuario'),
      email: _readString(map, 'email', fallback: 'sem e-mail'),
      membershipRole: _readString(map, 'membershipRole'),
      employeeRole: _readString(map, 'employeeRole'),
      status: _readString(map, 'status', fallback: 'ACTIVE'),
      accountStatus: _readString(map, 'accountStatus', fallback: 'ACTIVE'),
      effectivePermissions: _readStringList(map, 'effectivePermissions'),
      isOwner: map['isOwner'] == true,
      isProtectedOwner: map['isProtectedOwner'] == true,
      hasUserAccount: map['hasUserAccount'] != false,
      hasEmployeeProfile: map['hasEmployeeProfile'] == true,
      invitationStatus: _readOptionalString(map, 'invitationStatus'),
      invitationSentAt: _readDate(map, 'invitationSentAt'),
      lastSeenAt: _readDate(map, 'lastSeenAt'),
      createdAt: _readDate(map, 'createdAt'),
      updatedAt: _readDate(map, 'updatedAt'),
      devices: _readList(
        map,
        'devices',
      ).map(AdminCompanyAccessDevice.fromMap).toList(growable: false),
    );
  }
}

class AdminCompanyAccessEmployee {
  const AdminCompanyAccessEmployee({
    required this.employeeProfileId,
    required this.userId,
    required this.membershipId,
    required this.name,
    required this.email,
    required this.phone,
    required this.employeeRole,
    required this.membershipRole,
    required this.status,
    required this.savedPermissions,
    required this.effectivePermissions,
    required this.isOwner,
    required this.isProtectedOwner,
    required this.hasUserAccount,
    required this.invitationStatus,
    required this.invitationSentAt,
    required this.inviteExpiresAt,
    required this.acceptedAt,
    required this.disabledAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String employeeProfileId;
  final String? userId;
  final String? membershipId;
  final String name;
  final String? email;
  final String? phone;
  final String employeeRole;
  final String? membershipRole;
  final String status;
  final List<String> savedPermissions;
  final List<String> effectivePermissions;
  final bool isOwner;
  final bool isProtectedOwner;
  final bool hasUserAccount;
  final String? invitationStatus;
  final DateTime? invitationSentAt;
  final DateTime? inviteExpiresAt;
  final DateTime? acceptedAt;
  final DateTime? disabledAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory AdminCompanyAccessEmployee.fromMap(Map<String, dynamic> map) {
    return AdminCompanyAccessEmployee(
      employeeProfileId: _readString(map, 'employeeProfileId'),
      userId: _readOptionalString(map, 'userId'),
      membershipId: _readOptionalString(map, 'membershipId'),
      name: _readString(map, 'name', fallback: 'Funcionario'),
      email: _readOptionalString(map, 'email'),
      phone: _readOptionalString(map, 'phone'),
      employeeRole: _readString(map, 'employeeRole', fallback: 'READ_ONLY'),
      membershipRole: _readOptionalString(map, 'membershipRole'),
      status: _readString(map, 'status', fallback: 'DISABLED'),
      savedPermissions: _readStringList(map, 'savedPermissions'),
      effectivePermissions: _readStringList(map, 'effectivePermissions'),
      isOwner: map['isOwner'] == true,
      isProtectedOwner: map['isProtectedOwner'] == true,
      hasUserAccount: map['hasUserAccount'] == true,
      invitationStatus: _readOptionalString(map, 'invitationStatus'),
      invitationSentAt: _readDate(map, 'invitationSentAt'),
      inviteExpiresAt: _readDate(map, 'inviteExpiresAt'),
      acceptedAt: _readDate(map, 'acceptedAt'),
      disabledAt: _readDate(map, 'disabledAt'),
      createdAt: _readDate(map, 'createdAt'),
      updatedAt: _readDate(map, 'updatedAt'),
    );
  }
}

class AdminCompanyAccessPermission {
  const AdminCompanyAccessPermission({
    required this.key,
    required this.description,
    required this.owner,
    required this.admin,
    required this.operator,
  });

  final String key;
  final String description;
  final bool owner;
  final bool admin;
  final bool operator;

  factory AdminCompanyAccessPermission.fromMap(Map<String, dynamic> map) {
    return AdminCompanyAccessPermission(
      key: _readString(map, 'key'),
      description: _readString(map, 'description'),
      owner: map['owner'] == true,
      admin: map['admin'] == true,
      operator: map['operator'] == true,
    );
  }
}

class AdminCompanyAccessDevice {
  const AdminCompanyAccessDevice({
    required this.id,
    required this.userId,
    required this.membershipId,
    required this.userName,
    required this.userEmail,
    required this.membershipRole,
    required this.clientType,
    required this.clientInstanceId,
    required this.deviceLabel,
    required this.platform,
    required this.appVersion,
    required this.status,
    required this.lastSeenAt,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String membershipId;
  final String userName;
  final String userEmail;
  final String membershipRole;
  final String clientType;
  final String clientInstanceId;
  final String? deviceLabel;
  final String? platform;
  final String? appVersion;
  final String status;
  final DateTime? lastSeenAt;
  final DateTime? createdAt;

  factory AdminCompanyAccessDevice.fromMap(Map<String, dynamic> map) {
    return AdminCompanyAccessDevice(
      id: _readString(map, 'id'),
      userId: _readString(map, 'userId'),
      membershipId: _readString(map, 'membershipId'),
      userName: _readString(map, 'userName', fallback: 'Usuario'),
      userEmail: _readString(map, 'userEmail', fallback: 'sem e-mail'),
      membershipRole: _readString(map, 'membershipRole'),
      clientType: _readString(map, 'clientType', fallback: 'UNKNOWN'),
      clientInstanceId: _readString(map, 'clientInstanceId'),
      deviceLabel: _readOptionalString(map, 'deviceLabel'),
      platform: _readOptionalString(map, 'platform'),
      appVersion: _readOptionalString(map, 'appVersion'),
      status: _readString(map, 'status', fallback: 'UNKNOWN'),
      lastSeenAt: _readDate(map, 'lastSeenAt'),
      createdAt: _readDate(map, 'createdAt'),
    );
  }
}

class AdminCompanyAccessAuditEvent {
  const AdminCompanyAccessAuditEvent({
    required this.id,
    required this.source,
    required this.action,
    required this.actorName,
    required this.actorEmail,
    required this.target,
    required this.reason,
    required this.metadata,
    required this.createdAt,
  });

  final String id;
  final String source;
  final String action;
  final String? actorName;
  final String? actorEmail;
  final String? target;
  final String? reason;
  final Object? metadata;
  final DateTime? createdAt;

  factory AdminCompanyAccessAuditEvent.fromMap(Map<String, dynamic> map) {
    return AdminCompanyAccessAuditEvent(
      id: _readString(map, 'id'),
      source: _readString(map, 'source'),
      action: _readString(map, 'action'),
      actorName: _readOptionalString(map, 'actorName'),
      actorEmail: _readOptionalString(map, 'actorEmail'),
      target: _readOptionalString(map, 'target'),
      reason: _readOptionalString(map, 'reason'),
      metadata: sanitizeAdminBillingValue(map['metadata']),
      createdAt: _readDate(map, 'createdAt'),
    );
  }
}

List<Map<String, dynamic>> _readList(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! List) {
    return const <Map<String, dynamic>>[];
  }
  return value.whereType<Map<String, dynamic>>().toList(growable: false);
}

Map<String, dynamic> _readMap(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is Map<String, dynamic>) {
    return value;
  }
  return const <String, dynamic>{};
}

String _readString(
  Map<String, dynamic> map,
  String key, {
  String fallback = '',
}) {
  final value = map[key];
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  return fallback;
}

String? _readOptionalString(Map<String, dynamic> map, String key) {
  final value = map[key]?.toString().trim();
  if (value == null || value.isEmpty) {
    return null;
  }
  return value;
}

DateTime? _readDate(Map<String, dynamic> map, String key) {
  final value = _readOptionalString(map, key);
  return value == null ? null : DateTime.tryParse(value);
}

int? _readInt(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  return int.tryParse(value?.toString() ?? '');
}

List<String> _readStringList(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! List) {
    return const <String>[];
  }
  return value.map((item) => item.toString()).toList(growable: false);
}
