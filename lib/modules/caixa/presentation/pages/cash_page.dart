import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/providers/app_data_refresh_provider.dart';
import '../../../../app/core/utils/money_parser.dart';
import '../../../../app/core/widgets/app_card.dart';
import '../../../../app/core/widgets/app_feedback.dart';
import '../../../../app/core/widgets/app_main_drawer.dart';
import '../../../../app/core/widgets/app_page_header.dart';
import '../../../../app/core/widgets/app_selector_chip.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import '../../../../app/core/widgets/app_state_card.dart';
import '../../../../app/core/widgets/app_status_badge.dart';
import '../../../../app/core/widgets/app_summary_block.dart';
import '../../../../app/routes/route_names.dart';
import '../../../../app/theme/app_design_tokens.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../vendas/domain/entities/sale_enums.dart';
import '../../domain/entities/cash_enums.dart';
import '../../domain/entities/cash_manual_movement_input.dart';
import '../../domain/entities/cash_movement.dart';
import '../../domain/entities/cash_session.dart';
import '../providers/cash_providers.dart';
import '../widgets/cash_session_detail_sheet.dart';

class CashPage extends ConsumerStatefulWidget {
  const CashPage({super.key});

  @override
  ConsumerState<CashPage> createState() => _CashPageState();
}

class _CashPageState extends ConsumerState<CashPage> {
  int? _autoDialogSessionId;

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<CashSession?>>(currentCashSessionProvider, (_, next) {
      next.whenData((session) {
        if (!mounted || session == null) {
          _autoDialogSessionId = null;
          return;
        }
        if (!session.awaitingInitialFloatConfirmation ||
            _autoDialogSessionId == session.id) {
          return;
        }
        _autoDialogSessionId = session.id;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showAutoOpenConfirmationDialog(session);
        });
      });
    });

    final currentSessionAsync = ref.watch(currentCashSessionProvider);
    final movementsAsync = ref.watch(currentCashMovementsProvider);
    final sessionsAsync = ref.watch(cashSessionHistoryProvider);
    final visibleMovements = ref.watch(visibleCashMovementsProvider);
    final filteredMovements = ref.watch(filteredCashMovementsProvider);
    final filter = ref.watch(cashMovementFilterProvider);
    final movementCounts = ref.watch(cashMovementCountsProvider);
    final actionState = ref.watch(cashActionControllerProvider);
    final operatorName = ref.watch(currentCashOperatorNameProvider);
    final layout = context.appLayout;

    return Scaffold(
      appBar: AppBar(title: const Text('Caixa')),
      drawer: const AppMainDrawer(),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.read(appDataRefreshProvider.notifier).state++;
          await ref.read(currentCashSessionProvider.future);
        },
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            layout.pagePadding,
            layout.space5,
            layout.pagePadding,
            layout.space10,
          ),
          children: [
            AppPageHeader(
              title: 'Caixa operacional',
              subtitle:
                  'Sessão atual, saldo físico e ações do operador $operatorName.',
              badgeLabel: 'Operação do caixa',
              badgeIcon: Icons.account_balance_wallet_rounded,
            ),
            const SizedBox(height: 14),
            currentSessionAsync.when(
              data: (session) => _CurrentSessionSection(
                session: session,
                updatedAt: _resolveUpdatedAt(session, movementsAsync.value),
                isBusy: actionState.isLoading,
                onOpen: _openSession,
                onConfirmAutomaticOpen: session == null
                    ? null
                    : () => _showAutoOpenConfirmationDialog(session),
                onClose: session == null
                    ? null
                    : () => _startCloseFlow(session),
                onSupply: () => _registerMovement(CashMovementType.supply),
                onWithdraw: () => _registerMovement(CashMovementType.sangria),
                onCount: () => context.pushNamed(AppRouteNames.cashCount),
                onSelectFilter: _selectFilter,
              ),
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => AppSectionCard(
                title: 'Falha ao carregar caixa',
                subtitle: error.toString(),
                child: FilledButton.tonal(
                  onPressed: () =>
                      ref.read(appDataRefreshProvider.notifier).state++,
                  child: const Text('Tentar novamente'),
                ),
              ),
            ),
            if (actionState.hasError) ...[
              SizedBox(height: layout.sectionGap),
              AppStateCard(
                title: 'Falha em uma acao do caixa',
                message: actionState.error.toString(),
                tone: AppStateTone.error,
                compact: true,
              ),
            ],
            SizedBox(height: layout.sectionGap),
            AppSectionCard(
              title: 'Movimentações',
              subtitle:
                  'Mostrando ${visibleMovements.length} movimentações${filteredMovements.length != visibleMovements.length ? ' de ${filteredMovements.length}' : ''}.',
              padding: const EdgeInsets.all(16),
              child: movementsAsync.when(
                data: (_) {
                  if (filteredMovements.isEmpty) {
                    return const Text(
                      'Nenhuma movimentação encontrada para o filtro selecionado.',
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: layout.quickActionHeight + 2,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: CashMovementFilter.values.length,
                          separatorBuilder: (_, __) =>
                              SizedBox(width: layout.space3),
                          itemBuilder: (context, index) {
                            final item = CashMovementFilter.values[index];
                            return AppSelectorChip(
                              label: item.label,
                              count: movementCounts[item] ?? 0,
                              selected: filter == item,
                              tone: AppSelectorChipTone.info,
                              onSelected: (_) => _selectFilter(item),
                            );
                          },
                        ),
                      ),
                      SizedBox(height: layout.blockGap),
                      for (final movement in visibleMovements) ...[
                        _MovementTile(movement: movement),
                        const SizedBox(height: 8),
                      ],
                      if (filteredMovements.length > visibleMovements.length)
                        OutlinedButton.icon(
                          onPressed: () =>
                              ref
                                      .read(
                                        cashMovementVisibleCountProvider
                                            .notifier,
                                      )
                                      .state +=
                                  10,
                          icon: const Icon(Icons.expand_more_rounded),
                          label: const Text('Carregar mais'),
                        ),
                    ],
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) =>
                    Text('Falha ao carregar movimentações: $error'),
              ),
            ),
            SizedBox(height: layout.sectionGap),
            AppSectionCard(
              title: 'Histórico de sessões',
              subtitle: 'Fechamentos recentes e divergências de caixa.',
              padding: const EdgeInsets.all(16),
              child: sessionsAsync.when(
                data: (sessions) {
                  if (sessions.isEmpty) {
                    return const Text('Nenhuma sessão registrada ainda.');
                  }
                  return Column(
                    children: [
                      for (final session in sessions.take(6)) ...[
                        _SessionHistoryTile(
                          session: session,
                          onTap: () => _showSessionDetail(session),
                        ),
                        const SizedBox(height: 8),
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

  DateTime? _resolveUpdatedAt(
    CashSession? session,
    List<CashMovement>? movements,
  ) {
    final providerValue = ref.watch(cashLastUpdatedAtProvider);
    if (providerValue != null) {
      return providerValue;
    }
    if (movements != null && movements.isNotEmpty) {
      return movements.first.createdAt;
    }
    return session?.openedAt;
  }

  void _selectFilter(CashMovementFilter filter) {
    ref.read(cashMovementFilterProvider.notifier).state = filter;
    ref.read(cashMovementVisibleCountProvider.notifier).state = 10;
  }

  Future<void> _openSession() async {
    final amountController = TextEditingController();
    final notesController = TextEditingController();
    final submitted = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
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
                decoration: const InputDecoration(
                  labelText: 'Troco inicial (R\$)',
                ),
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
            child: const Text('Abrir caixa'),
          ),
        ],
      ),
    );
    amountController.dispose();
    notesController.dispose();
    if (submitted == null) return;
    try {
      await ref
          .read(cashActionControllerProvider.notifier)
          .openSession(
            initialFloatCents: MoneyParser.parseToCents(
              submitted['amount'] ?? '',
            ),
            notes: submitted['notes'],
          );
      if (!mounted) return;
      AppFeedback.success(context, 'Caixa aberto com sucesso.');
    } catch (_) {}
  }

  Future<void> _showAutoOpenConfirmationDialog(CashSession session) async {
    final amountController = TextEditingController();
    final result = await showDialog<_AutoOpenResolution>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Abertura automática do caixa'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Informe o troco inicial para iniciar a sessão.'),
            const SizedBox(height: 12),
            TextField(
              controller: amountController,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Troco inicial (R\$)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(
              context,
            ).pop(const _AutoOpenResolution.closeCash()),
            child: const Text('Fechar caixa'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(
              _AutoOpenResolution.confirm(
                MoneyParser.parseToCents(amountController.text),
              ),
            ),
            child: const Text('Confirmar abertura'),
          ),
        ],
      ),
    );
    amountController.dispose();
    if (result == null || !mounted) {
      _autoDialogSessionId = null;
      return;
    }
    try {
      if (result.shouldCloseCash) {
        await ref
            .read(cashActionControllerProvider.notifier)
            .closeSession(
              countedBalanceCents: session.expectedBalanceCents,
              notes: 'Sessão encerrada sem confirmação do troco inicial.',
            );
        if (!mounted) return;
        AppFeedback.success(context, 'Caixa fechado.');
      } else {
        await ref
            .read(cashActionControllerProvider.notifier)
            .confirmAutoOpenedSession(
              initialFloatCents: result.initialFloatCents,
            );
        if (!mounted) return;
        AppFeedback.success(context, 'Abertura do caixa confirmada.');
      }
    } catch (_) {
      _autoDialogSessionId = null;
      rethrow;
    } finally {
      _autoDialogSessionId = null;
    }
  }

  Future<void> _startCloseFlow(CashSession session) async {
    final countedController = TextEditingController(
      text: AppFormatters.currencyFromCents(session.expectedBalanceCents),
    );
    final notesController = TextEditingController();
    final shouldClose = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: StatefulBuilder(
          builder: (context, setModalState) {
            final countedCents = MoneyParser.parseToCents(
              countedController.text,
            );
            final differenceCents = countedCents - session.expectedBalanceCents;
            final colorScheme = Theme.of(context).colorScheme;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Fechamento do caixa',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'Confira o saldo esperado, informe o valor contado e conclua o fechamento.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Saldo esperado',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                      Text(
                        AppFormatters.currencyFromCents(
                          session.expectedBalanceCents,
                        ),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: colorScheme.primary,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _SummaryLine(
                  label: 'Período',
                  value:
                      '${AppFormatters.shortDateTime(session.openedAt)} - agora',
                ),
                _SummaryLine(label: 'Operador', value: session.operatorName),
                _SummaryLine(
                  label: 'Troco inicial',
                  value: AppFormatters.currencyFromCents(
                    session.initialFloatCents,
                  ),
                ),
                _SummaryLine(
                  label: 'Vendas em dinheiro',
                  value: AppFormatters.currencyFromCents(
                    session.cashEntriesCents,
                  ),
                ),
                _SummaryLine(
                  label: 'Fiado recebido em dinheiro',
                  value: AppFormatters.currencyFromCents(
                    session.fiadoReceiptsCashCents,
                  ),
                ),
                _SummaryLine(
                  label: 'Fiado recebido por Pix',
                  value: AppFormatters.currencyFromCents(
                    session.fiadoReceiptsPixCents,
                  ),
                ),
                _SummaryLine(
                  label: 'Fiado recebido por cartão',
                  value: AppFormatters.currencyFromCents(
                    session.fiadoReceiptsCardCents,
                  ),
                ),
                _SummaryLine(
                  label: 'Suprimentos',
                  value: AppFormatters.currencyFromCents(session.suppliesCents),
                ),
                _SummaryLine(
                  label: 'Sangrias',
                  value: AppFormatters.currencyFromCents(
                    session.withdrawalsCents,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: countedController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setModalState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Saldo contado em caixa',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Observação de fechamento',
                    hintText: 'Opcional',
                  ),
                ),
                const SizedBox(height: 12),
                _DifferenceBanner(differenceCents: differenceCents),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Cancelar'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Confirmar fechamento'),
                              content: Text(
                                'Confirma o fechamento do caixa com saldo contado de ${AppFormatters.currencyFromCents(countedCents)}?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(false),
                                  child: const Text('Voltar'),
                                ),
                                FilledButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(true),
                                  child: const Text('Confirmar fechamento'),
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true && context.mounted) {
                            Navigator.of(context).pop(true);
                          }
                        },
                        child: const Text('Confirmar fechamento'),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
    if (shouldClose != true) {
      countedController.dispose();
      notesController.dispose();
      return;
    }
    try {
      await ref
          .read(cashActionControllerProvider.notifier)
          .closeSession(
            countedBalanceCents: MoneyParser.parseToCents(
              countedController.text,
            ),
            notes: notesController.text,
          );
      if (!mounted) return;
      AppFeedback.success(context, 'Caixa fechado com sucesso.');
    } catch (_) {
    } finally {
      countedController.dispose();
      notesController.dispose();
    }
  }

  Future<void> _registerMovement(CashMovementType type) async {
    final amountController = TextEditingController();
    final descriptionController = TextEditingController();
    final submitted = await showDialog<CashManualMovementInput>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(type == CashMovementType.supply ? 'Suprimento' : 'Sangria'),
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
      ),
    );
    amountController.dispose();
    descriptionController.dispose();
    if (submitted == null) return;
    try {
      await ref
          .read(cashActionControllerProvider.notifier)
          .registerManualMovement(submitted);
      if (!mounted) return;
      final actionLabel = type == CashMovementType.supply
          ? 'Suprimento'
          : 'Sangria';
      final value = AppFormatters.currencyFromCents(submitted.amountCents);
      AppFeedback.success(context, '$actionLabel registrado: $value.');
    } catch (_) {}
  }

  Future<void> _showSessionDetail(CashSession session) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CashSessionDetailSheet(session: session),
    );
  }
}

class _CurrentSessionSection extends StatelessWidget {
  const _CurrentSessionSection({
    required this.session,
    required this.updatedAt,
    required this.isBusy,
    required this.onOpen,
    required this.onConfirmAutomaticOpen,
    required this.onClose,
    required this.onSupply,
    required this.onWithdraw,
    required this.onCount,
    required this.onSelectFilter,
  });

  final CashSession? session;
  final DateTime? updatedAt;
  final bool isBusy;
  final Future<void> Function() onOpen;
  final VoidCallback? onConfirmAutomaticOpen;
  final VoidCallback? onClose;
  final Future<void> Function() onSupply;
  final Future<void> Function() onWithdraw;
  final VoidCallback onCount;
  final ValueChanged<CashMovementFilter> onSelectFilter;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (session == null) {
      return AppSectionCard(
        title: 'Sessão atual',
        subtitle: 'Nenhum caixa aberto no momento.',
        padding: const EdgeInsets.all(16),
        trailing: const AppStatusBadge(
          label: 'Fechado',
          tone: AppStatusTone.danger,
          icon: Icons.lock_outline,
        ),
        child: FilledButton.icon(
          onPressed: isBusy ? null : onOpen,
          icon: const Icon(Icons.lock_open_outlined),
          label: const Text('Abrir caixa'),
        ),
      );
    }

    final current = session!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSectionCard(
          title: 'Sessão atual',
          subtitle: current.awaitingInitialFloatConfirmation
              ? 'Abertura pendente de confirmação do troco inicial.'
              : 'Caixa ${current.isOpen ? 'aberto' : 'fechado'} desde ${AppFormatters.shortDateTime(current.openedAt)}.',
          padding: const EdgeInsets.all(16),
          trailing: current.awaitingInitialFloatConfirmation
              ? const AppStatusBadge(
                  label: 'Aguardando confirmação',
                  tone: AppStatusTone.warning,
                  icon: Icons.hourglass_top_rounded,
                )
              : AppStatusBadge(
                  label: current.status.label,
                  tone: current.isOpen
                      ? AppStatusTone.success
                      : AppStatusTone.neutral,
                  icon: current.isOpen ? Icons.lock_open : Icons.lock_outline,
                ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Saldo em caixa',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            AppFormatters.currencyFromCents(
                              current.physicalBalanceCents,
                            ),
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Saldo esperado',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          AppFormatters.currencyFromCents(
                            current.expectedBalanceCents,
                          ),
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: colorScheme.primary,
                              ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _InfoLine(
                    label: 'Abertura',
                    value: AppFormatters.shortDateTime(current.openedAt),
                  ),
                  _InfoLine(
                    label: 'Troco inicial',
                    value: AppFormatters.currencyFromCents(
                      current.initialFloatCents,
                    ),
                    semanticLabel:
                        'Troco inicial ${AppFormatters.currencyFromCents(current.initialFloatCents)}',
                  ),
                  _InfoLine(label: 'Operador', value: current.operatorName),
                  _InfoLine(
                    label: 'Duração',
                    value: _formatDuration(
                      (current.closedAt ?? DateTime.now()).difference(
                        current.openedAt,
                      ),
                    ),
                  ),
                ],
              ),
              if (current.awaitingInitialFloatConfirmation) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.secondaryContainer.withValues(
                      alpha: 0.68,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Troco inicial não informado. Confirme a abertura para liberar suprimento, sangria e contagem.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: colorScheme.onPrimaryContainer),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (current.notes?.isNotEmpty ?? false) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    current.notes!,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
              if (updatedAt != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'Atualizado às ${TimeOfDay.fromDateTime(updatedAt!).format(context)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ],
          ),
        ),
        AppSectionCard(
          title: 'Ações principais',
          subtitle: current.awaitingInitialFloatConfirmation
              ? 'Confirme a abertura antes de seguir.'
              : 'Operações mais usadas no caixa.',
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: current.isOpen
                ? [
                    _ActionButton(
                      label: 'Fechar caixa',
                      icon: Icons.lock_outline,
                      isDanger: true,
                      onPressed: onClose,
                    ),
                    _ActionButton(
                      label: 'Suprimento',
                      icon: Icons.add_circle_outline,
                      onPressed:
                          current.awaitingInitialFloatConfirmation || isBusy
                          ? null
                          : onSupply,
                    ),
                    _ActionButton(
                      label: 'Sangria',
                      icon: Icons.remove_circle_outline,
                      onPressed:
                          current.awaitingInitialFloatConfirmation || isBusy
                          ? null
                          : onWithdraw,
                    ),
                    _ActionButton(
                      label: 'Contagem',
                      icon: Icons.calculate_outlined,
                      onPressed: current.awaitingInitialFloatConfirmation
                          ? null
                          : onCount,
                    ),
                    if (current.awaitingInitialFloatConfirmation)
                      _ActionButton(
                        label: 'Confirmar abertura',
                        icon: Icons.verified_outlined,
                        onPressed: isBusy ? null : onConfirmAutomaticOpen,
                      ),
                  ]
                : [
                    _ActionButton(
                      label: 'Abrir caixa',
                      icon: Icons.lock_open_outlined,
                      onPressed: isBusy ? null : onOpen,
                    ),
                  ],
          ),
        ),
        const SizedBox(height: 14),
        AppSectionCard(
          title: 'Resumo financeiro',
          subtitle: 'Toque em um bloco para filtrar as movimentações abaixo.',
          padding: const EdgeInsets.all(16),
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.18,
            children: [
              _CashMetricCard(
                label: 'Entradas',
                valueCents: current.cashEntriesCents,
                caption: 'Vendas em dinheiro',
                icon: Icons.arrow_downward_rounded,
                accentColor: AppTheme.success,
                semanticLabel:
                    'Entradas em dinheiro ${AppFormatters.currencyFromCents(current.cashEntriesCents)}',
                onTap: () => onSelectFilter(CashMovementFilter.sales),
              ),
              _CashMetricCard(
                label: 'Saídas',
                valueCents: current.withdrawalsCents,
                caption: 'Sangrias registradas',
                icon: Icons.arrow_upward_rounded,
                accentColor: AppTheme.warning,
                semanticLabel:
                    'Saídas ${AppFormatters.currencyFromCents(current.withdrawalsCents)}',
                onTap: () => onSelectFilter(CashMovementFilter.sangria),
              ),
              _CashMetricCard(
                label: 'Saldo físico',
                valueCents: current.physicalBalanceCents,
                caption: 'Dinheiro em caixa agora',
                icon: Icons.account_balance_wallet_rounded,
                accentColor: Theme.of(context).colorScheme.primary,
                semanticLabel:
                    'Saldo físico em caixa ${AppFormatters.currencyFromCents(current.physicalBalanceCents)}',
                onTap: () => onSelectFilter(CashMovementFilter.all),
                infoMessage:
                    'Saldo físico considera troco inicial, vendas em dinheiro, fiado recebido em dinheiro, suprimentos e sangrias.',
              ),
              _CashMetricCard(
                label: 'Fiado recebido',
                valueCents: current.totalFiadoReceiptsCents,
                caption: 'Dinheiro, Pix e cartão',
                icon: Icons.receipt_long_rounded,
                accentColor: AppTheme.secondary,
                semanticLabel:
                    'Fiado recebido ${AppFormatters.currencyFromCents(current.totalFiadoReceiptsCents)}',
                onTap: () => onSelectFilter(CashMovementFilter.fiado),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    return '${hours}h ${minutes.toString().padLeft(2, '0')}min';
  }
}

class _CashMetricCard extends StatelessWidget {
  const _CashMetricCard({
    required this.label,
    required this.valueCents,
    required this.caption,
    required this.icon,
    required this.accentColor,
    required this.semanticLabel,
    required this.onTap,
    this.infoMessage,
  });

  final String label;
  final int valueCents;
  final String caption;
  final IconData icon;
  final Color accentColor;
  final String semanticLabel;
  final VoidCallback onTap;
  final String? infoMessage;

  @override
  Widget build(BuildContext context) {
    final tokens = context.appColors;
    final palette = accentColor == AppTheme.success
        ? tokens.cashflowPositive
        : accentColor == AppTheme.warning
        ? tokens.warning
        : accentColor == AppTheme.secondary
        ? tokens.info
        : tokens.brand;

    return Semantics(
      label: semanticLabel,
      child: AppSummaryBlock(
        label: label,
        value: AppFormatters.currencyFromCents(valueCents),
        caption: caption,
        icon: icon,
        onTap: onTap,
        palette: palette,
        compact: true,
        infoMessage: infoMessage,
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.isDanger = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool isDanger;

  @override
  Widget build(BuildContext context) {
    final width = (MediaQuery.of(context).size.width - 64) / 2;
    final foreground = isDanger
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: width,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(132, 46),
          foregroundColor: foreground,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
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
    final palette = isNegative
        ? context.appColors.cashflowNegative
        : context.appColors.cashflowPositive;
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: palette.border),
            ),
            child: Text(
              movement.type.label,
              style: TextStyle(
                color: palette.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  movement.description?.isNotEmpty == true
                      ? movement.description!
                      : movement.type.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    AppFormatters.shortDateTime(movement.createdAt),
                    if (movement.paymentMethod != null)
                      movement.paymentMethod!.label,
                  ].join(' • '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Semantics(
            label:
                'Valor ${AppFormatters.currencyFromCents(movement.amountCents.abs())}',
            child: Text(
              AppFormatters.currencyFromCents(movement.amountCents.abs()),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: palette.onSurface,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionHistoryTile extends StatelessWidget {
  const _SessionHistoryTile({required this.session, required this.onTap});

  final CashSession session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final difference = session.differenceCents;
    final isNegativeDifference = (difference ?? 0) < 0;
    final isPositiveDifference = (difference ?? 0) > 0;
    final colorScheme = Theme.of(context).colorScheme;
    final negativePalette = context.appColors.cashflowNegative;
    final positivePalette = context.appColors.cashflowPositive;
    final valueColor = isNegativeDifference
        ? negativePalette.onSurface
        : isPositiveDifference
        ? positivePalette.onSurface
        : session.isOpen
        ? colorScheme.primary
        : colorScheme.onSurface;
    final valueLabel = difference != null
        ? '${difference > 0 ? '+' : ''}${AppFormatters.currencyFromCents(difference)}'
        : AppFormatters.currencyFromCents(session.expectedBalanceCents);
    final badgeLabel = session.isOpen
        ? 'Em aberto'
        : difference == null
        ? 'Fechado'
        : isNegativeDifference
        ? 'Diferença negativa'
        : isPositiveDifference
        ? 'Diferença positiva'
        : 'Fechado sem diferença';
    final badgeBackground = isNegativeDifference
        ? negativePalette.surface
        : isPositiveDifference
        ? positivePalette.surface
        : session.isOpen
        ? colorScheme.primaryContainer.withValues(alpha: 0.7)
        : colorScheme.surfaceContainerHigh;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.isOpen ? 'Sessão em aberto' : 'Sessão encerrada',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  'Operador: ${session.operatorName}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    'Abertura ${AppFormatters.shortDateTime(session.openedAt)}',
                    if (session.closedAt != null)
                      'Fechamento ${AppFormatters.shortDateTime(session.closedAt!)}',
                  ].join(' • '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isNegativeDifference)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(
                        Icons.warning_amber_rounded,
                        color: negativePalette.onSurface,
                        size: 18,
                      ),
                    ),
                  Text(
                    valueLabel,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: valueColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: badgeBackground,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: isNegativeDifference
                        ? negativePalette.border
                        : Colors.transparent,
                  ),
                ),
                child: Text(
                  badgeLabel,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: valueColor,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.label,
    required this.value,
    this.semanticLabel,
  });

  final String label;
  final String value;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 132,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 2),
          Semantics(
            label: semanticLabel,
            child: Text(value, style: Theme.of(context).textTheme.titleSmall),
          ),
        ],
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 12),
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

class _DifferenceBanner extends StatelessWidget {
  const _DifferenceBanner({required this.differenceCents});

  final int differenceCents;

  @override
  Widget build(BuildContext context) {
    final isNegative = differenceCents < 0;
    final isPositive = differenceCents > 0;
    final negativePalette = context.appColors.cashflowNegative;
    final positivePalette = context.appColors.cashflowPositive;
    final color = isNegative
        ? negativePalette.onSurface
        : isPositive
        ? positivePalette.onSurface
        : Theme.of(context).colorScheme.onSurfaceVariant;
    final background = isNegative
        ? negativePalette.surface
        : isPositive
        ? positivePalette.surface
        : Theme.of(context).colorScheme.surfaceContainerHigh;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'Diferença calculada: ${differenceCents > 0 ? '+' : ''}${AppFormatters.currencyFromCents(differenceCents)}',
        style: Theme.of(context).textTheme.titleSmall?.copyWith(color: color),
      ),
    );
  }
}

class _AutoOpenResolution {
  const _AutoOpenResolution._({
    required this.shouldCloseCash,
    this.initialFloatCents = 0,
  });
  const _AutoOpenResolution.confirm(int initialFloatCents)
    : this._(shouldCloseCash: false, initialFloatCents: initialFloatCents);
  const _AutoOpenResolution.closeCash() : this._(shouldCloseCash: true);

  final bool shouldCloseCash;
  final int initialFloatCents;
}
