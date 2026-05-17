import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/providers/app_data_refresh_provider.dart';
import '../../../../app/core/session/session_provider.dart';
import '../../../../app/core/widgets/app_card.dart';
import '../../../../app/core/widgets/app_feedback.dart';
import '../../../../app/core/widgets/app_list_tile_card.dart';
import '../../../../app/core/widgets/app_main_drawer.dart';
import '../../../../app/core/widgets/app_search_field.dart';
import '../../../../app/core/widgets/app_selector_chip.dart';
import '../../../../app/core/widgets/app_state_card.dart';
import '../../../../app/core/widgets/app_status_badge.dart';
import '../../../../app/routes/route_names.dart';
import '../../../../app/core/theme/app_design_tokens.dart';
import '../../../estoque/domain/entities/inventory_item.dart';
import '../../../estoque/domain/entities/inventory_summary.dart';
import '../../../estoque/domain/services/inventory_alert_service.dart';
import '../../../estoque/presentation/providers/inventory_providers.dart';
import '../../domain/entities/product.dart';
import '../providers/product_providers.dart';

enum ProductHubTab { catalog, inventory }

class ProductsPage extends ConsumerStatefulWidget {
  const ProductsPage({super.key, this.initialTab = ProductHubTab.catalog});

  final ProductHubTab initialTab;

  @override
  ConsumerState<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends ConsumerState<ProductsPage> {
  late final TextEditingController _searchController;
  late ProductHubTab _selectedTab;

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab;
    _searchController = TextEditingController(text: _initialSearchQuery());
    _syncSearchQuery(_searchController.text);
  }

  @override
  void didUpdateWidget(covariant ProductsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTab == widget.initialTab ||
        widget.initialTab == _selectedTab) {
      return;
    }
    _selectedTab = widget.initialTab;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String>(sessionRuntimeKeyProvider, (previous, next) {
      if (previous == null || previous == next) {
        return;
      }
      ref.read(productSearchQueryProvider.notifier).state = '';
      ref.read(inventorySearchQueryProvider.notifier).state = '';
      _searchController.clear();
    });

    final layout = context.appLayout;
    final totalLabel = _buildAppBarSubtitle();

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Produtos'),
            Text(
              totalLabel,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      drawer: const AppMainDrawer(),
      floatingActionButton: _buildFloatingActionButton(context),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              layout.pagePadding,
              layout.space4,
              layout.pagePadding,
              layout.space4,
            ),
            child: AppSearchField(
              controller: _searchController,
              hintText: _selectedTab == ProductHubTab.catalog
                  ? 'Buscar produto, variação ou código'
                  : 'Buscar nome, SKU, cor ou tamanho',
              onChanged: _updateSearchQuery,
              onClear: _clearSearchQuery,
            ),
          ),
          _HubTabSelector(selectedTab: _selectedTab, onChanged: _selectTab),
          SizedBox(height: layout.space2),
          Expanded(
            child: _selectedTab == ProductHubTab.catalog
                ? _buildCatalogTab(context)
                : _buildInventoryTab(context),
          ),
        ],
      ),
    );
  }

  String _buildAppBarSubtitle() {
    return switch (_selectedTab) {
      ProductHubTab.catalog =>
        ref
            .watch(productListProvider)
            .maybeWhen(
              data: (products) => '${products.length} item(ns)',
              orElse: () => 'Catálogo',
            ),
      ProductHubTab.inventory =>
        ref
            .watch(inventoryItemsProvider)
            .maybeWhen(
              data: (items) => '${items.length} SKU(s)',
              orElse: () => 'Estoque',
            ),
    };
  }

  Widget _buildFloatingActionButton(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: () async {
        if (_selectedTab == ProductHubTab.catalog) {
          final created = await context.pushNamed(AppRouteNames.productForm);
          if (created == true) {
            ref.invalidate(productListProvider);
          }
          return;
        }

        await context.pushNamed(AppRouteNames.inventoryAdjustment);
        ref.invalidate(inventoryItemsProvider);
      },
      icon: Icon(
        _selectedTab == ProductHubTab.catalog ? Icons.add : Icons.tune_rounded,
      ),
      label: Text(
        _selectedTab == ProductHubTab.catalog ? 'Novo produto' : 'Novo ajuste',
      ),
    );
  }

  Widget _buildCatalogTab(BuildContext context) {
    final productsAsync = ref.watch(productListProvider);
    final layout = context.appLayout;

    return productsAsync.when(
      data: (products) {
        if (products.isEmpty) {
          return ListView(
            padding: EdgeInsets.fromLTRB(
              layout.pagePadding,
              layout.space4,
              layout.pagePadding,
              92,
            ),
            children: [
              AppStateCard(
                title: 'Nenhum produto cadastrado',
                message:
                    'Cadastre o primeiro item para montar o catálogo da operação.',
                actionLabel: 'Novo produto',
                onAction: () => context.pushNamed(AppRouteNames.productForm),
              ),
            ],
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(productListProvider);
            await ref.read(productListProvider.future);
          },
          child: ListView.separated(
            padding: EdgeInsets.fromLTRB(
              layout.pagePadding,
              0,
              layout.pagePadding,
              92,
            ),
            itemCount: products.length,
            separatorBuilder: (_, __) => SizedBox(height: layout.space4),
            itemBuilder: (context, index) {
              final product = products[index];
              final showGroupHeader = _shouldShowGroupHeader(
                products: products,
                index: index,
              );

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showGroupHeader) ...[
                    Padding(
                      padding: EdgeInsets.fromLTRB(2, 2, 2, layout.space3),
                      child: AppStatusBadge(
                        label: product.baseProductName ?? product.modelName!,
                        tone: AppStatusTone.info,
                        icon: Icons.layers_outlined,
                      ),
                    ),
                  ],
                  _ProductTile(product: product),
                ],
              );
            },
          ),
        );
      },
      loading: () => Padding(
        padding: EdgeInsets.all(layout.pagePadding),
        child: const AppStateCard(
          title: 'Carregando catálogo',
          message: 'Buscando produtos e variações.',
          tone: AppStateTone.loading,
          compact: true,
        ),
      ),
      error: (error, _) => Center(
        child: Padding(
          padding: EdgeInsets.all(layout.pagePadding + layout.space2),
          child: AppStateCard(
            title: 'Falha ao carregar produtos',
            message: '$error',
            tone: AppStateTone.error,
            compact: true,
            actionLabel: 'Tentar novamente',
            onAction: () => ref.invalidate(productListProvider),
          ),
        ),
      ),
    );
  }

  Widget _buildInventoryTab(BuildContext context) {
    final itemsAsync = ref.watch(inventoryItemsProvider);
    final selectedFilter = ref.watch(inventoryFilterProvider);
    final layout = context.appLayout;

    return Column(
      children: [
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: layout.pagePadding),
            itemCount: InventoryListFilter.values.length,
            separatorBuilder: (_, __) => SizedBox(width: layout.space3),
            itemBuilder: (context, index) {
              final filter = InventoryListFilter.values[index];
              return AppSelectorChip(
                label: filter.label,
                selected: selectedFilter == filter,
                icon: _inventoryFilterIcon(filter),
                tone: _inventoryFilterTone(filter),
                onSelected: (_) =>
                    ref.read(inventoryFilterProvider.notifier).state = filter,
              );
            },
          ),
        ),
        SizedBox(height: layout.space3),
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
                    92,
                  ),
                  children: [
                    _InventorySummaryPanel(summary: summary),
                    SizedBox(height: layout.space4),
                    const _InventoryQuickActions(),
                    SizedBox(height: layout.space4),
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
                message: 'Buscando o saldo atual de produtos e variações.',
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
    );
  }

  IconData _inventoryFilterIcon(InventoryListFilter filter) {
    return switch (filter) {
      InventoryListFilter.all => Icons.inventory_2_outlined,
      InventoryListFilter.belowMinimum => Icons.priority_high_rounded,
      InventoryListFilter.zeroed => Icons.remove_shopping_cart_rounded,
      InventoryListFilter.active => Icons.check_circle_outline_rounded,
    };
  }

  AppSelectorChipTone _inventoryFilterTone(InventoryListFilter filter) {
    return switch (filter) {
      InventoryListFilter.all => AppSelectorChipTone.brand,
      InventoryListFilter.belowMinimum => AppSelectorChipTone.warning,
      InventoryListFilter.zeroed => AppSelectorChipTone.danger,
      InventoryListFilter.active => AppSelectorChipTone.success,
    };
  }

  void _selectTab(ProductHubTab tab) {
    if (_selectedTab == tab) {
      return;
    }
    setState(() {
      _selectedTab = tab;
      _syncSearchQuery(_searchController.text);
    });
  }

  void _updateSearchQuery(String value) {
    _syncSearchQuery(value);
    setState(() {});
  }

  void _clearSearchQuery() {
    _searchController.clear();
    _updateSearchQuery('');
  }

  String _initialSearchQuery() {
    final initialQuery = switch (widget.initialTab) {
      ProductHubTab.catalog => ref.read(productSearchQueryProvider),
      ProductHubTab.inventory => ref.read(inventorySearchQueryProvider),
    };
    if (initialQuery.trim().isNotEmpty) {
      return initialQuery;
    }
    final fallbackQuery = switch (widget.initialTab) {
      ProductHubTab.catalog => ref.read(inventorySearchQueryProvider),
      ProductHubTab.inventory => ref.read(productSearchQueryProvider),
    };
    return fallbackQuery;
  }

  void _syncSearchQuery(String value) {
    ref.read(productSearchQueryProvider.notifier).state = value;
    ref.read(inventorySearchQueryProvider.notifier).state = value;
  }

  bool _shouldShowGroupHeader({
    required List<Product> products,
    required int index,
  }) {
    final current = products[index];
    final currentGroup = (current.baseProductName ?? current.modelName)?.trim();
    if (!current.isVariantCatalog ||
        currentGroup == null ||
        currentGroup.isEmpty) {
      return false;
    }

    if (index == 0) {
      return true;
    }

    final previous = products[index - 1];
    final previousGroup = (previous.baseProductName ?? previous.modelName)
        ?.trim()
        .toLowerCase();
    return currentGroup.toLowerCase() != previousGroup;
  }
}

class _HubTabSelector extends StatelessWidget {
  const _HubTabSelector({required this.selectedTab, required this.onChanged});

  final ProductHubTab selectedTab;
  final ValueChanged<ProductHubTab> onChanged;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: layout.pagePadding),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<ProductHubTab>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment<ProductHubTab>(
              value: ProductHubTab.catalog,
              icon: Icon(Icons.sell_outlined),
              label: Text('Catálogo'),
            ),
            ButtonSegment<ProductHubTab>(
              value: ProductHubTab.inventory,
              icon: Icon(Icons.inventory_rounded),
              label: Text('Estoque'),
            ),
          ],
          selected: {selectedTab},
          onSelectionChanged: (selection) => onChanged(selection.first),
        ),
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
    return AppCard(
      padding: EdgeInsets.all(layout.compactCardPadding),
      child: Wrap(
        spacing: layout.space4,
        runSpacing: layout.space3,
        children: [
          _CompactInventoryStat(
            label: 'SKUs',
            value: '${summary.totalSkus}',
            icon: Icons.qr_code_2_rounded,
            color: context.appColors.brand.base,
          ),
          _CompactInventoryStat(
            label: 'Abaixo do minimo',
            value: '${summary.belowMinimumItems}',
            icon: Icons.priority_high_rounded,
            color: context.appColors.danger.base,
          ),
          _CompactInventoryStat(
            label: 'Zerados',
            value: '${summary.zeroedItems}',
            icon: Icons.remove_shopping_cart_rounded,
            color: context.appColors.warning.base,
          ),
          _CompactInventoryStat(
            label: 'Custo',
            value: AppFormatters.currencyFromCents(summary.estimatedCostCents),
            icon: Icons.payments_outlined,
            color: context.appColors.success.base,
          ),
        ],
      ),
    );
  }
}

class _CompactInventoryStat extends StatelessWidget {
  const _CompactInventoryStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 130, maxWidth: 190),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Flexible(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: value),
                ],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _InventoryQuickActions extends StatelessWidget {
  const _InventoryQuickActions();

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: 2,
        separatorBuilder: (_, __) => SizedBox(width: layout.space3),
        itemBuilder: (context, index) {
          return switch (index) {
            0 => SizedBox(
              width: 178,
              child: OutlinedButton.icon(
                onPressed: () =>
                    context.pushNamed(AppRouteNames.inventoryMovements),
                icon: const Icon(Icons.history_rounded),
                label: const Text('Movimentações'),
              ),
            ),
            _ => SizedBox(
              width: 188,
              child: OutlinedButton.icon(
                onPressed: () =>
                    context.pushNamed(AppRouteNames.inventoryCounts),
                icon: const Icon(Icons.fact_check_rounded),
                label: const Text('Inventário'),
              ),
            ),
          };
        },
      ),
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
        ? (item.hasVariant ? 'Variação sem atributos' : 'Produto simples')
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
              'Mínimo ${AppFormatters.quantityFromMil(item.minimumStockMil)} ${item.unitMeasure}',
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

class _ProductTileLeading extends StatelessWidget {
  const _ProductTileLeading({
    required this.product,
    required this.stockLow,
    required this.stockLowColor,
    required this.stockLowSurface,
    required this.brandColor,
    required this.brandSurface,
  });

  final Product product;
  final bool stockLow;
  final Color stockLowColor;
  final Color stockLowSurface;
  final Color brandColor;
  final Color brandSurface;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(context.appLayout.radiusMd);
    if (product.hasPhoto) {
      return ClipRRect(
        key: ValueKey('product-list-thumbnail-${product.id}'),
        borderRadius: radius,
        child: SizedBox(
          width: 56,
          height: 56,
          child: Image.file(
            File(product.primaryPhotoPath!),
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                _ProductTileIconFallback(
                  productId: product.id,
                  stockLow: stockLow,
                  stockLowColor: stockLowColor,
                  stockLowSurface: stockLowSurface,
                  brandColor: brandColor,
                  brandSurface: brandSurface,
                ),
          ),
        ),
      );
    }

    return _ProductTileIconFallback(
      productId: product.id,
      stockLow: stockLow,
      stockLowColor: stockLowColor,
      stockLowSurface: stockLowSurface,
      brandColor: brandColor,
      brandSurface: brandSurface,
    );
  }
}

class _ProductTileIconFallback extends StatelessWidget {
  const _ProductTileIconFallback({
    required this.productId,
    required this.stockLow,
    required this.stockLowColor,
    required this.stockLowSurface,
    required this.brandColor,
    required this.brandSurface,
  });

  final int productId;
  final bool stockLow;
  final Color stockLowColor;
  final Color stockLowSurface;
  final Color brandColor;
  final Color brandSurface;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: ValueKey('product-list-thumbnail-fallback-$productId'),
      decoration: BoxDecoration(
        color: stockLow ? stockLowSurface : brandSurface,
        borderRadius: BorderRadius.circular(context.appLayout.radiusMd),
      ),
      child: SizedBox(
        width: 56,
        height: 56,
        child: Icon(
          stockLow ? Icons.inventory_2_outlined : Icons.sell_outlined,
          size: context.appLayout.iconLg,
          color: stockLow ? stockLowColor : brandColor,
        ),
      ),
    );
  }
}

class _ProductTile extends ConsumerWidget {
  const _ProductTile({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = context.appColors;
    final stockLow = product.stockMil < 1000;
    final subtitleParts = <String>[
      if (product.catalogSubtitle != null) product.catalogSubtitle!,
      if (product.categoryName?.trim().isNotEmpty ?? false)
        product.categoryName!,
      if (product.barcode?.trim().isNotEmpty ?? false)
        'Codigo ${product.barcode}',
    ];
    final detailLine = <String>[
      if (subtitleParts.isNotEmpty) subtitleParts.join(' • '),
      '${AppFormatters.quantityFromMil(product.stockMil)} ${product.unitMeasure} em estoque',
    ];
    final hasModifiers = product.modifierGroupCount > 0;

    return AppListTileCard(
      title: product.displayName,
      subtitle: detailLine.join(' • '),
      leading: _ProductTileLeading(
        product: product,
        stockLow: stockLow,
        stockLowColor: tokens.stockLow.onSurface,
        stockLowSurface: tokens.stockLow.surface,
        brandColor: tokens.brand.base,
        brandSurface: tokens.brand.surface,
      ),
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            AppFormatters.currencyFromCents(product.salePriceCents),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: context.appLayout.space2),
          Text(
            stockLow
                ? 'Estoque baixo'
                : product.isActive
                ? 'Ativo'
                : 'Inativo',
            style: theme.textTheme.labelSmall?.copyWith(
              color: stockLow
                  ? tokens.stockLow.onSurface
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      badges: [
        if (!product.isActive)
          const AppStatusBadge(label: 'Inativo', tone: AppStatusTone.neutral),
        if (product.isVariantCatalog)
          const AppStatusBadge(label: 'Variação', tone: AppStatusTone.info),
        if (hasModifiers)
          AppStatusBadge(
            label:
                '+${product.modifierGroupCount} complemento${product.modifierGroupCount == 1 ? '' : 's'}',
            tone: AppStatusTone.info,
          ),
      ],
      footer: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _openEditor(context, ref),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Editar'),
            ),
          ),
          SizedBox(width: context.appLayout.space4),
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: () => _delete(context, ref),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Excluir'),
            ),
          ),
        ],
      ),
      onTap: () => _openEditor(context, ref),
      tone: stockLow ? AppCardTone.warning : AppCardTone.standard,
    );
  }

  Future<void> _openEditor(BuildContext context, WidgetRef ref) async {
    final updated = await context.pushNamed(
      AppRouteNames.productForm,
      extra: product,
    );
    if (updated == true) {
      ref.invalidate(productListProvider);
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Excluir produto'),
          content: Text('Deseja excluir "${product.displayName}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Excluir'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await ref.read(productRepositoryProvider).delete(product.id);
      ref.read(appDataRefreshProvider.notifier).state++;
      ref.invalidate(productListProvider);
      if (!context.mounted) {
        return;
      }
      AppFeedback.success(
        context,
        'Produto "${product.displayName}" excluido.',
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      AppFeedback.error(context, 'Nao foi possivel excluir o produto: $error');
    }
  }
}
