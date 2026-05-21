import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/owner_auth_controller.dart';
import '../../../core/auth/owner_providers.dart';
import '../../../core/models/owner_models.dart';
import '../../../core/widgets/owner_async_view.dart';
import '../../../core/widgets/owner_formatters.dart';
import '../../../core/widgets/owner_management_widgets.dart';

class OwnerCompanyPage extends ConsumerWidget {
  const OwnerCompanyPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final company = ref.watch(ownerCompanyProvider);
    return OwnerAsyncView(
      value: company,
      onRetry: () => ref.invalidate(ownerCompanyProvider),
      builder: (data) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OwnerPageIntro(
              title: data.name,
              subtitle:
                  'Gerencie dados comerciais exibidos no comprovante da empresa.',
              icon: Icons.storefront_rounded,
              trailing: FilledButton.icon(
                onPressed: () => _editReceipt(context, ref, data),
                icon: const Icon(Icons.edit_note_rounded),
                label: const Text('Editar comprovante'),
              ),
            ),
            const SizedBox(height: 18),
            OwnerSectionCard(
              title: 'Dados da empresa',
              subtitle: 'Resumo comercial e assinatura.',
              child: Wrap(
                spacing: 24,
                runSpacing: 14,
                children: [
                  _InfoItem(label: 'Nome', value: data.name),
                  _InfoItem(label: 'Razao social', value: data.legalName),
                  _InfoItem(
                    label: 'CPF/CNPJ',
                    value: data.documentNumber ?? 'Nao informado',
                  ),
                  _InfoItem(label: 'Dono', value: data.owner.name),
                  _InfoItem(label: 'E-mail do dono', value: data.owner.email),
                  _InfoItem(
                    label: 'Plano',
                    value: ownerPlanLabel(data.license.plan),
                  ),
                  _InfoItem(
                    label: 'Status da licenca',
                    value: OwnerFormatters.status(data.license.status),
                  ),
                  _InfoItem(
                    label: 'Proxima cobranca',
                    value: OwnerFormatters.date(data.license.nextPaymentDate),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              crossAxisAlignment: WrapCrossAlignment.start,
              children: [
                SizedBox(
                  width: 560,
                  child: OwnerSectionCard(
                    title: 'Empresa e comprovante',
                    subtitle: 'Configuracao atual exibida no recibo.',
                    child: Wrap(
                      spacing: 24,
                      runSpacing: 14,
                      children: [
                        _InfoItem(
                          label: 'Nome no comprovante',
                          value: data.receiptSettings.displayName ?? data.name,
                        ),
                        _InfoItem(
                          label: 'Documento',
                          value: _visibleReceiptValue(
                            data.receiptSettings.showDocument,
                            data.receiptSettings.document,
                          ),
                        ),
                        _InfoItem(
                          label: 'Telefone',
                          value: _visibleReceiptValue(
                            data.receiptSettings.showPhone,
                            data.receiptSettings.phone,
                          ),
                        ),
                        _InfoItem(
                          label: 'Endereco',
                          value: _visibleReceiptValue(
                            data.receiptSettings.showAddress,
                            data.receiptSettings.address,
                          ),
                        ),
                        _InfoItem(
                          label: 'Rodape',
                          value: _visibleReceiptValue(
                            data.receiptSettings.showFooterMessage,
                            data.receiptSettings.footerMessage,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: 360,
                  child: _ReceiptPreview(
                    companyName: data.name,
                    settings: data.receiptSettings,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

Future<void> _editReceipt(
  BuildContext context,
  WidgetRef ref,
  OwnerCompanySummary company,
) async {
  final result = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (_) => _ReceiptDialog(settings: company.receiptSettings),
  );
  if (result == null) {
    return;
  }
  try {
    await ref.read(ownerApiServiceProvider).updateReceiptSettings(body: result);
    ref.invalidate(ownerCompanyProvider);
    ref.invalidate(ownerReceiptSettingsProvider);
    ref.read(ownerRefreshTickProvider.notifier).state++;
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Comprovante atualizado.')));
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(describeOwnerError(error))));
    }
  }
}

class _ReceiptDialog extends StatefulWidget {
  const _ReceiptDialog({required this.settings});

  final OwnerReceiptSettings settings;

  @override
  State<_ReceiptDialog> createState() => _ReceiptDialogState();
}

class _ReceiptDialogState extends State<_ReceiptDialog> {
  late final TextEditingController _displayName;
  late final TextEditingController _document;
  late final TextEditingController _phone;
  late final TextEditingController _address;
  late final TextEditingController _footer;
  late bool _showDocument;
  late bool _showPhone;
  late bool _showAddress;
  late bool _showFooter;

  @override
  void initState() {
    super.initState();
    final settings = widget.settings;
    _displayName = TextEditingController(text: settings.displayName ?? '');
    _document = TextEditingController(text: settings.document ?? '');
    _phone = TextEditingController(text: settings.phone ?? '');
    _address = TextEditingController(text: settings.address ?? '');
    _footer = TextEditingController(text: settings.footerMessage ?? '');
    _showDocument = settings.showDocument;
    _showPhone = settings.showPhone;
    _showAddress = settings.showAddress;
    _showFooter = settings.showFooterMessage;
  }

  @override
  void dispose() {
    _displayName.dispose();
    _document.dispose();
    _phone.dispose();
    _address.dispose();
    _footer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Editar comprovante'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _displayName,
                decoration: const InputDecoration(
                  labelText: 'Nome no comprovante',
                ),
              ),
              TextField(
                controller: _document,
                decoration: const InputDecoration(labelText: 'CPF/CNPJ'),
              ),
              TextField(
                controller: _phone,
                decoration: const InputDecoration(
                  labelText: 'Telefone/WhatsApp',
                ),
              ),
              TextField(
                controller: _address,
                decoration: const InputDecoration(labelText: 'Endereco'),
              ),
              TextField(
                controller: _footer,
                decoration: const InputDecoration(
                  labelText: 'Mensagem do rodape',
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Mostrar documento'),
                value: _showDocument,
                onChanged: (value) => setState(() => _showDocument = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Mostrar telefone'),
                value: _showPhone,
                onChanged: (value) => setState(() => _showPhone = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Mostrar endereco'),
                value: _showAddress,
                onChanged: (value) => setState(() => _showAddress = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Mostrar rodape'),
                value: _showFooter,
                onChanged: (value) => setState(() => _showFooter = value),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(<String, dynamic>{
            'receiptDisplayName': _emptyToNull(_displayName.text),
            'receiptDocument': _emptyToNull(_document.text),
            'receiptPhone': _emptyToNull(_phone.text),
            'receiptAddress': _emptyToNull(_address.text),
            'receiptFooterMessage': _emptyToNull(_footer.text),
            'showDocumentOnReceipt': _showDocument,
            'showPhoneOnReceipt': _showPhone,
            'showAddressOnReceipt': _showAddress,
            'showFooterMessageOnReceipt': _showFooter,
          }),
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}

class _ReceiptPreview extends StatelessWidget {
  const _ReceiptPreview({required this.companyName, required this.settings});

  final String companyName;
  final OwnerReceiptSettings settings;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return OwnerSectionCard(
      title: 'Preview do comprovante',
      subtitle: 'Visual simples para conferencia rapida.',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              settings.displayName ?? companyName,
              textAlign: TextAlign.center,
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            if (settings.showDocument && settings.document != null)
              Text(settings.document!, textAlign: TextAlign.center),
            if (settings.showPhone && settings.phone != null)
              Text(settings.phone!, textAlign: TextAlign.center),
            if (settings.showAddress && settings.address != null)
              Text(settings.address!, textAlign: TextAlign.center),
            const Divider(height: 28),
            const Text(
              'Dados comerciais exibidos no cabecalho do comprovante.',
              textAlign: TextAlign.center,
            ),
            if (settings.showFooterMessage &&
                settings.footerMessage != null) ...[
              const SizedBox(height: 12),
              Text(settings.footerMessage!, textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoItem extends StatelessWidget {
  const _InfoItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

String? _emptyToNull(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String _visibleReceiptValue(bool visible, String? value) {
  if (!visible) {
    return 'Oculto';
  }
  return value == null || value.trim().isEmpty ? 'Nao informado' : value;
}
