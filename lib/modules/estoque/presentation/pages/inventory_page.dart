import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/widgets/app_card.dart';
import '../../../../app/core/widgets/app_list_tile_card.dart';
import '../../../../app/core/widgets/app_main_drawer.dart';
import '../../../../app/core/widgets/app_metric_card.dart';
import '../../../../app/core/widgets/app_page_header.dart';
import '../../../../app/core/widgets/app_search_field.dart';
import '../../../../app/core/widgets/app_state_card.dart';
import '../../../../app/core/widgets/app_status_badge.dart';
import '../../../../app/routes/route_names.dart';
import '../../../../app/theme/app_design_tokens.dart';
import '../../domain/entities/inventory_item.dart';
import '../../domain/entities/inventory_summary.dart';
import '../../domain/services/inventory_alert_service.dart';
import '../providers/inventory_providers.dart';

class InventoryPage extends ConsumerStatefulWidget {
  const InventoryPage({super.key});

  @override
  ConsumerState<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends ConsumerState<InventoryPage> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(
      text: ref.read(inventorySearchQueryProvider),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final itemsAsync = ref.watch(inventoryItemsProvider);
    final selectedFilter = ref.watch(inventoryFilterProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Estoque')),
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
            child: const AppPageHeader(
              title: 'Estoque atual',
              subtitle:
                  'Acompanhe o saldo operacional dos produtos acabados sem alterar a semantica atual do cadastro.',
              badgeLabel: 'Produtos',
              badgeIcon: Icons.inventory_2_rounded,
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
              children: [
                Expanded(
                  child: AppSearchField(
                    controller: _searchController,
                    hintText: 'Buscar nome, SKU, cor ou tamanho',
                    onChanged: (value) {
                      ref.read(inventorySearchQueryProvider.notifier).state =
                          value;
                      setState(() {});
                    },
                    onClear: () {
                      _searchController.clear();
                      ref.read(inventorySearchQueryProvider.notifier).state =
                          '';
                      setState(() {});
                    },
                  ),
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
                for (final filter in InventoryListFilter.values)
                  ChoiceChip(
                    label: Text(filter.label),
                    selected: selectedFilter == filter,
                    onSelected: (_) =>
                        ref.read(inventoryFilterProvider.notifier).state =
                            filter,
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
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => context.pushNamed(
                                AppRouteNames.inventoryMovements,
                              ),
                              icon: const Icon(Icons.history_rounded),
                              label: const Text('Ver movimentacoes'),
                            ),
                          ),
                          SizedBox(width: layout.space4),
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed: () => context.pushNamed(
                                AppRouteNames.inventoryAdjustment,
                              ),
                              icon: const Icon(Icons.tune_rounded),
                              label: const Text('Novo ajuste'),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: layout.space4),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              context.pushNamed(AppRouteNames.inventoryCounts),
                          icon: const Icon(Icons.fact_check_rounded),
                          label: const Text('Inventario fisico'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: itemsAsync.when(
              data: (items) {
                final summary = InventoryAlertService.summarize(items);
                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(inventoryItemsProvider);
                    await ref.read(inventoryItemsProvider.future);
                  },
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      layout.pagePadding,
                      0,
                      layout.pagePadding,
                      layout.pagePadding,
                    ),
                    children: [
                      _InventorySummaryPanel(summary: summary),
                      SizedBox(height: layout.space5),
                      if (items.isEmpty)
                        const AppStateCard(
                          title: 'Nenhum item encontrado',
                          message:
                              'Ajuste a busca ou o filtro para localizar outro SKU operacional.',
                        )
                      else
                        for (final item in items) ...[
                          _InventoryItemTile(item: item),
                          SizedBox(height: layout.space4),
                        ],
                    ],
                  ),
                );
              },
              loading: () => Padding(
                padding: EdgeInsets.all(layout.pagePadding),
                child: const AppStateCard(
                  title: 'Carregando estoque',
                  message: 'Buscando o saldo atual de produtos e variacoes.',
                  tone: AppStateTone.loading,
                  compact: true,
                ),
              ),
              error: (error, _) => Padding(
                padding: EdgeInsets.all(layout.pagePadding),
                child: AppStateCard(
                  title: 'Falha ao carregar o estoque',
                  message: '$error',
                  tone: AppStateTone.error,
                  compact: true,
                  actionLabel: 'Tentar novamente',
                  onAction: () => ref.invalidate(inventoryItemsProvider),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InventorySummaryPanel extends StatelessWidget {
  const _InventorySummaryPanel({required this.summary});

  final InventorySummary summary;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    return Wrap(
      spacing: layout.space4,
      runSpacing: layout.space4,
      children: [
        SizedBox(
          width: 190,
          child: AppMetricCard(
            label: 'Total de SKUs',
            value: '${summary.totalSkus}',
            icon: Icons.qr_code_2_rounded,
            caption: 'Itens visiveis no filtro atual',
            accentColor: context.appColors.brand.base,
          ),
        ),
        SizedBox(
          width: 190,
          child: AppMetricCard(
            label: 'Itens zerados',
            value: '${summary.zeroedItems}',
            icon: Icons.remove_shopping_cart_rounded,
            caption: 'Sem saldo disponivel agora',
            accentColor: context.appColors.warning.base,
          ),
        ),
        SizedBox(
          width: 190,
          child: AppMetricCard(
            label: 'Abaixo do minimo',
            value: '${summary.belowMinimumItems}',
            icon: Icons.priority_high_rounded,
            caption: 'Precisam de atencao operacional',
            accentColor: context.appColors.danger.base,
          ),
        ),
        SizedBox(
          width: 210,
          child: AppMetricCard(
            label: 'Valor em custo',
            value: AppFormatters.currencyFromCents(summary.estimatedCostCents),
            icon: Icons.payments_outlined,
            caption: 'Estimativa pelo custo atual cadastrado',
            accentColor: context.appColors.success.base,
          ),
        ),
      ],
    );
  }
}

class _InventoryItemTile extends StatelessWidget {
  const _InventoryItemTile({required this.item});

  final InventoryItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final statusTone = switch (item.status) {
      InventoryItemStatus.available => AppStatusTone.success,
      InventoryItemStatus.belowMinimum => AppStatusTone.warning,
      InventoryItemStatus.zeroed => AppStatusTone.danger,
      InventoryItemStatus.inactive => AppStatusTone.neutral,
    };
    final cardTone = switch (item.status) {
      InventoryItemStatus.available => AppCardTone.standard,
      InventoryItemStatus.belowMinimum => AppCardTone.warning,
      InventoryItemStatus.zeroed => AppCardTone.danger,
      InventoryItemStatus.inactive => AppCardTone.muted,
    };
    final subtitleParts = <String>[
      if ((item.sku ?? '').trim().isNotEmpty) 'SKU ${item.sku!.trim()}',
      if ((item.variantColorLabel ?? '').trim().isNotEmpty)
        'Cor ${item.variantColorLabel!.trim()}',
      if ((item.variantSizeLabel ?? '').trim().isNotEmpty)
        'Tam ${item.variantSizeLabel!.trim()}',
    ];
    final subtitle = subtitleParts.isEmpty
        ? (item.hasVariant ? 'Variacao sem atributos' : 'Produto simples')
        : subtitleParts.join('  |  ');

    return AppListTileCard(
      title: item.displayName,
      subtitle: subtitle,
      tone: cardTone,
      leading: DecoratedBox(
        decoration: BoxDecoration(
          color: switch (item.status) {
            InventoryItemStatus.available => context.appColors.success.surface,
            InventoryItemStatus.belowMinimum =>
              context.appColors.warning.surface,
            InventoryItemStatus.zeroed => context.appColors.danger.surface,
            InventoryItemStatus.inactive =>
              context.appColors.interactive.surface,
          },
          borderRadius: BorderRadius.circular(layout.radiusMd),
        ),
        child: Padding(
          padding: EdgeInsets.all(layout.space4),
          child: Icon(
            item.hasVariant ? Icons.style_outlined : Icons.inventory_2_outlined,
            color: switch (item.status) {
              InventoryItemStatus.available => context.appColors.success.base,
              InventoryItemStatus.belowMinimum =>
                context.appColors.warning.base,
              InventoryItemStatus.zeroed => context.appColors.danger.base,
              InventoryItemStatus.inactive =>
                context.appColors.interactive.base,
            },
          ),
        ),
      ),
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${AppFormatters.quantityFromMil(item.currentStockMil)} ${item.unitMeasure}',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: layout.space2),
          Text(
            item.status.label,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      badges: [
        AppStatusBadge(label: item.status.label, tone: statusTone),
        AppStatusBadge(
          label:
              'Minimo ${AppFormatters.quantityFromMil(item.minimumStockMil)} ${item.unitMeasure}',
          tone: AppStatusTone.neutral,
        ),
        AppStatusBadge(
          label: 'Custo ${AppFormatters.currencyFromCents(item.costCents)}',
          tone: AppStatusTone.info,
        ),
        AppStatusBadge(
          label:
              'Venda ${AppFormatters.currencyFromCents(item.salePriceCents)}',
          tone: AppStatusTone.success,
        ),
        if (item.allowNegativeStock)
          const AppStatusBadge(
            label: 'Aceita negativo',
            tone: AppStatusTone.warning,
          ),
      ],
    );
  }
}
