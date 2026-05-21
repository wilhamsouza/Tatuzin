import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/owner_providers.dart';
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
              subtitle: 'Resumo da empresa, assinatura e dados de comprovante.',
              icon: Icons.storefront_rounded,
              trailing: Chip(
                label: Text('Plano ${ownerPlanLabel(data.license.plan)}'),
              ),
            ),
            const SizedBox(height: 18),
            OwnerSectionCard(
              title: 'Dados da empresa',
              subtitle: 'Informacoes disponiveis para consulta.',
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
                    label: 'Status da licenca',
                    value: OwnerFormatters.status(data.license.status),
                  ),
                  _InfoItem(
                    label: 'Proxima cobranca',
                    value: OwnerFormatters.date(data.license.nextPaymentDate),
                  ),
                  _InfoItem(
                    label: 'Criada em',
                    value: OwnerFormatters.date(data.createdAt),
                  ),
                  _InfoItem(
                    label: 'Funcionarios no plano',
                    value: '${data.limits.maxEmployees}',
                  ),
                  _InfoItem(
                    label: 'Dispositivos no plano',
                    value: '${data.limits.maxDevices}',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            OwnerSectionCard(
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
          ],
        );
      },
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

String _visibleReceiptValue(bool visible, String? value) {
  if (!visible) {
    return 'Oculto';
  }
  return value == null || value.trim().isEmpty ? 'Nao informado' : value;
}
