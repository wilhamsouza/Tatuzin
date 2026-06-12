import 'package:flutter/material.dart';

import '../session/tenant_operational_block.dart';

class TenantPendingDeletionPage extends StatelessWidget {
  const TenantPendingDeletionPage({
    required this.block,
    required this.onAcknowledge,
    super.key,
  });

  final TenantOperationalBlock block;
  final VoidCallback onAcknowledge;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final companyName = block.companyName?.trim();

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.lock_clock_outlined,
                        size: 44,
                        color: colorScheme.error,
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Empresa em processo de exclusao',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      if (companyName != null && companyName.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          companyName,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                      const SizedBox(height: 16),
                      const Text(
                        'O acesso operacional desta empresa e a sincronizacao '
                        'foram bloqueados. Nao e possivel registrar novas '
                        'operacoes enquanto a solicitacao estiver em andamento.',
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Os dados locais deste dispositivo nao foram apagados '
                        'automaticamente. A remocao do app ou dos dados do app '
                        'deve ser feita somente depois da conclusao do processo '
                        'e conforme as orientacoes recebidas.',
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Aguarde a validacao e o tratamento da solicitacao. '
                        'Dados podem ser excluidos, anonimizados, desativados '
                        'ou retidos quando houver justificativa legal, de '
                        'seguranca ou auditoria.',
                      ),
                      const SizedBox(height: 24),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton(
                          key: const Key('tenant-pending-deletion-acknowledge'),
                          onPressed: onAcknowledge,
                          child: const Text('Entendi'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
