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
import '../../../../app/core/widgets/app_page_header.dart';
import '../../../../app/core/widgets/app_search_field.dart';
import '../../../../app/core/widgets/app_state_card.dart';
import '../../../../app/core/widgets/app_status_badge.dart';
import '../../../../app/routes/route_names.dart';
import '../../../../app/core/theme/app_design_tokens.dart';
import '../../domain/entities/product.dart';
import '../providers/product_providers.dart';

class ProductsPage extends ConsumerStatefulWidget {
  const ProductsPage({super.key});

  @override
  ConsumerState<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends ConsumerState<ProductsPage> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(
      text: ref.read(productSearchQueryProvider),
    );
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
      _searchController.clear();
    });

    final productsAsync = ref.watch(productListProvider);
    final layout = context.appLayout;
    final totalLabel = productsAsync.maybeWhen(
      data: (products) => '${products.length} item(ns)',
      orElse: () => 'Catalogo',
    );

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
        actions: const [
          IconButton(
            tooltip: 'Filtros do catalogo',
            onPressed: null,
            icon: Icon(Icons.filter_list_rounded),
          ),
        ],
      ),
      drawer: const AppMainDrawer(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await context.pushNamed(AppRouteNames.productForm);
          if (created == true) {
            ref.invalidate(productListProvider);
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('Novo produto'),
      ),
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
              title: 'Catalogo de produtos',
              subtitle:
                  'Consulte preco, estoque, categorias e variacoes com leitura mais clara.',
              badgeLabel: 'Operacao',
              badgeIcon: Icons.inventory_2_rounded,
              emphasized: true,
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              layout.pagePadding,
              0,
              layout.pagePadding,
              layout.space5,
            ),
            child: AppSearchField(
              controller: _searchController,
              hintText: 'Buscar produto, variacao ou codigo',
              onChanged: (value) {
                ref.read(productSearchQueryProvider.notifier).state = value;
                setState(() {});
              },
              onClear: () {
                _searchController.clear();
                ref.read(productSearchQueryProvider.notifier).state = '';
                setState(() {});
              },
            ),
          ),
          Expanded(
            child: productsAsync.when(
              data: (products) {
                if (products.isEmpty) {
                  return Padding(
                    padding: EdgeInsets.fromLTRB(
                      layout.pagePadding,
                      layout.space4,
                      layout.pagePadding,
                      92,
                    ),
                    child: AppStateCard(
                      title: 'Nenhum produto cadastrado',
                      message:
                          'Cadastre o primeiro item para montar o catalogo da operacao.',
                      actionLabel: 'Novo produto',
                      onAction: () =>
                          context.pushNamed(AppRouteNames.productForm),
                    ),
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
                    separatorBuilder: (_, __) =>
                        SizedBox(height: layout.space4),
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
                              padding: EdgeInsets.fromLTRB(
                                2,
                                2,
                                2,
                                layout.space3,
                              ),
                              child: AppStatusBadge(
                                label:
                                    product.baseProductName ??
                                    product.modelName!,
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
                  title: 'Carregando catalogo',
                  message: 'Buscando produtos e variacoes.',
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
            ),
          ),
        ],
      ),
    );
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
          const AppStatusBadge(label: 'Variacao', tone: AppStatusTone.info),
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
