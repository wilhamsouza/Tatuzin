import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/utils/money_parser.dart';
import '../../../../app/core/widgets/app_main_drawer.dart';
import '../../../../app/core/widgets/app_metric_card.dart';
import '../../../../app/core/widgets/app_page_header.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import '../../../../app/core/widgets/app_status_badge.dart';
import '../../../../app/routes/route_names.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../dashboard/presentation/providers/dashboard_providers.dart';
import '../../../vendas/domain/entities/sale_enums.dart';
import '../../domain/entities/cash_enums.dart';
import '../../domain/entities/cash_manual_movement_input.dart';
import '../../domain/entities/cash_movement.dart';
import '../../domain/entities/cash_session.dart';
import '../providers/cash_providers.dart';
import '../widgets/cash_session_detail_sheet.dart';

class CashPage extends ConsumerWidget {
  const CashPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentSessionAsync = ref.watch(currentCashSessionProvider);
    final movementsAsync = ref.watch(currentCashMovementsProvider);
    final sessionsAsync = ref.watch(cashSessionHistoryProvider);
    final actionState = ref.watch(cashActionControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Caixa')),
      drawer: const AppMainDrawer(),
      body: RefreshIndicator(
        onRefresh: () async {
          _invalidateCashProviders(ref);
          await ref.read(currentCashSessionProvider.future);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            const AppPageHeader(
              title: 'Caixa',
              subtitle:
                  'Acompanhe a sessão atual, entradas, saídas e movimentos com clareza operacional.',
              badgeLabel: 'Financeiro local',
              badgeIcon: Icons.account_balance_wallet_rounded,
            ),
            const SizedBox(height: 16),
            currentSessionAsync.when(
              data: (session) => _SessionOverviewSection(
                session: session,
                isBusy: actionState.isLoading,
                onOpen: () => _openSession(context, ref),
                onClose: () => _closeSession(context, ref),
                onSupply: () => _registerMovement(
                  context,
                  ref,
                  type: CashMovementType.supply,
                ),
                onWithdraw: () => _registerMovement(
                  context,
                  ref,
                  type: CashMovementType.sangria,
                ),
                onCount: () => context.pushNamed(AppRouteNames.cashCount),
              ),
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => AppSectionCard(
                title: 'Falha ao carregar caixa',
                subtitle: error.toString(),
                child: FilledButton.tonal(
                  onPressed: () => _invalidateCashProviders(ref),
                  child: const Text('Tentar novamente'),
                ),
              ),
            ),
            if (actionState.hasError) ...[
              const SizedBox(height: 16),
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    actionState.error.toString(),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            AppSectionCard(
              title: 'Movimentações recentes',
              subtitle: 'Últimas entradas e saídas da sessão atual.',
              child: movementsAsync.when(
                data: (movements) {
                  if (movements.isEmpty) {
                    return const Text(
                      'Nenhum movimento registrado na sessão atual.',
                    );
                  }

                  return Column(
                    children: [
                      for (final movement in movements.take(6)) ...[
                        _MovementTile(movement: movement),
                        const SizedBox(height: 12),
                      ],
                    ],
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) =>
                    Text('Falha ao carregar movimentações: $error'),
              ),
            ),
            const SizedBox(height: 16),
            AppSectionCard(
              title: 'Histórico de sessões',
              subtitle: 'Resumo das últimas aberturas e fechamentos.',
              child: sessionsAsync.when(
                data: (sessions) {
                  if (sessions.isEmpty) {
                    return const Text('Nenhuma sessão registrada ainda.');
                  }

                  return Column(
                    children: [
                      for (final session in sessions.take(8)) ...[
                        _SessionHistoryTile(
                          session: session,
                          onTap: () => _showSessionDetail(context, session),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) =>
                    Text('Falha ao carregar histórico: $error'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openSession(BuildContext context, WidgetRef ref) async {
    final amountController = TextEditingController();
    final notesController = TextEditingController();

    final submitted = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Abrir caixa'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Troco inicial'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(
                    labelText: 'Observação',
                    hintText: 'Opcional',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop({
                'amount': amountController.text,
                'notes': notesController.text,
              }),
              child: const Text('Abrir'),
            ),
          ],
        );
      },
    );

    amountController.dispose();
    notesController.dispose();

    if (submitted == null) {
      return;
    }

    try {
      await ref
          .read(cashActionControllerProvider.notifier)
          .openSession(
            initialFloatCents: MoneyParser.parseToCents(
              submitted['amount'] ?? '',
            ),
            notes: submitted['notes'],
          );
      _invalidateCashProviders(ref);

      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Caixa aberto com sucesso.')),
      );
    } catch (_) {
      if (!context.mounted) {
        return;
      }
    }
  }

  Future<void> _closeSession(BuildContext context, WidgetRef ref) async {
    final notesController = TextEditingController();
    final notes = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Fechar caixa'),
          content: TextField(
            controller: notesController,
            decoration: const InputDecoration(
              labelText: 'Observação de fechamento',
              hintText: 'Opcional',
            ),
            maxLines: 3,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(notesController.text),
              child: const Text('Fechar caixa'),
            ),
          ],
        );
      },
    );
    notesController.dispose();

    if (notes == null) {
      return;
    }

    try {
      await ref
          .read(cashActionControllerProvider.notifier)
          .closeSession(notes: notes);
      _invalidateCashProviders(ref);

      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Caixa fechado com sucesso.')),
      );
    } catch (_) {
      if (!context.mounted) {
        return;
      }
    }
  }

  Future<void> _registerMovement(
    BuildContext context,
    WidgetRef ref, {
    required CashMovementType type,
  }) async {
    final amountController = TextEditingController();
    final descriptionController = TextEditingController();

    final submitted = await showDialog<CashManualMovementInput>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            type == CashMovementType.supply ? 'Suprimento' : 'Sangria',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Valor'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descriptionController,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Descrição'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(
                CashManualMovementInput(
                  type: type,
                  amountCents: MoneyParser.parseToCents(amountController.text),
                  description: descriptionController.text.trim(),
                ),
              ),
              child: const Text('Registrar'),
            ),
          ],
        );
      },
    );

    amountController.dispose();
    descriptionController.dispose();

    if (submitted == null) {
      return;
    }

    try {
      await ref
          .read(cashActionControllerProvider.notifier)
          .registerManualMovement(submitted);
      _invalidateCashProviders(ref);

      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Movimento registrado com sucesso.')),
      );
    } catch (_) {
      if (!context.mounted) {
        return;
      }
    }
  }

  Future<void> _showSessionDetail(
    BuildContext context,
    CashSession session,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CashSessionDetailSheet(session: session),
    );
  }

  void _invalidateCashProviders(WidgetRef ref) {
    ref.invalidate(currentCashSessionProvider);
    ref.invalidate(currentCashMovementsProvider);
    ref.invalidate(cashSessionHistoryProvider);
    ref.invalidate(dashboardMetricsProvider);
  }
}

class _SessionOverviewSection extends StatelessWidget {
  const _SessionOverviewSection({
    required this.session,
    required this.isBusy,
    required this.onOpen,
    required this.onClose,
    required this.onSupply,
    required this.onWithdraw,
    required this.onCount,
  });

  final CashSession? session;
  final bool isBusy;
  final VoidCallback onOpen;
  final VoidCallback onClose;
  final VoidCallback onSupply;
  final VoidCallback onWithdraw;
  final VoidCallback onCount;

  @override
  Widget build(BuildContext context) {
    if (session == null) {
      return AppSectionCard(
        title: 'Sessão atual',
        subtitle: 'Nenhum caixa aberto no momento.',
        trailing: const AppStatusBadge(
          label: 'Fechado',
          tone: AppStatusTone.danger,
          icon: Icons.lock_outline,
        ),
        child: FilledButton.icon(
          onPressed: isBusy ? null : onOpen,
          icon: const Icon(Icons.lock_open_outlined),
          label: Text(isBusy ? 'Abrindo...' : 'Abrir caixa'),
        ),
      );
    }

    final current = session!;
    return Column(
      children: [
        AppSectionCard(
          title: 'Sessão atual',
          subtitle:
              'Caixa ${current.isOpen ? 'aberto' : 'fechado'} desde ${AppFormatters.shortDateTime(current.openedAt)}.',
          trailing: AppStatusBadge(
            label: current.status.label,
            tone: current.isOpen
                ? AppStatusTone.success
                : AppStatusTone.neutral,
            icon: current.isOpen ? Icons.lock_open : Icons.lock_outline,
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _InfoLine(
                      label: 'Troco inicial',
                      value: AppFormatters.currencyFromCents(
                        current.initialFloatCents,
                      ),
                    ),
                  ),
                  Expanded(
                    child: _InfoLine(
                      label: 'Abertura',
                      value: AppFormatters.shortDateTime(current.openedAt),
                    ),
                  ),
                ],
              ),
              if (current.notes?.isNotEmpty ?? false) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    current.notes!,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.08,
          children: [
            AppMetricCard(
              label: 'Entradas',
              value: AppFormatters.currencyFromCents(current.totalSalesCents),
              caption: 'Vendas recebidas',
              icon: Icons.arrow_downward_rounded,
              accentColor: AppTheme.success,
            ),
            AppMetricCard(
              label: 'Saídas',
              value: AppFormatters.currencyFromCents(
                current.totalWithdrawalsCents,
              ),
              caption: 'Sangrias e retiradas',
              icon: Icons.arrow_upward_rounded,
              accentColor: AppTheme.warning,
            ),
            AppMetricCard(
              label: 'Fiado recebido',
              value: AppFormatters.currencyFromCents(
                current.totalFiadoReceiptsCents,
              ),
              caption: 'Recebimentos do dia',
              icon: Icons.receipt_long_rounded,
              accentColor: AppTheme.secondary,
            ),
            AppMetricCard(
              label: 'Saldo atual',
              value: AppFormatters.currencyFromCents(current.finalBalanceCents),
              caption: 'Saldo parcial da sessão',
              icon: Icons.account_balance_wallet_rounded,
              accentColor: AppTheme.primary,
            ),
          ],
        ),
        const SizedBox(height: 16),
        AppSectionCard(
          title: 'Ações do caixa',
          subtitle: 'Acesse rapidamente as operações mais frequentes.',
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _ActionButton(
                label: 'Abrir caixa',
                icon: Icons.lock_open_outlined,
                onPressed: current.isOpen || isBusy ? null : onOpen,
              ),
              _ActionButton(
                label: 'Fechar caixa',
                icon: Icons.lock_outline,
                onPressed: current.isOpen && !isBusy ? onClose : null,
              ),
              _ActionButton(
                label: 'Suprimento',
                icon: Icons.add_circle_outline,
                onPressed: current.isOpen && !isBusy ? onSupply : null,
              ),
              _ActionButton(
                label: 'Sangria',
                icon: Icons.remove_circle_outline,
                onPressed: current.isOpen && !isBusy ? onWithdraw : null,
              ),
              _ActionButton(
                label: 'Contagem',
                icon: Icons.calculate_outlined,
                onPressed: onCount,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: (MediaQuery.of(context).size.width - 64) / 2,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
      ),
    );
  }
}

class _MovementTile extends StatelessWidget {
  const _MovementTile({required this.movement});

  final CashMovement movement;

  @override
  Widget build(BuildContext context) {
    final isNegative = movement.amountCents < 0;
    final tone = isNegative ? AppStatusTone.warning : AppStatusTone.success;

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        leading: AppStatusBadge(label: movement.type.label, tone: tone),
        title: Text(
          AppFormatters.currencyFromCents(movement.amountCents),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        subtitle: Text(
          [
            AppFormatters.shortDateTime(movement.createdAt),
            if (movement.paymentMethod != null) movement.paymentMethod!.label,
            if (movement.description?.isNotEmpty ?? false)
              movement.description!,
          ].join(' • '),
        ),
      ),
    );
  }
}

class _SessionHistoryTile extends StatelessWidget {
  const _SessionHistoryTile({
    required this.session,
    required this.onTap,
  });

  final CashSession session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        title: Text(
          session.isOpen ? 'Sessão em aberto' : 'Sessão encerrada',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        subtitle: Text(
          [
            'Abertura ${AppFormatters.shortDateTime(session.openedAt)}',
            if (session.closedAt != null)
              'Fechamento ${AppFormatters.shortDateTime(session.closedAt!)}',
          ].join(' • '),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(AppFormatters.currencyFromCents(session.finalBalanceCents)),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppStatusBadge(
                  label: session.status.label,
                  tone: session.isOpen
                      ? AppStatusTone.success
                      : AppStatusTone.neutral,
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
