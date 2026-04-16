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
import '../../../../app/routes/route_names.dart';
import '../../../../app/theme/app_design_tokens.dart';
import '../../domain/entities/product_profitability_row.dart';
import '../providers/product_providers.dart';

class ProductProfitabilityPage extends ConsumerStatefulWidget {
  const ProductProfitabilityPage({super.key});

  @override
  ConsumerState<ProductProfitabilityPage> createState() =>
      _ProductProfitabilityPageState();
}

class _ProductProfitabilityPageState
    extends ConsumerState<ProductProfitabilityPage> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(
      text: ref.read(productProfitabilitySearchQueryProvider),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rowsAsync = ref.watch(productProfitabilityRowsProvider);
    final selectedFilter = ref.watch(productProfitabilityFilterProvider);
    final selectedSort = ref.watch(productProfitabilitySortProvider);
    final layout = context.appLayout;

    return Scaffold(
      appBar: AppBar(title: const Text('Lucratividade')),
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
              title: 'Lucratividade local',
              subtitle:
                  'Produtos com ficha tecnica entram no ranking por margem. Itens sem ficha continuam visiveis, mas sem alerta falso.',
              badgeLabel: 'Produtos',
              badgeIcon: Icons.insights_rounded,
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
            child: AppSearchField(
              controller: _searchController,
              hintText: 'Buscar produto ou categoria',
              onChanged: (value) {
                ref
                        .read(productProfitabilitySearchQueryProvider.notifier)
                        .state =
                    value;
                setState(() {});
              },
              onClear: () {
                _searchController.clear();
                ref
                        .read(productProfitabilitySearchQueryProvider.notifier)
                        .state =
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
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<ProductProfitabilityFilter>(
                    initialValue: selectedFilter,
                    decoration: const InputDecoration(labelText: 'Filtro'),
                    items: ProductProfitabilityFilter.values
                        .map(
                          (filter) => DropdownMenuItem(
                            value: filter,
                            child: Text(filter.label),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      ref
                              .read(productProfitabilityFilterProvider.notifier)
                              .state =
                          value;
                    },
                  ),
                ),
                SizedBox(width: layout.space4),
                Expanded(
                  child: DropdownButtonFormField<ProductProfitabilitySort>(
                    initialValue: selectedSort,
                    decoration: const InputDecoration(labelText: 'Ordenar'),
                    items: ProductProfitabilitySort.values
                        .map(
                          (sort) => DropdownMenuItem(
                            value: sort,
                            child: Text(sort.label),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      ref
                              .read(productProfitabilitySortProvider.notifier)
                              .state =
                          value;
                    },
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: rowsAsync.when(
              data: (rows) {
                if (rows.isEmpty) {
                  return Padding(
                    padding: EdgeInsets.all(layout.pagePadding),
                    child: const AppStateCard(
                      title: 'Nenhum produto encontrado',
                      message:
                          'Ajuste a busca ou o filtro para revisar a leitura local de lucratividade.',
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(productProfitabilityRowsProvider);
                    await ref.read(productProfitabilityRowsProvider.future);
                  },
                  child: ListView.separated(
                    padding: EdgeInsets.fromLTRB(
                      layout.pagePadding,
                      0,
                      layout.pagePadding,
                      24,
                    ),
                    itemCount: rows.length,
                    separatorBuilder: (_, __) =>
                        SizedBox(height: layout.space4),
                    itemBuilder: (context, index) {
                      return _ProfitabilityTile(row: rows[index]);
                    },
                  ),
                );
              },
              loading: () => Padding(
                padding: EdgeInsets.all(layout.pagePadding),
                child: const AppStateCard(
                  title: 'Carregando lucratividade',
                  message: 'Buscando snapshots locais e custos manuais.',
                  tone: AppStateTone.loading,
                  compact: true,
                ),
              ),
              error: (error, _) => Padding(
                padding: EdgeInsets.all(layout.pagePadding),
                child: AppStateCard(
                  title: 'Falha ao carregar lucratividade',
                  message: '$error',
                  tone: AppStateTone.error,
                  compact: true,
                  actionLabel: 'Tentar novamente',
                  onAction: () =>
                      ref.invalidate(productProfitabilityRowsProvider),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfitabilityTile extends ConsumerWidget {
  const _ProfitabilityTile({required this.row});

  final ProductProfitabilityRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tone = _toneForRow(row);
    final layout = context.appLayout;
    final marginLabel = row.hasDerivedCalculation
        ? '${((row.grossMarginPercentBasisPoints ?? 0) / 100).toStringAsFixed(2)}%'
        : 'Sem ficha';

    return AppListTileCard(
      title: row.productName,
      subtitle: [
        if ((row.categoryName ?? '').trim().isNotEmpty) row.categoryName!,
        row.contextLabel,
      ].join(' • '),
      badges: [
        AppStatusBadge(
          label: row.sourceLabel,
          tone: row.hasDerivedCalculation
              ? AppStatusTone.info
              : AppStatusTone.neutral,
        ),
        AppStatusBadge(label: row.marginStatus.label, tone: tone),
      ],
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            AppFormatters.currencyFromCents(row.salePriceCents),
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          SizedBox(height: layout.space2),
          Text(
            marginLabel,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
      footer: Wrap(
        spacing: layout.space4,
        runSpacing: layout.space3,
        children: [
          _MetricText(
            label: 'Custo ativo',
            value: AppFormatters.currencyFromCents(row.activeCostCents),
          ),
          _MetricText(
            label: 'Custo manual',
            value: AppFormatters.currencyFromCents(row.manualCostCents),
          ),
          _MetricText(
            label: row.hasDerivedCalculation ? 'Lucro bruto' : 'Margem',
            value: row.hasDerivedCalculation
                ? AppFormatters.currencyFromCents(row.grossMarginCents ?? 0)
                : 'Sem calculo',
          ),
          _MetricText(
            label: 'Atualizado',
            value: row.lastCostUpdatedAt == null
                ? 'Sem snapshot'
                : AppFormatters.shortDateTime(row.lastCostUpdatedAt!),
          ),
        ],
      ),
      onTap: () async {
        final updated = await context.pushNamed(
          AppRouteNames.productForm,
          extra: (await ref
              .read(localProductRepositoryProvider)
              .findById(row.productId, includeDeleted: false)),
        );
        if (updated == true) {
          ref.invalidate(productProfitabilityRowsProvider);
          ref.invalidate(productListProvider);
        }
      },
    );
  }

  AppStatusTone _toneForRow(ProductProfitabilityRow row) {
    return switch (row.marginStatus) {
      ProductProfitabilityMarginStatus.healthy => AppStatusTone.success,
      ProductProfitabilityMarginStatus.attention => AppStatusTone.warning,
      ProductProfitabilityMarginStatus.low => AppStatusTone.danger,
      ProductProfitabilityMarginStatus.notAvailable => AppStatusTone.neutral,
    };
  }
}

class _MetricText extends StatelessWidget {
  const _MetricText({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
