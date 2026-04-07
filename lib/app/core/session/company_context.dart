import '../constants/app_constants.dart';

class CompanyContext {
  const CompanyContext({
    required this.localId,
    required this.remoteId,
    required this.displayName,
    required this.legalName,
    required this.documentNumber,
    this.licensePlan,
    this.licenseStatus,
    this.licenseStartsAt,
    this.licenseExpiresAt,
    this.maxDevices,
    this.syncEnabled = false,
  });

  const CompanyContext.localDefault()
    : localId = null,
      remoteId = null,
      displayName = AppConstants.defaultLocalCompanyName,
      legalName = AppConstants.defaultLocalCompanyName,
      documentNumber = null,
      licensePlan = null,
      licenseStatus = null,
      licenseStartsAt = null,
      licenseExpiresAt = null,
      maxDevices = null,
      syncEnabled = false;

  final int? localId;
  final String? remoteId;
  final String displayName;
  final String legalName;
  final String? documentNumber;
  final String? licensePlan;
  final String? licenseStatus;
  final DateTime? licenseStartsAt;
  final DateTime? licenseExpiresAt;
  final int? maxDevices;
  final bool syncEnabled;

  bool get hasRemoteIdentity => remoteId != null && remoteId!.isNotEmpty;

  bool get hasCloudLicense =>
      licenseStatus != null && licenseStatus!.isNotEmpty;

  bool get isTrialLicense => _normalizedLicenseStatus == 'trial';

  bool get isActiveLicense => _normalizedLicenseStatus == 'active';

  bool get isSuspendedLicense => _normalizedLicenseStatus == 'suspended';

  bool get isExpiredLicense => _normalizedLicenseStatus == 'expired';

  bool get allowsCloudSync =>
      hasRemoteIdentity && syncEnabled && (isActiveLicense || isTrialLicense);

  String get licenseStatusLabel {
    switch (_normalizedLicenseStatus) {
      case 'trial':
        return 'Trial';
      case 'active':
        return 'Ativa';
      case 'suspended':
        return 'Suspensa';
      case 'expired':
        return 'Expirada';
      default:
        return 'Uso local';
    }
  }

  String get licensePlanLabel {
    final plan = licensePlan?.trim();
    if (plan == null || plan.isEmpty) {
      return 'Local';
    }
    return plan[0].toUpperCase() + plan.substring(1);
  }

  String get cloudSyncLabel => allowsCloudSync
      ? 'Cloud liberada'
      : hasCloudLicense
      ? 'Cloud limitada'
      : 'Somente local';

  String? get cloudSyncRestrictionReason {
    if (!hasRemoteIdentity) {
      return 'Tenant remoto ainda nao vinculado.';
    }
    if (!hasCloudLicense) {
      return 'Licenca cloud ainda nao configurada para esta empresa.';
    }
    if (isSuspendedLicense) {
      return 'A licenca desta empresa esta suspensa. O uso local continua liberado.';
    }
    if (isExpiredLicense) {
      return 'A licenca desta empresa expirou. O uso local continua liberado.';
    }
    if (!syncEnabled) {
      return 'A sincronizacao cloud foi desativada para esta empresa.';
    }
    return null;
  }

  String? get _normalizedLicenseStatus => licenseStatus?.trim().toLowerCase();
}
