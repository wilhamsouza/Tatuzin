import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/owner_providers.dart';
import '../../../core/models/owner_models.dart';
import '../../../core/widgets/owner_management_widgets.dart';

class OwnerCashPolicyCard extends ConsumerStatefulWidget {
  const OwnerCashPolicyCard({super.key, required this.company});
  final OwnerCompanySummary company;

  @override
  ConsumerState<OwnerCashPolicyCard> createState() =>
      _OwnerCashPolicyCardState();
}

class _OwnerCashPolicyCardState extends ConsumerState<OwnerCashPolicyCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) => OwnerSectionCard(
    title: 'Política de caixa',
    subtitle:
        'Conferência da contagem no aplicativo • Revisão ${widget.company.cashPolicyRevision}',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Conferência cega no fechamento'),
          subtitle: const Text(
            'O operador informa a contagem antes de ver o saldo esperado. Os relatórios gerenciais continuam disponíveis.',
          ),
          value: widget.company.cashBlindClosureEnabled,
          onChanged: widget.company.canManageCashPolicy && !_busy
              ? _confirm
              : null,
        ),
        const SizedBox(height: 8),
        const Text(
          'Aplica-se às novas aberturas após o aplicativo atualizar a política. Sessões já abertas preservam sua regra. Dispositivos antigos podem não aplicar a conferência cega; atualize os aplicativos. Esta opção não bloqueia todo acesso do operador aos valores.',
        ),
        if (!widget.company.canManageCashPolicy)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Seu acesso permite consultar esta política.'),
          ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(
              semanticsLabel: 'Salvando política de caixa',
            ),
          ),
      ],
    ),
  );

  Future<void> _confirm(bool enabled) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          enabled ? 'Ativar conferência cega?' : 'Desativar conferência cega?',
        ),
        content: const Text(
          'A alteração valerá para novas sessões após a atualização da política no aplicativo. Caixas já abertos mantêm a política original.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirmar alteração'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(ownerApiServiceProvider)
          .updateCashPolicy(blindClosureEnabled: enabled);
      ref.invalidate(ownerCompanyProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Política de caixa atualizada.')),
        );
      }
    } on OwnerApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
