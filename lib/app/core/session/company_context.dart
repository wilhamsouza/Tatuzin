import '../constants/app_constants.dart';
import '../entitlements/plan_entitlements.dart';

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
    this.receiptSettings = const CompanyReceiptSettings.defaults(),
    PlanEntitlements? entitlements,
  }) : entitlements = entitlements ?? PlanEntitlements.free;

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
      syncEnabled = false,
      receiptSettings = const CompanyReceiptSettings.defaults(),
      entitlements = PlanEntitlements.free;

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
  final CompanyReceiptSettings receiptSettings;
  final PlanEntitlements entitlements;

  PlanKey get plan => entitlements.plan;

  Set<FeatureKey> get features => entitlements.features;

  PlanLimits get limits => entitlements.limits;

  bool hasFeature(FeatureKey feature) => entitlements.hasFeature(feature);

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
    switch ((licensePlan?.trim().toLowerCase() ?? entitlements.plan.key)) {
      case 'free':
      case 'trial':
        return 'Free';
      case 'basic':
        return 'Básico';
      case 'pro':
        return 'Pro';
      default:
        return 'Local';
    }
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
      return 'A licenca desta empresa esta suspensa. A base local permanece vinculada a este tenant.';
    }
    if (isExpiredLicense) {
      return 'A licenca desta empresa expirou. A base local permanece vinculada a este tenant.';
    }
    if (!syncEnabled) {
      return 'A sincronizacao cloud foi desativada para esta empresa.';
    }
    return null;
  }

  String? get _normalizedLicenseStatus => licenseStatus?.trim().toLowerCase();

  CompanyContext copyWith({
    String? displayName,
    String? legalName,
    String? documentNumber,
    CompanyReceiptSettings? receiptSettings,
  }) {
    return CompanyContext(
      localId: localId,
      remoteId: remoteId,
      displayName: displayName ?? this.displayName,
      legalName: legalName ?? this.legalName,
      documentNumber: documentNumber ?? this.documentNumber,
      licensePlan: licensePlan,
      licenseStatus: licenseStatus,
      licenseStartsAt: licenseStartsAt,
      licenseExpiresAt: licenseExpiresAt,
      maxDevices: maxDevices,
      syncEnabled: syncEnabled,
      receiptSettings: receiptSettings ?? this.receiptSettings,
      entitlements: entitlements,
    );
  }
}

class CompanyReceiptSettings {
  const CompanyReceiptSettings({
    this.receiptDisplayName,
    this.receiptDocument,
    this.receiptPhone,
    this.receiptAddress,
    this.receiptFooterMessage,
    this.showDocumentOnReceipt = true,
    this.showPhoneOnReceipt = true,
    this.showAddressOnReceipt = true,
    this.showFooterMessageOnReceipt = true,
  });

  const CompanyReceiptSettings.defaults()
    : receiptDisplayName = null,
      receiptDocument = null,
      receiptPhone = null,
      receiptAddress = null,
      receiptFooterMessage = null,
      showDocumentOnReceipt = true,
      showPhoneOnReceipt = true,
      showAddressOnReceipt = true,
      showFooterMessageOnReceipt = true;

  final String? receiptDisplayName;
  final String? receiptDocument;
  final String? receiptPhone;
  final String? receiptAddress;
  final String? receiptFooterMessage;
  final bool showDocumentOnReceipt;
  final bool showPhoneOnReceipt;
  final bool showAddressOnReceipt;
  final bool showFooterMessageOnReceipt;

  String displayNameOrFallback(String fallback) {
    final value = receiptDisplayName?.trim();
    if (value == null || value.isEmpty) {
      return fallback.trim().isEmpty ? AppConstants.appName : fallback.trim();
    }
    return value;
  }

  String footerOrFallback(String fallback) {
    final value = receiptFooterMessage?.trim();
    if (!showFooterMessageOnReceipt || value == null || value.isEmpty) {
      return fallback;
    }
    return value;
  }

  CompanyReceiptSettings copyWith({
    String? receiptDisplayName,
    String? receiptDocument,
    String? receiptPhone,
    String? receiptAddress,
    String? receiptFooterMessage,
    bool? showDocumentOnReceipt,
    bool? showPhoneOnReceipt,
    bool? showAddressOnReceipt,
    bool? showFooterMessageOnReceipt,
    bool clearReceiptDisplayName = false,
    bool clearReceiptDocument = false,
    bool clearReceiptPhone = false,
    bool clearReceiptAddress = false,
    bool clearReceiptFooterMessage = false,
  }) {
    return CompanyReceiptSettings(
      receiptDisplayName: clearReceiptDisplayName
          ? null
          : receiptDisplayName ?? this.receiptDisplayName,
      receiptDocument: clearReceiptDocument
          ? null
          : receiptDocument ?? this.receiptDocument,
      receiptPhone: clearReceiptPhone
          ? null
          : receiptPhone ?? this.receiptPhone,
      receiptAddress: clearReceiptAddress
          ? null
          : receiptAddress ?? this.receiptAddress,
      receiptFooterMessage: clearReceiptFooterMessage
          ? null
          : receiptFooterMessage ?? this.receiptFooterMessage,
      showDocumentOnReceipt:
          showDocumentOnReceipt ?? this.showDocumentOnReceipt,
      showPhoneOnReceipt: showPhoneOnReceipt ?? this.showPhoneOnReceipt,
      showAddressOnReceipt: showAddressOnReceipt ?? this.showAddressOnReceipt,
      showFooterMessageOnReceipt:
          showFooterMessageOnReceipt ?? this.showFooterMessageOnReceipt,
    );
  }
}
