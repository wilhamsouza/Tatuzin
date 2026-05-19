import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/errors/app_exceptions.dart';
import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/session/app_session.dart';
import '../../../../app/core/session/company_context.dart';
import '../../../../app/core/session/session_provider.dart';
import '../../../../app/core/widgets/app_button.dart';
import '../../../../app/core/widgets/app_feedback.dart';
import '../../../../app/core/widgets/app_main_drawer.dart';
import '../../../../app/core/widgets/app_page_header.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import '../../../../app/routes/route_names.dart';
import '../../../comprovantes/domain/entities/commercial_receipt.dart';
import '../../../comprovantes/domain/entities/commercial_receipt_detail_line.dart';
import '../../../comprovantes/domain/entities/commercial_receipt_item.dart';
import '../../../comprovantes/presentation/widgets/commercial_receipt_view.dart';
import '../../domain/company_receipt_settings.dart';
import '../providers/company_receipt_settings_providers.dart';

const _footerLimit = 160;

class CompanyPage extends ConsumerStatefulWidget {
  const CompanyPage({super.key});

  @override
  ConsumerState<CompanyPage> createState() => _CompanyPageState();
}

class _CompanyPageState extends ConsumerState<CompanyPage> {
  late final TextEditingController _displayNameController;
  late final TextEditingController _documentController;
  late final TextEditingController _phoneController;
  late final TextEditingController _addressController;
  late final TextEditingController _footerController;
  bool _showDocument = true;
  bool _showPhone = true;
  bool _showAddress = true;
  bool _showFooter = true;
  String? _loadedCompanyKey;
  bool _applyingCompany = false;

  @override
  void initState() {
    super.initState();
    _displayNameController = TextEditingController();
    _documentController = TextEditingController();
    _phoneController = TextEditingController();
    _addressController = TextEditingController();
    _footerController = TextEditingController();
    _footerController.addListener(() {
      if (!_applyingCompany && mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _documentController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _footerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(appSessionProvider);
    final company = session.company;
    final canEdit = _canEditCompany(session);
    final AsyncValue<CompanyReceiptSettingsSnapshot?> settingsAsync =
        session.isRemoteAuthenticated
        ? ref.watch(companyReceiptSettingsProvider).whenData((value) => value)
        : const AsyncValue<CompanyReceiptSettingsSnapshot?>.data(null);
    final controllerState = ref.watch(companyReceiptSettingsControllerProvider);

    settingsAsync.whenData((snapshot) {
      _applyCompany(snapshot?.mergeInto(company) ?? company);
    });
    if (!session.isRemoteAuthenticated ||
        (settingsAsync.hasError && _loadedCompanyKey == null)) {
      _applyCompany(company);
    }
    final canSave =
        canEdit && !controllerState.isLoading && !settingsAsync.hasError;

    return Scaffold(
      appBar: AppBar(title: const Text('Empresa e comprovante')),
      drawer: const AppMainDrawer(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          const AppPageHeader(
            title: 'Empresa e comprovante',
            subtitle: 'Essas informações aparecem nos comprovantes e recibos.',
            badgeLabel: 'Sistema',
            badgeIcon: Icons.storefront_rounded,
            emphasized: true,
          ),
          const SizedBox(height: 18),
          if (settingsAsync.isLoading && _loadedCompanyKey == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            if (settingsAsync.hasError) ...[
              _MessageCard(
                title: 'Não foi possível carregar os dados remotos',
                message: _friendlyError(settingsAsync.error),
                icon: Icons.cloud_off_rounded,
              ),
              const SizedBox(height: 18),
            ],
            if (!canEdit) ...[
              const _MessageCard(
                title: 'Sem permissão para editar',
                message:
                    'Somente o dono/administrador pode alterar dados da empresa.',
                icon: Icons.lock_outline_rounded,
              ),
              const SizedBox(height: 18),
            ],
            AppSectionCard(
              title: 'Dados exibidos no recibo',
              subtitle: 'Conteúdo comercial usado no cabeçalho do comprovante.',
              child: Column(
                children: [
                  _TextField(
                    controller: _displayNameController,
                    label: 'Nome no comprovante',
                    hintText: company.displayName,
                    enabled: canEdit,
                  ),
                  const SizedBox(height: 12),
                  _ToggleTextField(
                    controller: _documentController,
                    label: 'CPF/CNPJ',
                    enabled: canEdit,
                    visible: _showDocument,
                    onVisibleChanged: (value) {
                      setState(() => _showDocument = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  _ToggleTextField(
                    controller: _phoneController,
                    label: 'Telefone/WhatsApp',
                    enabled: canEdit,
                    keyboardType: TextInputType.phone,
                    visible: _showPhone,
                    onVisibleChanged: (value) {
                      setState(() => _showPhone = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  _ToggleTextField(
                    controller: _addressController,
                    label: 'Endereço',
                    enabled: canEdit,
                    visible: _showAddress,
                    onVisibleChanged: (value) {
                      setState(() => _showAddress = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  _ToggleTextField(
                    controller: _footerController,
                    label: 'Mensagem no rodapé',
                    enabled: canEdit,
                    maxLength: _footerLimit,
                    maxLines: 2,
                    visible: _showFooter,
                    onVisibleChanged: (value) {
                      setState(() => _showFooter = value);
                    },
                  ),
                  const SizedBox(height: 14),
                  AppButton.primary(
                    label: controllerState.isLoading
                        ? 'Salvando...'
                        : 'Salvar alterações',
                    icon: Icons.save_outlined,
                    onPressed: canSave ? _save : null,
                    expand: true,
                  ),
                  const SizedBox(height: 10),
                  AppButton.secondary(
                    label: 'Pré-visualizar comprovante',
                    icon: Icons.receipt_long_rounded,
                    onPressed: () => _showReceiptPreview(context, company),
                    expand: true,
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          AppSectionCard(
            title: 'Plano e acesso',
            subtitle:
                'O plano atual define quais recursos ficam disponíveis no app.',
            child: Column(
              children: [
                _InfoRow(label: 'Plano', value: company.licensePlanLabel),
                _InfoRow(label: 'Status', value: company.licenseStatusLabel),
                _InfoRow(
                  label: 'Validade',
                  value: company.licenseExpiresAt == null
                      ? 'Não informada'
                      : AppFormatters.shortDate(company.licenseExpiresAt!),
                ),
                _InfoRow(
                  label: 'Dispositivos',
                  value: '${company.limits.maxDevices}',
                ),
                _InfoRow(
                  label: 'Funcionários',
                  value: '${company.limits.maxEmployees}',
                ),
                const SizedBox(height: 10),
                AppButton.primary(
                  label: 'Assinatura e planos',
                  icon: Icons.workspace_premium_outlined,
                  onPressed: () => context.goNamed(AppRouteNames.subscription),
                  expand: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _applyCompany(CompanyContext company) {
    final key = [
      company.remoteId,
      company.displayName,
      company.documentNumber,
      company.receiptSettings.receiptDisplayName,
      company.receiptSettings.receiptDocument,
      company.receiptSettings.receiptPhone,
      company.receiptSettings.receiptAddress,
      company.receiptSettings.receiptFooterMessage,
      company.receiptSettings.showDocumentOnReceipt,
      company.receiptSettings.showPhoneOnReceipt,
      company.receiptSettings.showAddressOnReceipt,
      company.receiptSettings.showFooterMessageOnReceipt,
    ].join('|');
    if (_loadedCompanyKey == key) {
      return;
    }
    _loadedCompanyKey = key;
    final draft = CompanyReceiptSettingsDraft.fromCompany(company);
    _applyingCompany = true;
    _displayNameController.text = draft.receiptDisplayName ?? '';
    _documentController.text = draft.receiptDocument ?? '';
    _phoneController.text = draft.receiptPhone ?? '';
    _addressController.text = draft.receiptAddress ?? '';
    _footerController.text = draft.receiptFooterMessage ?? '';
    _applyingCompany = false;
    _showDocument = draft.showDocumentOnReceipt;
    _showPhone = draft.showPhoneOnReceipt;
    _showAddress = draft.showAddressOnReceipt;
    _showFooter = draft.showFooterMessageOnReceipt;
  }

  Future<void> _save() async {
    try {
      await ref
          .read(companyReceiptSettingsControllerProvider.notifier)
          .save(_buildDraft());
      if (mounted) {
        AppFeedback.success(context, 'Dados do comprovante salvos.');
      }
    } catch (error) {
      if (mounted) {
        AppFeedback.error(context, _friendlyError(error));
      }
    }
  }

  CompanyReceiptSettingsDraft _buildDraft() {
    return CompanyReceiptSettingsDraft(
      receiptDisplayName: _clean(_displayNameController.text),
      receiptDocument: _clean(_documentController.text),
      receiptPhone: _clean(_phoneController.text),
      receiptAddress: _clean(_addressController.text),
      receiptFooterMessage: _clean(_footerController.text),
      showDocumentOnReceipt: _showDocument,
      showPhoneOnReceipt: _showPhone,
      showAddressOnReceipt: _showAddress,
      showFooterMessageOnReceipt: _showFooter,
    );
  }

  void _showReceiptPreview(BuildContext context, CompanyContext company) {
    final draft = _buildDraft();
    final settings = CompanyReceiptSettings(
      receiptDisplayName: draft.receiptDisplayName,
      receiptDocument: draft.receiptDocument,
      receiptPhone: draft.receiptPhone,
      receiptAddress: draft.receiptAddress,
      receiptFooterMessage: draft.receiptFooterMessage,
      showDocumentOnReceipt: draft.showDocumentOnReceipt,
      showPhoneOnReceipt: draft.showPhoneOnReceipt,
      showAddressOnReceipt: draft.showAddressOnReceipt,
      showFooterMessageOnReceipt: draft.showFooterMessageOnReceipt,
    );
    final receipt = CommercialReceipt(
      type: CommercialReceiptType.cashSale,
      identifier: 'PREVIA',
      issuedAt: DateTime.now(),
      businessName: settings.displayNameOrFallback(company.displayName),
      businessDetails: _businessDetails(settings),
      title: CommercialReceiptType.cashSale.title,
      statusLabel: 'Prévia',
      paymentMethodLabel: 'Dinheiro',
      operationDetails: const [
        CommercialReceiptDetailLine(label: 'Cupom', value: 'PREVIA'),
        CommercialReceiptDetailLine(label: 'Operação', value: 'Venda à vista'),
        CommercialReceiptDetailLine(
          label: 'Cliente',
          value: 'Cliente não informado',
        ),
      ],
      items: const [
        CommercialReceiptItem(
          title: 'Item de exemplo',
          supportingLines: [],
          quantityLabel: '1 un',
          unitPriceCents: 1290,
          subtotalCents: 1290,
        ),
      ],
      extraDetails: const [],
      subtotalCents: 1290,
      discountCents: 0,
      surchargeCents: 0,
      totalCents: 1290,
      subtotalLabel: 'Subtotal',
      totalLabel: 'Total final',
      footerMessage: settings.footerOrFallback(
        'Comprovante gerado com base nos dados atuais da empresa.',
      ),
    );

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.92,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
                child: Row(
                  children: [
                    Text(
                      'Prévia do comprovante',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Fechar',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(child: CommercialReceiptView(receipt: receipt)),
            ],
          ),
        );
      },
    );
  }

  List<CommercialReceiptDetailLine> _businessDetails(
    CompanyReceiptSettings settings,
  ) {
    final details = <CommercialReceiptDetailLine>[];
    void add({
      required bool visible,
      required String label,
      required String? value,
    }) {
      final normalized = value?.trim();
      if (!visible || normalized == null || normalized.isEmpty) {
        return;
      }
      details.add(CommercialReceiptDetailLine(label: label, value: normalized));
    }

    add(
      visible: settings.showDocumentOnReceipt,
      label: 'CPF/CNPJ',
      value: settings.receiptDocument,
    );
    add(
      visible: settings.showPhoneOnReceipt,
      label: 'Telefone/WhatsApp',
      value: settings.receiptPhone,
    );
    add(
      visible: settings.showAddressOnReceipt,
      label: 'Endereço',
      value: settings.receiptAddress,
    );
    return details;
  }

  bool _canEditCompany(AppSession session) {
    final role = session.membership?.role.trim().toUpperCase();
    return session.isRemoteAuthenticated &&
        (role == 'OWNER' || role == 'ADMIN');
  }

  String? _clean(String value) {
    final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    return normalized.isEmpty ? null : normalized;
  }

  String _friendlyError(Object? error) {
    if (error is AppException) {
      return error.message;
    }
    return 'Não foi possível carregar os dados da empresa agora.';
  }
}

class _TextField extends StatelessWidget {
  const _TextField({
    required this.controller,
    required this.label,
    required this.enabled,
    this.hintText,
    this.keyboardType,
    this.maxLength,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final bool enabled;
  final String? hintText;
  final TextInputType? keyboardType;
  final int? maxLength;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      maxLength: maxLength,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        border: const OutlineInputBorder(),
        counterText: maxLength == null
            ? null
            : '${controller.text.characters.length}/$maxLength',
      ),
    );
  }
}

class _ToggleTextField extends StatelessWidget {
  const _ToggleTextField({
    required this.controller,
    required this.label,
    required this.enabled,
    required this.visible,
    required this.onVisibleChanged,
    this.keyboardType,
    this.maxLength,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final bool enabled;
  final bool visible;
  final ValueChanged<bool> onVisibleChanged;
  final TextInputType? keyboardType;
  final int? maxLength;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _TextField(
          controller: controller,
          label: label,
          enabled: enabled,
          keyboardType: keyboardType,
          maxLength: maxLength,
          maxLines: maxLines,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('Mostrar $label no comprovante'),
          value: visible,
          onChanged: enabled ? onVisibleChanged : null,
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.title,
    required this.message,
    required this.icon,
  });

  final String title;
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(message),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
