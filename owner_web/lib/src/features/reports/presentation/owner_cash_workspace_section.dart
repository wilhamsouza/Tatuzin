import 'package:flutter/material.dart';

import '../../../core/models/owner_models.dart';
import '../../../core/widgets/owner_formatters.dart';
import '../../../core/widgets/owner_management_widgets.dart';

String _money(int? cents) =>
    cents == null ? 'Indisponível' : OwnerFormatters.moneyFromCents(cents);

class OwnerCashWorkspaceSection extends StatelessWidget {
  const OwnerCashWorkspaceSection({
    super.key,
    required this.workspace,
    required this.onSessionSelected,
    required this.onRefresh,
  });
  final OwnerCashWorkspace workspace;
  final ValueChanged<String> onSessionSelected;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final summary = workspace.summary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OwnerSectionCard(
          title: 'Caixa geral da empresa',
          subtitle:
              'Consolidado na nuvem por funcionário. Cada responsável compartilha seu próprio caixa entre aparelhos; outros funcionários mantêm caixas separados.',
          trailing: OutlinedButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.sync),
            label: const Text('Atualizar caixa geral'),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  OwnerMetricCard(
                    title: 'Funcionários com caixa aberto',
                    value: summary.openEmployees?.toString() ?? '—',
                    detail: 'Caixas independentes por responsável',
                    icon: Icons.badge_outlined,
                    isAvailable: summary.openEmployees != null,
                  ),
                  OwnerMetricCard(
                    title: 'Conferências pendentes',
                    value: summary.pendingEmployees?.toString() ?? '—',
                    detail: 'Aguardam envio ou revisão no aplicativo',
                    icon: Icons.cloud_sync_outlined,
                    isAvailable: summary.pendingEmployees != null,
                  ),
                  OwnerMetricCard(
                    title: 'Saldo sincronizado',
                    value: _money(summary.totalExpectedBalanceCents),
                    detail: 'Movimentos já recebidos na nuvem',
                    icon: Icons.cloud_done_outlined,
                    isAvailable: summary.totalExpectedBalanceCents != null,
                  ),
                  OwnerMetricCard(
                    title: 'Contagem confirmada',
                    value: _money(summary.confirmedCountedBalanceCents),
                    detail: 'Último fechamento confirmado por funcionário',
                    icon: Icons.fact_check_outlined,
                    isAvailable: summary.confirmedCountedBalanceCents != null,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Uma contagem enviada offline continua pendente até os aparelhos participantes sincronizarem. Se o saldo mudar, o responsável precisa reconferir no aplicativo. Valores declarados pendentes não compõem a contagem confirmada.',
              ),
              if (workspace.legacySessionsPresent) ...[
                const SizedBox(height: 12),
                Text(
                  'Histórico anterior: ${summary.legacySessions?.toString() ?? 'há'} sessões legadas disponíveis abaixo. Seus fundos não são somados ao caixa geral por funcionário.',
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        OwnerSectionCard(
          title: 'Caixas por funcionário',
          subtitle:
              'Situação atual de cada responsável, com os aparelhos participantes da mesma sessão.',
          child: workspace.employees.isEmpty
              ? const OwnerEmptyState(
                  title: 'Nenhum caixa por funcionário sincronizado',
                  message:
                      'As novas sessões aparecerão após o aplicativo sincronizar. O histórico anterior continua disponível abaixo.',
                  icon: Icons.cloud_queue,
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final table =
                        constraints.maxWidth >= 900 &&
                        MediaQuery.textScalerOf(context).scale(14) <= 21;
                    if (table) {
                      return SizedBox(
                        width: double.infinity,
                        child: DataTable(
                          columnSpacing: 16,
                          horizontalMargin: 8,
                          columns: const [
                            DataColumn(label: Text('Responsável')),
                            DataColumn(label: Text('Situação')),
                            DataColumn(
                              label: Text('Saldo na nuvem'),
                              numeric: true,
                            ),
                            DataColumn(label: Text('Declarado'), numeric: true),
                            DataColumn(label: Text('Participantes')),
                          ],
                          rows: [
                            for (final employee in workspace.employees)
                              DataRow(
                                cells: [
                                  DataCell(
                                    SizedBox(
                                      width: 150,
                                      child: Text(employee.employee.name),
                                    ),
                                  ),
                                  DataCell(
                                    SizedBox(
                                      width: 150,
                                      child: Text(employee.statusLabel),
                                    ),
                                  ),
                                  DataCell(
                                    Text(_money(employee.expectedBalanceCents)),
                                  ),
                                  DataCell(
                                    Text(_money(employee.countedBalanceCents)),
                                  ),
                                  DataCell(
                                    TextButton(
                                      onPressed: () => showDialog<void>(
                                        context: context,
                                        builder: (dialogContext) => AlertDialog(
                                          scrollable: true,
                                          title: Text(employee.employee.name),
                                          content: SizedBox(
                                            width: 480,
                                            child: _EmployeeCashFacts(
                                              employee: employee,
                                              onSessionSelected: (id) {
                                                Navigator.of(
                                                  dialogContext,
                                                ).pop();
                                                onSessionSelected(id);
                                              },
                                            ),
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.of(
                                                dialogContext,
                                              ).pop(),
                                              child: const Text('Fechar'),
                                            ),
                                          ],
                                        ),
                                      ),
                                      child: Text(
                                        '${employee.participants.length} ${employee.participants.length == 1 ? 'aparelho' : 'aparelhos'} • Consultar',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      );
                    }
                    return Column(
                      children: [
                        for (final employee in workspace.employees)
                          Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ExpansionTile(
                              key: PageStorageKey(
                                'employee-cash-${employee.employee.id}',
                              ),
                              tilePadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              title: Text(
                                employee.employee.name,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              subtitle: Text(employee.statusLabel),
                              childrenPadding: const EdgeInsets.fromLTRB(
                                16,
                                0,
                                16,
                                16,
                              ),
                              children: [
                                _EmployeeCashFacts(
                                  employee: employee,
                                  onSessionSelected: onSessionSelected,
                                ),
                              ],
                            ),
                          ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _EmployeeCashFacts extends StatelessWidget {
  const _EmployeeCashFacts({
    required this.employee,
    required this.onSessionSelected,
  });
  final OwnerEmployeeCashWorkspace employee;
  final ValueChanged<String> onSessionSelected;

  @override
  Widget build(BuildContext context) {
    final generation = employee.closureRequest['generation'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Saldo sincronizado: ${_money(employee.expectedBalanceCents)}'),
        Text(
          '${employee.isPending ? 'Declarado • conferência pendente' : 'Contagem declarada'}: ${_money(employee.countedBalanceCents)}',
        ),
        if (employee.status == 'CLOSED')
          Text('Diferença confirmada: ${_money(employee.differenceCents)}'),
        for (final reason in employee.pendingReasons)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Semantics(
              liveRegion: true,
              child: Text(switch (reason) {
                'AWAITING_PARTICIPANT_SYNC' =>
                  'Fechamento ainda não confirmado: aguardando sincronização dos aparelhos participantes.',
                'BALANCE_CHANGED_RECONFIRM_REQUIRED' =>
                  'O saldo mudou após a contagem. O responsável precisa reconferir no aplicativo.',
                _ =>
                  'Há uma pendência de conferência. Consulte o aplicativo do responsável.',
              }),
            ),
          ),
        const SizedBox(height: 12),
        Text(
          'Aparelhos participantes',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        if (employee.participants.isEmpty)
          const Text('Nenhum aparelho participante informado.'),
        for (final participant in employee.participants)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${participant.name}\n${generation is num
                  ? participant.lastAckGeneration == generation
                        ? 'Envio confirmado para esta conferência'
                        : 'Aguardando envio para esta conferência'
                  : 'Participa do caixa deste responsável'}',
            ),
          ),
        if (employee.detailSessionId != null) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => onSessionSelected(employee.detailSessionId!),
            icon: const Icon(Icons.visibility_outlined),
            label: const Text('Consultar sessão e histórico'),
          ),
        ],
      ],
    );
  }
}
