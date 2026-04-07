import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/errors/app_exceptions.dart';
import '../../../../app/core/network/contracts/api_client_contract.dart';
import '../../../../app/core/network/network_providers.dart';
import '../../../../app/core/providers/app_data_refresh_provider.dart';
import '../../../../app/core/session/auth_token_storage.dart';

final adminRemoteServiceProvider = Provider<AdminRemoteService>((ref) {
  return AdminRemoteService(
    apiClient: ref.watch(realApiClientProvider),
    tokenStorage: ref.watch(authTokenStorageProvider),
  );
});

final adminOverviewProvider = FutureProvider<AdminOverview>((ref) async {
  ref.watch(appDataRefreshProvider);
  return ref.watch(adminRemoteServiceProvider).fetchOverview();
});

final adminCompanyDetailProvider =
    FutureProvider.family<AdminCompanyDetail, String>((ref, companyId) async {
      ref.watch(appDataRefreshProvider);
      return ref
          .watch(adminRemoteServiceProvider)
          .fetchCompanyDetail(companyId);
    });

final adminLicenseControllerProvider =
    AsyncNotifierProvider<AdminLicenseController, void>(
      AdminLicenseController.new,
    );

class AdminRemoteService {
  const AdminRemoteService({
    required ApiClientContract apiClient,
    required AuthTokenStorage tokenStorage,
  }) : _apiClient = apiClient,
       _tokenStorage = tokenStorage;

  final ApiClientContract _apiClient;
  final AuthTokenStorage _tokenStorage;

  Future<AdminOverview> fetchOverview() async {
    final headers = await _authorizedHeaders();
    final companiesResponse = await _apiClient.getJson(
      '/admin/companies',
      options: ApiRequestOptions(headers: headers),
    );
    final auditResponse = await _apiClient.getJson(
      '/admin/audit/summary',
      options: ApiRequestOptions(headers: headers),
    );
    final syncResponse = await _apiClient.getJson(
      '/admin/sync/summary',
      options: ApiRequestOptions(headers: headers),
    );

    final companyItems =
        (companiesResponse.data['items'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(AdminCompanySummary.fromMap)
            .toList();

    return AdminOverview(
      companies: companyItems,
      auditSummary: AdminAuditSummary.fromMap(auditResponse.data),
      syncSummary: AdminSyncSummary.fromMap(syncResponse.data),
    );
  }

  Future<AdminCompanyDetail> fetchCompanyDetail(String companyId) async {
    final response = await _apiClient.getJson(
      '/admin/companies/$companyId',
      options: ApiRequestOptions(headers: await _authorizedHeaders()),
    );
    return AdminCompanyDetail.fromMap(response.data);
  }

  Future<AdminLicenseSnapshot> updateLicense({
    required String companyId,
    required String plan,
    required String status,
    required DateTime? expiresAt,
    required bool syncEnabled,
    required int? maxDevices,
  }) async {
    final response = await _apiClient.patchJson(
      '/admin/licenses/$companyId',
      body: <String, dynamic>{
        'plan': plan.trim(),
        'status': status.trim().toLowerCase(),
        'expiresAt': expiresAt?.toIso8601String(),
        'syncEnabled': syncEnabled,
        'maxDevices': maxDevices,
      },
      options: ApiRequestOptions(headers: await _authorizedHeaders()),
    );
    final license = response.data['license'];
    if (license is! Map<String, dynamic>) {
      throw const ValidationException(
        'A API nao retornou a licenca atualizada no formato esperado.',
      );
    }
    return AdminLicenseSnapshot.fromMap(license);
  }

  Future<Map<String, String>> _authorizedHeaders() async {
    final token = await _tokenStorage.readAccessToken();
    if (token == null || token.trim().isEmpty) {
      throw const AuthenticationException(
        'Sessao administrativa nao encontrada. Faca login remoto novamente.',
      );
    }

    return <String, String>{'Authorization': 'Bearer ${token.trim()}'};
  }
}

class AdminLicenseController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<AdminLicenseSnapshot> updateLicense({
    required String companyId,
    required String plan,
    required String status,
    required DateTime? expiresAt,
    required bool syncEnabled,
    required int? maxDevices,
  }) async {
    state = const AsyncLoading();
    try {
      final result = await ref
          .read(adminRemoteServiceProvider)
          .updateLicense(
            companyId: companyId,
            plan: plan,
            status: status,
            expiresAt: expiresAt,
            syncEnabled: syncEnabled,
            maxDevices: maxDevices,
          );
      ref.read(appDataRefreshProvider.notifier).state++;
      ref.invalidate(adminOverviewProvider);
      ref.invalidate(adminCompanyDetailProvider(companyId));
      state = const AsyncData(null);
      return result;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }
}

class AdminOverview {
  const AdminOverview({
    required this.companies,
    required this.auditSummary,
    required this.syncSummary,
  });

  final List<AdminCompanySummary> companies;
  final AdminAuditSummary auditSummary;
  final AdminSyncSummary syncSummary;
}

class AdminCompanySummary {
  const AdminCompanySummary({
    required this.id,
    required this.name,
    required this.legalName,
    required this.documentNumber,
    required this.slug,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    required this.license,
    required this.counts,
  });

  final String id;
  final String name;
  final String legalName;
  final String? documentNumber;
  final String slug;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final AdminLicenseSnapshot? license;
  final AdminEntityCounts counts;

  factory AdminCompanySummary.fromMap(Map<String, dynamic> map) {
    return AdminCompanySummary(
      id: _readString(map, 'id'),
      name: _readString(map, 'name'),
      legalName: _readString(
        map,
        'legalName',
        fallback: _readString(map, 'name'),
      ),
      documentNumber: _readOptionalString(map, 'documentNumber'),
      slug: _readString(map, 'slug'),
      isActive: map['isActive'] == true,
      createdAt: _readOptionalDateTime(map, 'createdAt'),
      updatedAt: _readOptionalDateTime(map, 'updatedAt'),
      license: map['license'] is Map<String, dynamic>
          ? AdminLicenseSnapshot.fromMap(map['license'] as Map<String, dynamic>)
          : null,
      counts: AdminEntityCounts.fromMap(
        map['counts'] as Map<String, dynamic>? ?? const <String, dynamic>{},
      ),
    );
  }
}

class AdminCompanyDetail {
  const AdminCompanyDetail({required this.company, required this.memberships});

  final AdminCompanySummary company;
  final List<AdminMembershipSummary> memberships;

  factory AdminCompanyDetail.fromMap(Map<String, dynamic> map) {
    final companyMap = map['company'];
    if (companyMap is! Map<String, dynamic>) {
      throw const ValidationException(
        'A API nao retornou o detalhe da empresa no formato esperado.',
      );
    }

    return AdminCompanyDetail(
      company: AdminCompanySummary.fromMap(companyMap),
      memberships: (map['memberships'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(AdminMembershipSummary.fromMap)
          .toList(),
    );
  }
}

class AdminMembershipSummary {
  const AdminMembershipSummary({
    required this.id,
    required this.role,
    required this.isDefault,
    required this.createdAt,
    required this.updatedAt,
    required this.userId,
    required this.userName,
    required this.userEmail,
    required this.userIsActive,
    required this.userIsPlatformAdmin,
  });

  final String id;
  final String role;
  final bool isDefault;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String userId;
  final String userName;
  final String userEmail;
  final bool userIsActive;
  final bool userIsPlatformAdmin;

  factory AdminMembershipSummary.fromMap(Map<String, dynamic> map) {
    final user = map['user'];
    if (user is! Map<String, dynamic>) {
      throw const ValidationException(
        'A API nao retornou o usuario da membership no formato esperado.',
      );
    }

    return AdminMembershipSummary(
      id: _readString(map, 'id'),
      role: _readString(map, 'role'),
      isDefault: map['isDefault'] == true,
      createdAt: _readOptionalDateTime(map, 'createdAt'),
      updatedAt: _readOptionalDateTime(map, 'updatedAt'),
      userId: _readString(user, 'id'),
      userName: _readString(user, 'name'),
      userEmail: _readString(user, 'email'),
      userIsActive: user['isActive'] == true,
      userIsPlatformAdmin: user['isPlatformAdmin'] == true,
    );
  }
}

class AdminLicenseSnapshot {
  const AdminLicenseSnapshot({
    required this.id,
    required this.companyId,
    required this.companyName,
    required this.companyLegalName,
    required this.companySlug,
    required this.companyIsActive,
    required this.plan,
    required this.status,
    required this.startsAt,
    required this.expiresAt,
    required this.maxDevices,
    required this.syncEnabled,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String companyId;
  final String companyName;
  final String companyLegalName;
  final String companySlug;
  final bool companyIsActive;
  final String plan;
  final String status;
  final DateTime? startsAt;
  final DateTime? expiresAt;
  final int? maxDevices;
  final bool syncEnabled;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get statusLabel {
    switch (status.toLowerCase()) {
      case 'trial':
        return 'Trial';
      case 'active':
        return 'Ativa';
      case 'suspended':
        return 'Suspensa';
      case 'expired':
        return 'Expirada';
      default:
        return status;
    }
  }

  factory AdminLicenseSnapshot.fromMap(Map<String, dynamic> map) {
    return AdminLicenseSnapshot(
      id: _readString(map, 'id'),
      companyId: _readString(map, 'companyId'),
      companyName: _readString(map, 'companyName'),
      companyLegalName: _readString(
        map,
        'companyLegalName',
        fallback: _readString(map, 'companyName'),
      ),
      companySlug: _readString(map, 'companySlug'),
      companyIsActive: map['companyIsActive'] == true,
      plan: _readString(map, 'plan'),
      status: _readString(map, 'status').toLowerCase(),
      startsAt: _readOptionalDateTime(map, 'startsAt'),
      expiresAt: _readOptionalDateTime(map, 'expiresAt'),
      maxDevices: _readOptionalInt(map, 'maxDevices'),
      syncEnabled: map['syncEnabled'] == true,
      createdAt: _readOptionalDateTime(map, 'createdAt'),
      updatedAt: _readOptionalDateTime(map, 'updatedAt'),
    );
  }
}

class AdminEntityCounts {
  const AdminEntityCounts({
    required this.memberships,
    required this.categories,
    required this.products,
    required this.customers,
    required this.suppliers,
    required this.purchases,
    required this.sales,
    required this.financialEvents,
    required this.cashEvents,
  });

  final int memberships;
  final int categories;
  final int products;
  final int customers;
  final int suppliers;
  final int purchases;
  final int sales;
  final int financialEvents;
  final int cashEvents;

  int get totalRemoteRecords =>
      categories +
      products +
      customers +
      suppliers +
      purchases +
      sales +
      financialEvents +
      cashEvents;

  factory AdminEntityCounts.fromMap(Map<String, dynamic> map) {
    return AdminEntityCounts(
      memberships: _readOptionalInt(map, 'memberships') ?? 0,
      categories: _readOptionalInt(map, 'categories') ?? 0,
      products: _readOptionalInt(map, 'products') ?? 0,
      customers: _readOptionalInt(map, 'customers') ?? 0,
      suppliers: _readOptionalInt(map, 'suppliers') ?? 0,
      purchases: _readOptionalInt(map, 'purchases') ?? 0,
      sales: _readOptionalInt(map, 'sales') ?? 0,
      financialEvents: _readOptionalInt(map, 'financialEvents') ?? 0,
      cashEvents: _readOptionalInt(map, 'cashEvents') ?? 0,
    );
  }
}

class AdminAuditSummary {
  const AdminAuditSummary({
    required this.totalEvents,
    required this.countsByAction,
    required this.recentEvents,
  });

  final int totalEvents;
  final Map<String, int> countsByAction;
  final List<AdminAuditEvent> recentEvents;

  factory AdminAuditSummary.fromMap(Map<String, dynamic> map) {
    return AdminAuditSummary(
      totalEvents: _readOptionalInt(map, 'totalEvents') ?? 0,
      countsByAction: {
        for (final entry
            in (map['countsByAction'] as List<dynamic>? ?? const <dynamic>[])
                .whereType<Map<String, dynamic>>())
          _readString(entry, 'action'): _readOptionalInt(entry, 'count') ?? 0,
      },
      recentEvents: (map['recentEvents'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(AdminAuditEvent.fromMap)
          .toList(),
    );
  }
}

class AdminAuditEvent {
  const AdminAuditEvent({
    required this.id,
    required this.action,
    required this.createdAt,
    required this.actorUserName,
    required this.actorUserEmail,
    required this.targetCompanyName,
    required this.details,
  });

  final String id;
  final String action;
  final DateTime? createdAt;
  final String actorUserName;
  final String actorUserEmail;
  final String? targetCompanyName;
  final Map<String, dynamic> details;

  factory AdminAuditEvent.fromMap(Map<String, dynamic> map) {
    final actor =
        map['actorUser'] as Map<String, dynamic>? ?? const <String, dynamic>{};
    final targetCompany = map['targetCompany'] as Map<String, dynamic>?;
    return AdminAuditEvent(
      id: _readString(map, 'id'),
      action: _readString(map, 'action'),
      createdAt: _readOptionalDateTime(map, 'createdAt'),
      actorUserName: _readString(actor, 'name', fallback: 'Administrador'),
      actorUserEmail: _readString(actor, 'email', fallback: 'sem e-mail'),
      targetCompanyName: targetCompany == null
          ? null
          : _readOptionalString(targetCompany, 'name'),
      details:
          map['details'] as Map<String, dynamic>? ?? const <String, dynamic>{},
    );
  }
}

class AdminSyncSummary {
  const AdminSyncSummary({
    required this.totalCompanies,
    required this.syncEnabledCompanies,
    required this.licenseStatusCounts,
    required this.companySummaries,
  });

  final int totalCompanies;
  final int syncEnabledCompanies;
  final Map<String, int> licenseStatusCounts;
  final List<AdminSyncCompanySummary> companySummaries;

  factory AdminSyncSummary.fromMap(Map<String, dynamic> map) {
    final overview =
        map['overview'] as Map<String, dynamic>? ?? const <String, dynamic>{};
    return AdminSyncSummary(
      totalCompanies: _readOptionalInt(overview, 'totalCompanies') ?? 0,
      syncEnabledCompanies:
          _readOptionalInt(overview, 'syncEnabledCompanies') ?? 0,
      licenseStatusCounts: {
        for (final entry
            in (overview['licenseStatusCounts'] as Map<String, dynamic>? ??
                    const <String, dynamic>{})
                .entries)
          entry.key: _normalizeToInt(entry.value),
      },
      companySummaries:
          (map['companies'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .map(AdminSyncCompanySummary.fromMap)
              .toList(),
    );
  }
}

class AdminSyncCompanySummary {
  const AdminSyncCompanySummary({
    required this.companyId,
    required this.companyName,
    required this.companySlug,
    required this.licenseStatus,
    required this.licensePlan,
    required this.syncEnabled,
    required this.remoteRecordCount,
    required this.entityCounts,
  });

  final String companyId;
  final String companyName;
  final String companySlug;
  final String? licenseStatus;
  final String? licensePlan;
  final bool syncEnabled;
  final int remoteRecordCount;
  final AdminEntityCounts entityCounts;

  factory AdminSyncCompanySummary.fromMap(Map<String, dynamic> map) {
    return AdminSyncCompanySummary(
      companyId: _readString(map, 'companyId'),
      companyName: _readString(map, 'companyName'),
      companySlug: _readString(map, 'companySlug'),
      licenseStatus: _readOptionalString(map, 'licenseStatus'),
      licensePlan: _readOptionalString(map, 'licensePlan'),
      syncEnabled: map['syncEnabled'] == true,
      remoteRecordCount: _readOptionalInt(map, 'remoteRecordCount') ?? 0,
      entityCounts: AdminEntityCounts.fromMap(
        map['entityCounts'] as Map<String, dynamic>? ??
            const <String, dynamic>{},
      ),
    );
  }
}

String _readString(Map<String, dynamic> map, String key, {String? fallback}) {
  final value = map[key];
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  if (fallback != null) {
    return fallback;
  }
  throw ValidationException('Campo "$key" ausente no payload administrativo.');
}

String? _readOptionalString(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  return null;
}

DateTime? _readOptionalDateTime(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is String && value.trim().isNotEmpty) {
    return DateTime.tryParse(value.trim());
  }
  return null;
}

int? _readOptionalInt(Map<String, dynamic> map, String key) {
  return _normalizeToInt(map[key]);
}

int _normalizeToInt(Object? rawValue) {
  if (rawValue is int) {
    return rawValue;
  }
  if (rawValue is num) {
    return rawValue.toInt();
  }
  if (rawValue is String && rawValue.trim().isNotEmpty) {
    return int.tryParse(rawValue.trim()) ?? 0;
  }
  return 0;
}
