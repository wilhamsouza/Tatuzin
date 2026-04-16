import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/widgets/app_list_tile_card.dart';
import '../../../../app/core/widgets/app_main_drawer.dart';
import '../../../../app/core/widgets/app_page_header.dart';
import '../../../../app/core/widgets/app_search_field.dart';
import '../../../../app/core/widgets/app_state_card.dart';
import '../../../../app/core/widgets/app_status_badge.dart';
import '../../../../app/core/widgets/app_summary_block.dart';
import '../../../../app/routes/route_names.dart';
import '../../../../app/theme/app_design_tokens.dart';
import '../../domain/entities/supply_inventory.dart';
import '../providers/supply_providers.dart';

class ReorderSuggestionsPage extends ConsumerStatefulWidget {
  const ReorderSuggestionsPage({super.key});

  @override
  ConsumerState<ReorderSuggestionsPage> createState() =>
      _ReorderSuggestionsPageState();
}

class _ReorderSuggestionsPageState
    extends ConsumerState<ReorderSuggestionsPage> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(
      text: ref.read(reorderSuggestionsSearchQueryProvider),
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
    final filter = ref.watch(reorderSuggestionsFilterProvider);
    final suggestionsAsync = ref.watch(supplyReorderSuggestionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Recomprar hoje')),
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
              title: 'Recomprar hoje',
              subtitle:
                  'Veja o que falta comprar hoje usando apenas saldo derivado e estoque minimo.',
              badgeLabel: 'Reposicao',
              badgeIcon: Icons.shopping_bag_outlined,
              emphasized: true,
            ),
          ),
          suggestionsAsync.when(
            data: (suggestions) {
              final criticalCount = suggestions
                  .where(
                    (item) =>
                        item.overview.inventoryStatus ==
                        SupplyInventoryStatus.critical,
                  )
                  .length;
              final lowCount = suggestions
                  .where(
                    (item) =>
                        item.overview.inventoryStatus ==
                        SupplyInventoryStatus.low,
                  )
                  .length;
              return Padding(
                padding: EdgeInsets.fromLTRB(
                  layout.pagePadding,
                  0,
                  layout.pagePadding,
                  layout.space4,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: AppSummaryBlock(
                        label: 'Itens criticos',
                        value: '$criticalCount',
                        caption: criticalCount == 1
                            ? 'Precisa de atencao imediata'
                            : 'Precisam de atencao imediata',
                        icon: Icons.priority_high_rounded,
                        palette: context.appColors.danger,
                        compact: true,
                      ),
                    ),
                    SizedBox(width: layout.space4),
                    Expanded(
                      child: AppSummaryBlock(
                        label: 'Itens acionaveis',
                        value: '${criticalCount + lowCount}',
                        caption: lowCount == 0
                            ? 'Sem itens em nivel baixo'
                            : '$lowCount em nivel baixo',
                        icon: Icons.playlist_add_check_rounded,
                        palette: context.appColors.warning,
                        compact: true,
                      ),
                    ),
                  ],
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              layout.pagePadding,
              0,
              layout.pagePadding,
              layout.space4,
            ),
            child: AppSearchField(
              controller: _searchController,
              hintText: 'Buscar por insumo ou fornecedor',
              onChanged: (value) {
                ref.read(reorderSuggestionsSearchQueryProvider.notifier).state =
                    value;
                setState(() {});
              },
              onClear: () {
                _searchController.clear();
                ref.read(reorderSuggestionsSearchQueryProvider.notifier).state =
                    '';
                setState(() {});
              },
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
                for (final option in SupplyReorderFilter.values)
                  ChoiceChip(
                    label: Text(option.label),
                    selected: filter == option,
                    onSelected: (_) =>
                        ref
                                .read(reorderSuggestionsFilterProvider.notifier)
                                .state =
                            option,
                  ),
              ],
            ),
          ),
          Expanded(
            child: suggestionsAsync.when(
              data: (suggestions) {
                if (suggestions.isEmpty) {
                  return Padding(
                    padding: EdgeInsets.all(layout.pagePadding),
                    child: AppStateCard(
                      title: _emptyTitle(filter),
                      message: _emptyMessage(filter),
                      tone: AppStateTone.success,
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(supplyReorderSuggestionsProvider);
                    await ref.read(supplyReorderSuggestionsProvider.future);
                  },
                  child: ListView.separated(
                    padding: EdgeInsets.fromLTRB(
                      layout.pagePadding,
                      0,
                      layout.pagePadding,
                      92,
                    ),
                    itemCount: suggestions.length,
                    separatorBuilder: (_, __) =>
                        SizedBox(height: layout.space4),
                    itemBuilder: (context, index) {
                      final suggestion = suggestions[index];
                      return _SuggestionTile(suggestion: suggestion);
                    },
                  ),
                );
              },
              loading: () => Padding(
                padding: EdgeInsets.all(layout.pagePadding),
                child: const AppStateCard(
                  title: 'Carregando recompra',
                  message: 'Calculando itens abaixo do minimo.',
                  tone: AppStateTone.loading,
                  compact: true,
                ),
              ),
              error: (error, _) => Padding(
                padding: EdgeInsets.all(layout.pagePadding),
                child: AppStateCard(
                  title: 'Falha ao montar a recompra',
                  message: '$error',
                  tone: AppStateTone.error,
                  compact: true,
                  actionLabel: 'Tentar novamente',
                  onAction: () =>
                      ref.invalidate(supplyReorderSuggestionsProvider),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _emptyTitle(SupplyReorderFilter filter) {
    return switch (filter) {
      SupplyReorderFilter.all => 'Nada para recomprar agora',
      SupplyReorderFilter.critical => 'Nenhum item critico',
      SupplyReorderFilter.low => 'Nenhum item em nivel baixo',
    };
  }

  String _emptyMessage(SupplyReorderFilter filter) {
    return switch (filter) {
      SupplyReorderFilter.all =>
        'Nao ha insumos ativos abaixo do minimo com baseline operacional suficiente.',
      SupplyReorderFilter.critical => 'Nao ha insumos criticos no momento.',
      SupplyReorderFilter.low => 'Nao ha insumos em nivel baixo no momento.',
    };
  }
}

class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile({required this.suggestion});

  final SupplyReorderSuggestion suggestion;

  @override
  Widget build(BuildContext context) {
    final supply = suggestion.overview.supply;
    final layout = context.appLayout;
    final isCritical =
        suggestion.overview.inventoryStatus == SupplyInventoryStatus.critical;
    final lastPurchaseAt = suggestion.overview.lastPurchaseAt;

    return AppListTileCard(
      title: supply.name,
      subtitle: supply.defaultSupplierName == null
          ? 'Sem fornecedor padrao vinculado'
          : 'Fornecedor padrao: ${supply.defaultSupplierName}',
      leading: DecoratedBox(
        decoration: BoxDecoration(
          color: isCritical
              ? context.appColors.danger.surface
              : context.appColors.warning.surface,
          borderRadius: BorderRadius.circular(layout.radiusMd),
        ),
        child: Padding(
          padding: EdgeInsets.all(layout.space4),
          child: Icon(
            isCritical
                ? Icons.priority_high_rounded
                : Icons.warning_amber_rounded,
            color: isCritical
                ? context.appColors.danger.base
                : context.appColors.warning.base,
          ),
        ),
      ),
      badges: [
        AppStatusBadge(
          label: suggestion.overview.inventoryStatus.label,
          tone: isCritical ? AppStatusTone.danger : AppStatusTone.warning,
        ),
        AppStatusBadge(
          label:
              'Saldo ${AppFormatters.quantityFromMil(supply.currentStockMil ?? 0)} ${supply.unitType}',
          tone: AppStatusTone.info,
        ),
        AppStatusBadge(
          label:
              'Minimo ${AppFormatters.quantityFromMil(supply.minimumStockMil ?? 0)} ${supply.unitType}',
          tone: AppStatusTone.neutral,
        ),
        AppStatusBadge(
          label:
              'Falta ${AppFormatters.quantityFromMil(suggestion.shortageMil)} ${supply.unitType}',
          tone: isCritical ? AppStatusTone.danger : AppStatusTone.warning,
        ),
        if (lastPurchaseAt != null)
          AppStatusBadge(
            label: 'Ultima compra ${AppFormatters.shortDate(lastPurchaseAt)}',
            tone: AppStatusTone.neutral,
          ),
      ],
      footer: Wrap(
        spacing: layout.space3,
        runSpacing: layout.space3,
        children: [
          OutlinedButton.icon(
            onPressed: () => context.pushNamed(
              AppRouteNames.supplyInventory,
              extra: supply.id,
            ),
            icon: const Icon(Icons.history_rounded),
            label: const Text('Movimentos'),
          ),
          OutlinedButton.icon(
            onPressed: () =>
                context.pushNamed(AppRouteNames.supplyForm, extra: supply),
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('Detalhes'),
          ),
          FilledButton.tonalIcon(
            onPressed: () => context.pushNamed(AppRouteNames.purchaseForm),
            icon: const Icon(Icons.add_shopping_cart_rounded),
            label: const Text('Nova compra'),
          ),
        ],
      ),
    );
  }
}
