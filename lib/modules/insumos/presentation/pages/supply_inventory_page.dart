import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/widgets/app_feedback.dart';
import '../../../../app/core/widgets/app_list_tile_card.dart';
import '../../../../app/core/widgets/app_main_drawer.dart';
import '../../../../app/core/widgets/app_page_header.dart';
import '../../../../app/core/widgets/app_state_card.dart';
import '../../../../app/core/widgets/app_status_badge.dart';
import '../../../../app/core/widgets/app_summary_block.dart';
import '../../../../app/theme/app_design_tokens.dart';
import '../../domain/entities/supply_inventory.dart';
import '../providers/supply_providers.dart';

class SupplyInventoryPage extends ConsumerStatefulWidget {
  const SupplyInventoryPage({super.key, this.initialSupplyId});

  final int? initialSupplyId;

  @override
  ConsumerState<SupplyInventoryPage> createState() =>
      _SupplyInventoryPageState();
}

class _SupplyInventoryPageState extends ConsumerState<SupplyInventoryPage> {
  SupplyInventorySourceType? _sourceType;
  int _periodDays = 30;
  bool _isVerifying = false;
  SupplyInventoryConsistencyReport? _lastConsistencyReport;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final occurredFrom = _periodDays <= 0
        ? null
        : DateTime.now().subtract(Duration(days: _periodDays));
    final movementsQuery = SupplyInventoryMovementQuery(
      supplyId: widget.initialSupplyId,
      sourceType: _sourceType,
      occurredFrom: occurredFrom,
    );
    final movementsAsync = ref.watch(
      supplyInventoryMovementsProvider(movementsQuery),
    );
    final supplyAsync = widget.initialSupplyId == null
        ? null
        : ref.watch(supplyDetailProvider(widget.initialSupplyId!));

    return Scaffold(
      appBar: AppBar(title: const Text('Estoque operacional')),
      drawer: const AppMainDrawer(),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              layout.pagePadding,
              layout.space5,
              layout.pagePadding,
              layout.space4,
            ),
            child: AppPageHeader(
              title: 'Movimentacoes de insumos',
              subtitle: _buildSubtitle(supplyAsync),
              badgeLabel: 'Ledger local',
              badgeIcon: Icons.inventory_2_outlined,
              emphasized: true,
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              layout.pagePadding,
              0,
              layout.pagePadding,
              layout.space4,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AppSummaryBlock(
                    label: 'Consistencia do estoque',
                    value: _consistencyValueLabel,
                    caption: _consistencyCaptionLabel,
                    icon: _lastConsistencyReport?.hasDrift ?? false
                        ? Icons.rule_rounded
                        : Icons.verified_rounded,
                    palette: _lastConsistencyReport == null
                        ? context.appColors.info
                        : (_lastConsistencyReport!.hasDrift
                              ? context.appColors.warning
                              : context.appColors.success),
                    compact: true,
                  ),
                ),
                SizedBox(width: layout.space4),
                FilledButton.tonalIcon(
                  onPressed: _isVerifying ? null : _verifyConsistency,
                  icon: _isVerifying
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.verified_user_rounded),
                  label: Text(_isVerifying ? 'Verificando' : 'Verificar saldo'),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              layout.pagePadding,
              0,
              layout.pagePadding,
              layout.space4,
            ),
            child: Wrap(
              spacing: layout.space3,
              runSpacing: layout.space3,
              children: [
                for (final source in <SupplyInventorySourceType?>[
                  null,
                  SupplyInventorySourceType.purchase,
                  SupplyInventorySourceType.purchaseCancel,
                  SupplyInventorySourceType.sale,
                  SupplyInventorySourceType.saleCancel,
                  SupplyInventorySourceType.manualAdjustment,
                  SupplyInventorySourceType.migrationSeed,
                ])
                  ChoiceChip(
                    label: Text(
                      source == null ? 'Todas as origens' : source.filterLabel,
                    ),
                    selected: _sourceType == source,
                    onSelected: (_) => setState(() => _sourceType = source),
                  ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              layout.pagePadding,
              0,
              layout.pagePadding,
              layout.space5,
            ),
            child: Wrap(
              spacing: layout.space3,
              runSpacing: layout.space3,
              children: [
                for (final option in const <(int, String)>[
                  (0, 'Periodo inteiro'),
                  (7, 'Ultimos 7 dias'),
                  (30, 'Ultimos 30 dias'),
                ])
                  ChoiceChip(
                    label: Text(option.$2),
                    selected: _periodDays == option.$1,
                    onSelected: (_) => setState(() => _periodDays = option.$1),
                  ),
              ],
            ),
          ),
          Expanded(
            child: movementsAsync.when(
              data: (movements) {
                if (movements.isEmpty) {
                  return Padding(
                    padding: EdgeInsets.all(layout.pagePadding),
                    child: const AppStateCard(
                      title: 'Sem movimentacoes',
                      message:
                          'Ainda nao existem movimentos operacionais para o filtro selecionado.',
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(
                      supplyInventoryMovementsProvider(movementsQuery),
                    );
                  },
                  child: ListView.separated(
                    padding: EdgeInsets.fromLTRB(
                      layout.pagePadding,
                      0,
                      layout.pagePadding,
                      layout.pagePadding,
                    ),
                    itemCount: movements.length,
                    separatorBuilder: (_, __) =>
                        SizedBox(height: layout.space4),
                    itemBuilder: (context, index) {
                      final movement = movements[index];
                      final footerLines = <String>[
                        if ((movement.notes ?? '').trim().isNotEmpty)
                          movement.notes!.trim(),
                        if (movement.auditReferenceLabel != null)
                          movement.auditReferenceLabel!,
                      ];

                      return AppListTileCard(
                        title: movement.supplyName,
                        subtitle: movement.historyLabel,
                        leading: DecoratedBox(
                          decoration: BoxDecoration(
                            color: _toneForMovement(movement).surface,
                            borderRadius: BorderRadius.circular(
                              layout.radiusMd,
                            ),
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(layout.space4),
                            child: Icon(
                              _iconForMovement(movement),
                              color: _toneForMovement(movement).base,
                            ),
                          ),
                        ),
                        badges: [
                          AppStatusBadge(
                            label:
                                '${movement.quantityDeltaMil >= 0 ? '+' : ''}${AppFormatters.quantityFromMil(movement.quantityDeltaMil)} ${movement.unitType}',
                            tone: movement.quantityDeltaMil >= 0
                                ? AppStatusTone.success
                                : AppStatusTone.warning,
                          ),
                          AppStatusBadge(
                            label: AppFormatters.shortDateTime(
                              movement.occurredAt,
                            ),
                            tone: AppStatusTone.info,
                          ),
                          if (movement.isLegacySeed)
                            const AppStatusBadge(
                              label: 'Inicializacao tecnica',
                              tone: AppStatusTone.neutral,
                            ),
                        ],
                        footer: footerLines.isEmpty
                            ? null
                            : Text(
                                footerLines.join('  |  '),
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                      );
                    },
                  ),
                );
              },
              loading: () => Padding(
                padding: EdgeInsets.all(layout.pagePadding),
                child: const AppStateCard(
                  title: 'Carregando movimentacoes',
                  message: 'Buscando o ledger operacional local.',
                  tone: AppStateTone.loading,
                  compact: true,
                ),
              ),
              error: (error, _) => Padding(
                padding: EdgeInsets.all(layout.pagePadding),
                child: AppStateCard(
                  title: 'Falha ao carregar movimentacoes',
                  message: '$error',
                  tone: AppStateTone.error,
                  compact: true,
                  actionLabel: 'Tentar novamente',
                  onAction: () => ref.invalidate(
                    supplyInventoryMovementsProvider(movementsQuery),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String get _consistencyValueLabel {
    final report = _lastConsistencyReport;
    if (report == null) {
      return widget.initialSupplyId == null
          ? 'Verificacao manual disponivel'
          : 'Verificar este insumo';
    }
    if (report.isConsistent) {
      return 'Sem divergencias';
    }
    return '${report.repairedSupplyCount} corrigidos agora';
  }

  String get _consistencyCaptionLabel {
    final report = _lastConsistencyReport;
    if (report == null) {
      return 'Recalcula o saldo pelo ledger e corrige o cache se houver drift silencioso.';
    }
    if (report.isConsistent) {
      return '${report.checkedSupplyCount} insumos verificados em ${AppFormatters.shortDateTime(report.checkedAt)}.';
    }
    return '${report.driftedSupplyCount} divergencias encontradas em ${AppFormatters.shortDateTime(report.checkedAt)}.';
  }

  Future<void> _verifyConsistency() async {
    setState(() => _isVerifying = true);
    try {
      final report = await ref
          .read(supplyRepositoryProvider)
          .verifyInventoryConsistency(
            supplyIds: widget.initialSupplyId == null
                ? null
                : [widget.initialSupplyId!],
          );
      if (!mounted) {
        return;
      }

      setState(() => _lastConsistencyReport = report);
      ref.invalidate(supplyInventoryOverviewProvider);
      ref.invalidate(supplyReorderSuggestionsProvider);
      if (widget.initialSupplyId != null) {
        ref.invalidate(supplyDetailProvider(widget.initialSupplyId!));
      }

      if (report.isConsistent) {
        AppFeedback.success(
          context,
          report.checkedSupplyCount == 1
              ? 'Saldo verificado sem divergencias.'
              : 'Saldos verificados sem divergencias.',
        );
      } else {
        AppFeedback.info(
          context,
          report.repairedSupplyCount == 1
              ? '1 divergencia de estoque foi corrigida pelo ledger.'
              : '${report.repairedSupplyCount} divergencias de estoque foram corrigidas pelo ledger.',
        );
      }
    } catch (error) {
      if (mounted) {
        AppFeedback.error(
          context,
          'Nao foi possivel verificar a consistencia do estoque: $error',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isVerifying = false);
      }
    }
  }

  String _buildSubtitle(AsyncValue<dynamic>? supplyAsync) {
    if (supplyAsync == null) {
      return 'Entradas, saidas, ajustes, estornos e saldo inicial migrado do estoque operacional local.';
    }
    return supplyAsync.when(
      data: (supply) => supply == null
          ? 'Movimentacoes do estoque operacional local.'
          : 'Historico operacional do insumo ${supply.name}.',
      loading: () => 'Carregando contexto do insumo selecionado.',
      error: (_, __) => 'Movimentacoes do estoque operacional local.',
    );
  }

  AppTonePalette _toneForMovement(SupplyInventoryMovement movement) {
    final colors = context.appColors;
    switch (movement.sourceType) {
      case SupplyInventorySourceType.purchase:
      case SupplyInventorySourceType.purchaseCancel:
        return colors.success;
      case SupplyInventorySourceType.sale:
      case SupplyInventorySourceType.saleCancel:
        return colors.warning;
      case SupplyInventorySourceType.manualAdjustment:
        return colors.info;
      case SupplyInventorySourceType.migrationSeed:
        return colors.interactive;
    }
  }

  IconData _iconForMovement(SupplyInventoryMovement movement) {
    switch (movement.sourceType) {
      case SupplyInventorySourceType.purchase:
        return Icons.south_west_rounded;
      case SupplyInventorySourceType.purchaseCancel:
        return Icons.undo_rounded;
      case SupplyInventorySourceType.sale:
        return Icons.north_east_rounded;
      case SupplyInventorySourceType.saleCancel:
        return Icons.history_toggle_off_rounded;
      case SupplyInventorySourceType.manualAdjustment:
        return Icons.tune_rounded;
      case SupplyInventorySourceType.migrationSeed:
        return Icons.flag_rounded;
    }
  }
}
