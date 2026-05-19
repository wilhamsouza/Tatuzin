import '../../../app/core/session/company_context.dart';

class CompanyReceiptSettingsDraft {
  const CompanyReceiptSettingsDraft({
    required this.receiptDisplayName,
    required this.receiptDocument,
    required this.receiptPhone,
    required this.receiptAddress,
    required this.receiptFooterMessage,
    required this.showDocumentOnReceipt,
    required this.showPhoneOnReceipt,
    required this.showAddressOnReceipt,
    required this.showFooterMessageOnReceipt,
  });

  factory CompanyReceiptSettingsDraft.fromCompany(CompanyContext company) {
    final settings = company.receiptSettings;
    return CompanyReceiptSettingsDraft(
      receiptDisplayName: settings.receiptDisplayName,
      receiptDocument: settings.receiptDocument ?? company.documentNumber,
      receiptPhone: settings.receiptPhone,
      receiptAddress: settings.receiptAddress,
      receiptFooterMessage: settings.receiptFooterMessage,
      showDocumentOnReceipt: settings.showDocumentOnReceipt,
      showPhoneOnReceipt: settings.showPhoneOnReceipt,
      showAddressOnReceipt: settings.showAddressOnReceipt,
      showFooterMessageOnReceipt: settings.showFooterMessageOnReceipt,
    );
  }

  final String? receiptDisplayName;
  final String? receiptDocument;
  final String? receiptPhone;
  final String? receiptAddress;
  final String? receiptFooterMessage;
  final bool showDocumentOnReceipt;
  final bool showPhoneOnReceipt;
  final bool showAddressOnReceipt;
  final bool showFooterMessageOnReceipt;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'receiptDisplayName': receiptDisplayName,
      'receiptDocument': receiptDocument,
      'receiptPhone': receiptPhone,
      'receiptAddress': receiptAddress,
      'receiptFooterMessage': receiptFooterMessage,
      'showDocumentOnReceipt': showDocumentOnReceipt,
      'showPhoneOnReceipt': showPhoneOnReceipt,
      'showAddressOnReceipt': showAddressOnReceipt,
      'showFooterMessageOnReceipt': showFooterMessageOnReceipt,
    };
  }
}

class CompanyReceiptSettingsSnapshot {
  const CompanyReceiptSettingsSnapshot({
    required this.companyId,
    required this.displayName,
    required this.legalName,
    required this.documentNumber,
    required this.settings,
  });

  factory CompanyReceiptSettingsSnapshot.fromJson(Map<String, dynamic> json) {
    final company = json['company'] is Map<String, dynamic>
        ? json['company'] as Map<String, dynamic>
        : json;
    final name = _readString(company['name']) ?? 'Empresa';
    return CompanyReceiptSettingsSnapshot(
      companyId: _readString(company['id']),
      displayName: name,
      legalName: _readString(company['legalName']) ?? name,
      documentNumber: _readString(company['documentNumber']),
      settings: CompanyReceiptSettings(
        receiptDisplayName: _readString(company['receiptDisplayName']),
        receiptDocument: _readString(company['receiptDocument']),
        receiptPhone: _readString(company['receiptPhone']),
        receiptAddress: _readString(company['receiptAddress']),
        receiptFooterMessage: _readString(company['receiptFooterMessage']),
        showDocumentOnReceipt: company['showDocumentOnReceipt'] != false,
        showPhoneOnReceipt: company['showPhoneOnReceipt'] != false,
        showAddressOnReceipt: company['showAddressOnReceipt'] != false,
        showFooterMessageOnReceipt:
            company['showFooterMessageOnReceipt'] != false,
      ),
    );
  }

  final String? companyId;
  final String displayName;
  final String legalName;
  final String? documentNumber;
  final CompanyReceiptSettings settings;

  CompanyContext mergeInto(CompanyContext company) {
    return company.copyWith(
      displayName: displayName,
      legalName: legalName,
      documentNumber: documentNumber,
      receiptSettings: settings,
    );
  }

  static String? _readString(Object? value) {
    final text = value is String ? value.trim() : null;
    if (text == null || text.isEmpty) {
      return null;
    }
    return text;
  }
}
