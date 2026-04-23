import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/session/session_provider.dart';
import '../../../../app/core/widgets/app_bottom_action_bar.dart';
import '../../../../app/core/widgets/app_bottom_sheet_container.dart';
import '../../../../app/core/widgets/app_card.dart';
import '../../../../app/core/widgets/app_main_drawer.dart';
import '../../../../app/core/widgets/app_input.dart';
import '../../../../app/core/widgets/app_state_card.dart';
import '../../../../app/core/widgets/app_status_badge.dart';
import '../../../../app/routes/route_names.dart';
import '../../../../app/theme/app_design_tokens.dart';
import '../../../carrinho/domain/entities/cart_item.dart';
import '../../../carrinho/presentation/providers/cart_provider.dart';
import '../../../produtos/domain/entities/modifier_group.dart';
import '../../../produtos/domain/entities/modifier_option.dart';
import '../../../produtos/domain/entities/product.dart';
import '../../../produtos/presentation/providers/product_providers.dart';
import '../providers/sales_providers.dart';

class SalesPage extends ConsumerStatefulWidget {
  const SalesPage({super.key});

  @override
  ConsumerState<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends ConsumerState<SalesPage> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(
      text: ref.read(salesSearchQueryProvider),
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

    final productsAsync = ref.watch(salesCatalogProvider);
    final cart = ref.watch(cartProvider);
    final layout = context.appLayout;

    return Scaffold(
      drawer: const AppMainDrawer(),
      appBar: AppBar(
        title: const Text('Vendas'),
        actions: [
          IconButton(
            tooltip: 'Abrir carrinho',
            onPressed: () => context.pushNamed(AppRouteNames.cart),
            icon: Badge(
              isLabelVisible: cart.totalItems > 0,
              label: Text('${cart.totalItems}'),
              child: const Icon(Icons.shopping_cart_outlined),
            ),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final horizontalPadding = constraints.maxWidth >= 900
              ? layout.pagePadding + 2
              : layout.pagePaddingCompact;
          final tileHeight = constraints.maxWidth >= 900 ? 206.0 : 188.0;
          final maxTileWidth = constraints.maxWidth >= 1200
              ? 216.0
              : constraints.maxWidth >= 720
              ? 196.0
              : 172.0;

          return Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  layout.space3,
                  horizontalPadding,
                  0,
                ),
                child: _CompactSalesHeader(
                  controller: _searchController,
                  cartItems: cart.totalItems,
                  cartIsEmpty: cart.isEmpty,
                  onChanged: (value) {
                    ref.read(salesSearchQueryProvider.notifier).state = value;
                    setState(() {});
                  },
                  onSubmitted: _submitSearch,
                  onClear: _clearSearch,
                  onScan: _scanBarcode,
                  onOpenHistory: () =>
                      context.pushNamed(AppRouteNames.salesHistory),
                  onOpenCart: () => context.pushNamed(AppRouteNames.cart),
                  onOpenCheckout: cart.isEmpty
                      ? null
                      : () => context.pushNamed(AppRouteNames.checkout),
                ),
              ),
              Expanded(
                child: productsAsync.when(
                  data: (products) {
                    if (products.isEmpty) {
                      return Padding(
                        padding: EdgeInsets.all(horizontalPadding),
                        child: const AppStateCard(
                          title: 'Nenhum produto disponivel',
                          message:
                              'A busca atual nao encontrou itens no catalogo. Ajuste o filtro ou leia um codigo pelo scanner.',
                          compact: true,
                        ),
                      );
                    }

                    return RefreshIndicator(
                      onRefresh: () async {
                        ref.invalidate(salesCatalogProvider);
                        await ref.read(salesCatalogProvider.future);
                      },
                      child: GridView.builder(
                        padding: EdgeInsets.fromLTRB(
                          horizontalPadding,
                          layout.space4,
                          horizontalPadding,
                          cart.isEmpty ? 20 : 96,
                        ),
                        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: maxTileWidth,
                          mainAxisExtent: tileHeight,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                        itemCount: products.length,
                        itemBuilder: (context, index) {
                          return _ProductTile(entry: products[index]);
                        },
                      ),
                    );
                  },
                  loading: () => const Center(
                    child: AppStateCard(
                      title: 'Atualizando catalogo',
                      message: 'Buscando produtos e variacoes para o PDV.',
                      tone: AppStateTone.loading,
                      compact: true,
                    ),
                  ),
                  error: (error, _) => Padding(
                    padding: EdgeInsets.all(horizontalPadding),
                    child: AppStateCard(
                      title: 'Falha ao carregar catalogo',
                      message: '$error',
                      tone: AppStateTone.error,
                      compact: true,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: cart.isEmpty
          ? null
          : AppBottomActionBar(
              minimum: EdgeInsets.fromLTRB(
                layout.pagePaddingCompact,
                0,
                layout.pagePaddingCompact,
                layout.pagePaddingCompact,
              ),
              child: _BottomCartBar(
                cartItems: cart.totalItems,
                totalCents: cart.totalCents,
                onOpenCart: () => context.pushNamed(AppRouteNames.cart),
                onOpenCheckout: () => context.pushNamed(AppRouteNames.checkout),
              ),
            ),
    );
  }

  Future<void> _submitSearch(String value) async {
    await _handleQuickBarcodeAdd(value);
  }

  Future<void> _scanBarcode() async {
    final barcode = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => const _BarcodeScannerSheet(),
    );

    if (!mounted || barcode == null || barcode.trim().isEmpty) {
      return;
    }

    _searchController.text = barcode;
    ref.read(salesSearchQueryProvider.notifier).state = barcode;
    setState(() {});
    await _handleQuickBarcodeAdd(barcode);
  }

  Future<void> _handleQuickBarcodeAdd(String value) async {
    final result = await ref.read(salesQuickAddProvider).addByBarcode(value);
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(result.message)));

    if (result.wasAdded) {
      _clearSearch();
    }
  }

  void _clearSearch() {
    _searchController.clear();
    ref.read(salesSearchQueryProvider.notifier).state = '';
    setState(() {});
  }
}

class _CompactSalesHeader extends StatelessWidget {
  const _CompactSalesHeader({
    required this.controller,
    required this.cartItems,
    required this.cartIsEmpty,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
    required this.onScan,
    required this.onOpenHistory,
    required this.onOpenCart,
    required this.onOpenCheckout,
  });

  final TextEditingController controller;
  final int cartItems;
  final bool cartIsEmpty;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;
  final VoidCallback onScan;
  final VoidCallback onOpenHistory;
  final VoidCallback onOpenCart;
  final VoidCallback? onOpenCheckout;

  @override
  Widget build(BuildContext context) {
    final canClear = controller.text.trim().isNotEmpty;
    final theme = Theme.of(context);
    final layout = context.appLayout;

    return AppCard(
      tone: AppCardTone.brand,
      padding: EdgeInsets.all(layout.compactCardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AppStatusBadge(
                label: 'PDV',
                tone: AppStatusTone.info,
                icon: Icons.point_of_sale_rounded,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Operação de venda',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (cartItems > 0)
                Text(
                  cartItems == 1 ? '1 item' : '$cartItems itens',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: AppInput(
                  controller: controller,
                  textInputAction: TextInputAction.search,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  hintText: 'Buscar produto ou código',
                  suffixIcon: canClear
                      ? IconButton(
                          tooltip: 'Limpar busca',
                          onPressed: onClear,
                          icon: const Icon(Icons.close_rounded),
                        )
                      : null,
                  onChanged: onChanged,
                  onSubmitted: onSubmitted,
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Ler c\u00f3digo de barras',
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: FilledButton.tonal(
                    onPressed: onScan,
                    style: FilledButton.styleFrom(
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Icon(Icons.qr_code_scanner_rounded, size: 20),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(6),
              child: Row(
                children: [
                  _HeaderQuickAction(
                    label: 'Histórico',
                    icon: Icons.history_rounded,
                    tooltip: 'Abrir histórico de vendas',
                    onTap: onOpenHistory,
                  ),
                  const SizedBox(width: 6),
                  _HeaderQuickAction(
                    label: 'Carrinho',
                    icon: Icons.shopping_cart_checkout_rounded,
                    tooltip: cartIsEmpty
                        ? 'Abrir carrinho'
                        : 'Abrir carrinho com $cartItems item(ns)',
                    badgeCount: cartItems,
                    onTap: onOpenCart,
                  ),
                  const SizedBox(width: 6),
                  _HeaderQuickAction(
                    label: 'Finalizar',
                    icon: Icons.check_circle_outline_rounded,
                    tooltip: 'Finalizar venda',
                    onTap: onOpenCheckout,
                    isPrimary: true,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderQuickAction extends StatelessWidget {
  const _HeaderQuickAction({
    required this.label,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.badgeCount = 0,
    this.isPrimary = false,
  });

  final String label;
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final int badgeCount;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foregroundColor = isPrimary
        ? colorScheme.onPrimary
        : colorScheme.onSurface;
    final backgroundColor = isPrimary
        ? colorScheme.primary
        : colorScheme.surface;
    final borderColor = isPrimary
        ? colorScheme.primary
        : colorScheme.outlineVariant;

    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: backgroundColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: borderColor),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: 40,
                minWidth: isPrimary ? 108 : 92,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Badge(
                      isLabelVisible: badgeCount > 0,
                      label: Text('$badgeCount'),
                      child: Icon(icon, size: 18, color: foregroundColor),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: foregroundColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomCartBar extends StatelessWidget {
  const _BottomCartBar({
    required this.cartItems,
    required this.totalCents,
    required this.onOpenCart,
    required this.onOpenCheckout,
  });

  final int cartItems;
  final int totalCents;
  final VoidCallback onOpenCart;
  final VoidCallback onOpenCheckout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                cartItems == 1 ? '1 item' : '$cartItems itens',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 2),
              Text(
                AppFormatters.currencyFromCents(totalCents),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: _BottomActionButton(
            label: 'Carrinho',
            icon: Icons.shopping_cart_rounded,
            onPressed: onOpenCart,
            filled: false,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          flex: 2,
          child: _BottomActionButton(
            label: 'Finalizar venda',
            icon: Icons.check_circle_outline_rounded,
            onPressed: onOpenCheckout,
            filled: true,
          ),
        ),
      ],
    );
  }
}

class _BottomActionButton extends StatelessWidget {
  const _BottomActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    required this.filled,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final child = SizedBox(
      width: double.infinity,
      height: 40,
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 6),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );

    return filled
        ? FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              minimumSize: const Size(0, 40),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: child,
          )
        : OutlinedButton(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              minimumSize: const Size(0, 40),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: child,
          );
  }
}

class _ProductTile extends ConsumerWidget {
  const _ProductTile({required this.entry});

  final SalesCatalogEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final product = entry.product;
    final outOfStock = entry.totalStockMil < 1000;
    final stockLabel =
        'Estoque ${AppFormatters.quantityFromMil(entry.totalStockMil)}';
    final secondaryDetails = [
      if (entry.hasVariants)
        '${entry.availableVariants.length} variante${entry.availableVariants.length == 1 ? '' : 's'}',
      if (product.modifierGroupCount > 0)
        '${product.modifierGroupCount} complemento${product.modifierGroupCount == 1 ? '' : 's'}',
      if (product.barcode?.isNotEmpty ?? false) 'Cód. ${product.barcode}',
    ];

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      elevation: 0,
      child: InkWell(
        onTap: outOfStock ? null : () => _addProduct(context, ref),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (product.hasPhoto) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    height: 56,
                    width: double.infinity,
                    child: Image.file(
                      File(product.primaryPhotoPath!),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => DecoratedBox(
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerLow,
                        ),
                        child: Icon(
                          Icons.image_not_supported_outlined,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      entry.displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: outOfStock
                            ? colorScheme.errorContainer.withValues(alpha: 0.4)
                            : colorScheme.primaryContainer.withValues(
                                alpha: 0.7,
                              ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: IconButton(
                        tooltip: entry.hasVariants
                            ? 'Escolher variante'
                            : 'Adicionar ao carrinho',
                        onPressed: outOfStock
                            ? null
                            : () => _addProduct(context, ref),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        icon: Icon(
                          outOfStock
                              ? Icons.block_rounded
                              : entry.hasVariants
                              ? Icons.tune_rounded
                              : Icons.add_shopping_cart_rounded,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                entry.hasPriceRange
                    ? 'A partir de ${AppFormatters.currencyFromCents(entry.startingPriceCents)}'
                    : AppFormatters.currencyFromCents(entry.startingPriceCents),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${product.unitMeasure} • $stockLabel',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 11.5,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              if (secondaryDetails.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  secondaryDetails.join(' • '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: outOfStock
                      ? colorScheme.errorContainer.withValues(alpha: 0.55)
                      : colorScheme.primaryContainer.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      outOfStock
                          ? Icons.block_rounded
                          : entry.hasVariants
                          ? Icons.tune_rounded
                          : Icons.add_shopping_cart_rounded,
                      size: 14,
                      color: outOfStock
                          ? colorScheme.error
                          : colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        outOfStock
                            ? 'Sem estoque'
                            : entry.hasVariants
                            ? 'Escolher variante'
                            : 'Adicionar',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: outOfStock
                              ? colorScheme.error
                              : colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addProduct(BuildContext context, WidgetRef ref) async {
    final selectedProduct = await _resolveSelectedProduct(context);
    if (selectedProduct == null || !context.mounted) {
      return;
    }

    final added = await _addProductWithCompatibility(
      context,
      ref,
      selectedProduct,
    );
    if (added == null || !context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            added
                ? '${selectedProduct.displayName} adicionado ao carrinho.'
                : 'Não foi possível adicionar mais unidades por falta de estoque.',
          ),
        ),
      );
  }

  Future<Product?> _resolveSelectedProduct(BuildContext context) async {
    if (!entry.hasVariants) {
      return entry.product;
    }

    final selectedVariant = await showModalBottomSheet<ProductVariant>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _VariantSelectionSheet(entry: entry),
    );
    if (selectedVariant == null) {
      return null;
    }

    return entry.buildSellableVariantProduct(selectedVariant);
  }

  Future<bool?> _addProductWithCompatibility(
    BuildContext context,
    WidgetRef ref,
    Product product,
  ) async {
    final hasOperationalModifiers =
        product.baseProductId != null && product.modifierGroupCount > 0;
    if (!hasOperationalModifiers) {
      return ref.read(cartProvider.notifier).addProduct(product);
    }

    final customization = await showModalBottomSheet<_CartCustomizationResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CustomizeCartItemSheet(product: product),
    );
    if (customization == null) {
      return null;
    }

    return ref
        .read(cartProvider.notifier)
        .addCustomizedProduct(
          product,
          modifiers: customization.modifiers,
          notes: customization.notes,
        );
  }
}

class _VariantSelectionSheet extends StatefulWidget {
  const _VariantSelectionSheet({required this.entry});

  final SalesCatalogEntry entry;

  @override
  State<_VariantSelectionSheet> createState() => _VariantSelectionSheetState();
}

class _VariantSelectionSheetState extends State<_VariantSelectionSheet> {
  String? _selectedSize;
  String? _selectedColor;

  List<String> get _sizes => widget.entry.availableVariants
      .map((variant) => variant.sizeLabel.trim())
      .where((label) => label.isNotEmpty)
      .toSet()
      .toList(growable: false);

  List<String> get _colorsForSelectedSize {
    final selectedSize = _selectedSize;
    if (selectedSize == null) {
      return const <String>[];
    }

    return widget.entry.availableVariants
        .where((variant) => variant.sizeLabel.trim() == selectedSize)
        .map((variant) => variant.colorLabel.trim())
        .where((label) => label.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  ProductVariant? get _selectedVariant {
    final selectedSize = _selectedSize;
    final selectedColor = _selectedColor;
    if (selectedSize == null || selectedColor == null) {
      return null;
    }

    for (final variant in widget.entry.availableVariants) {
      if (variant.sizeLabel.trim() == selectedSize &&
          variant.colorLabel.trim() == selectedColor) {
        return variant;
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    if (_sizes.length == 1) {
      _selectedSize = _sizes.first;
    }
    if (_colorsForSelectedSize.length == 1) {
      _selectedColor = _colorsForSelectedSize.first;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final product = widget.entry.product;
    final selectedVariant = _selectedVariant;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.entry.displayName,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${widget.entry.availableVariants.length} variantes disponíveis',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.entry.hasPriceRange
                      ? 'A partir de ${AppFormatters.currencyFromCents(widget.entry.startingPriceCents)}'
                      : AppFormatters.currencyFromCents(
                          widget.entry.startingPriceCents,
                        ),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  product.description?.trim().isNotEmpty ?? false
                      ? product.description!.trim()
                      : 'Escolha tamanho e cor para adicionar a variante correta.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Tamanho',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _sizes
                .map(
                  (size) => ChoiceChip(
                    label: Text(size),
                    selected: _selectedSize == size,
                    onSelected: (_) {
                      setState(() {
                        _selectedSize = size;
                        if (!_colorsForSelectedSize.contains(_selectedColor)) {
                          _selectedColor = null;
                        }
                        if (_colorsForSelectedSize.length == 1) {
                          _selectedColor = _colorsForSelectedSize.first;
                        }
                      });
                    },
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: 16),
          Text(
            'Cor',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          if (_selectedSize == null)
            Text(
              'Escolha um tamanho para ver as cores disponíveis.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _colorsForSelectedSize
                  .map(
                    (color) => ChoiceChip(
                      label: Text(color),
                      selected: _selectedColor == color,
                      onSelected: (_) {
                        setState(() => _selectedColor = color);
                      },
                    ),
                  )
                  .toList(growable: false),
            ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: selectedVariant == null
                ? Text(
                    'Selecione uma combinação válida para continuar.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${selectedVariant.sizeLabel} • ${selectedVariant.colorLabel}',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        AppFormatters.currencyFromCents(
                          product.salePriceCents +
                              selectedVariant.priceAdditionalCents,
                        ),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'SKU ${selectedVariant.sku} • Estoque ${AppFormatters.quantityFromMil(selectedVariant.stockMil)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: selectedVariant == null
                  ? null
                  : () => Navigator.of(context).pop(selectedVariant),
              icon: const Icon(Icons.add_shopping_cart_rounded),
              label: const Text('Adicionar variante'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CartCustomizationResult {
  const _CartCustomizationResult({
    required this.modifiers,
    required this.notes,
  });

  final List<CartItemModifier> modifiers;
  final String? notes;
}

class _CustomizeCartItemSheet extends ConsumerStatefulWidget {
  const _CustomizeCartItemSheet({required this.product});

  final Product product;

  @override
  ConsumerState<_CustomizeCartItemSheet> createState() =>
      _CustomizeCartItemSheetState();
}

class _CustomizeCartItemSheetState
    extends ConsumerState<_CustomizeCartItemSheet> {
  final _notesController = TextEditingController();
  final Set<int> _selectedOptionIds = <int>{};
  final Map<int, ModifierGroup> _groupsById = <int, ModifierGroup>{};
  final Map<int, ModifierOption> _optionsById = <int, ModifierOption>{};
  bool _isLoading = true;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.product.displayName,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            AppFormatters.currencyFromCents(widget.product.salePriceCents),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_loadError != null)
            AppStateCard(
              title: 'Falha ao carregar complementos',
              message: '$_loadError',
              tone: AppStateTone.error,
              compact: true,
              actionLabel: 'Tentar novamente',
              onAction: _retryLoad,
            )
          else if (_groupsById.isNotEmpty)
            SizedBox(
              height: 260,
              child: ListView(
                children: _groupsById.values
                    .map((group) {
                      final options = _optionsById.values
                          .where((option) => option.groupId == group.id)
                          .toList(growable: false);
                      final isSingleSelection = group.maxSelections == 1;
                      return ExpansionTile(
                        title: Text(group.name),
                        subtitle: Text(
                          [
                            group.isRequired ? 'Obrigatório' : 'Opcional',
                            'mín. ${group.minSelections}',
                            'máx. ${group.maxSelections ?? 'livre'}',
                          ].join(' • '),
                        ),
                        children: options
                            .map((option) {
                              final selected = _selectedOptionIds.contains(
                                option.id,
                              );
                              return CheckboxListTile(
                                value: selected,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                secondary: isSingleSelection
                                    ? const Icon(Icons.radio_button_checked)
                                    : const Icon(Icons.check_box_outlined),
                                title: Text(option.name),
                                subtitle: Text(
                                  option.priceDeltaCents == 0
                                      ? (option.adjustmentType == 'remove'
                                            ? 'Remoção'
                                            : 'Sem custo adicional')
                                      : '${option.adjustmentType == 'remove' ? 'Remoção' : 'Adição'} (${AppFormatters.currencyFromCents(option.priceDeltaCents)})',
                                ),
                                onChanged: (value) => _toggleOption(
                                  group: group,
                                  options: options,
                                  option: option,
                                  nextValue: value == true,
                                ),
                              );
                            })
                            .toList(growable: false),
                      );
                    })
                    .toList(growable: false),
              ),
            ),
          TextField(
            controller: _notesController,
            decoration: const InputDecoration(
              labelText: 'Observação do item (opcional)',
            ),
            minLines: 1,
            maxLines: 2,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _submitSelection,
              icon: const Icon(Icons.add_shopping_cart_rounded),
              label: const Text('Adicionar ao carrinho'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _load() async {
    final baseProductId = widget.product.baseProductId;
    if (baseProductId == null) {
      if (!mounted) {
        return;
      }
      setState(() => _isLoading = false);
      return;
    }

    try {
      final localCatalog = ref.read(localCatalogRepositoryProvider);
      final groups = await localCatalog.listModifierGroups(baseProductId);
      for (final group in groups) {
        _groupsById[group.id] = group;
        final options = await localCatalog.listModifierOptions(group.id);
        for (final option in options) {
          _optionsById[option.id] = option;
        }
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadError = error;
        _isLoading = false;
      });
      return;
    }

    if (!mounted) {
      return;
    }
    setState(() => _isLoading = false);
  }

  void _retryLoad() {
    setState(() {
      _isLoading = true;
      _loadError = null;
      _groupsById.clear();
      _optionsById.clear();
      _selectedOptionIds.clear();
    });
    _load();
  }

  void _toggleOption({
    required ModifierGroup group,
    required List<ModifierOption> options,
    required ModifierOption option,
    required bool nextValue,
  }) {
    setState(() {
      if (!nextValue) {
        _selectedOptionIds.remove(option.id);
        return;
      }

      if (group.maxSelections == 1) {
        for (final item in options) {
          _selectedOptionIds.remove(item.id);
        }
        _selectedOptionIds.add(option.id);
        return;
      }

      final selectedCount = options
          .where((item) => _selectedOptionIds.contains(item.id))
          .length;
      if (group.maxSelections != null &&
          selectedCount >= group.maxSelections!) {
        return;
      }
      _selectedOptionIds.add(option.id);
    });
  }

  void _submitSelection() {
    final validationError = _validateSelections();
    if (validationError != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(validationError)));
      return;
    }

    Navigator.of(context).pop(
      _CartCustomizationResult(
        modifiers: _buildModifiers(),
        notes: _cleanNullable(_notesController.text),
      ),
    );
  }

  String? _validateSelections() {
    for (final group in _groupsById.values) {
      final selectedCount = _selectionCountForGroup(group.id);
      if (group.isRequired && selectedCount == 0) {
        return 'Selecione pelo menos uma opção em ${group.name}.';
      }
      if (selectedCount < group.minSelections) {
        return 'Selecione no mínimo ${group.minSelections} opção(ões) em ${group.name}.';
      }
      if (group.maxSelections != null && selectedCount > group.maxSelections!) {
        return 'Selecione no máximo ${group.maxSelections} opção(ões) em ${group.name}.';
      }
    }
    return null;
  }

  int _selectionCountForGroup(int groupId) {
    var count = 0;
    for (final optionId in _selectedOptionIds) {
      final option = _optionsById[optionId];
      if (option?.groupId == groupId) {
        count++;
      }
    }
    return count;
  }

  List<CartItemModifier> _buildModifiers() {
    final modifiers = <CartItemModifier>[];
    for (final optionId in _selectedOptionIds) {
      final option = _optionsById[optionId];
      if (option == null) {
        continue;
      }
      final group = _groupsById[option.groupId];
      modifiers.add(
        CartItemModifier(
          modifierGroupId: group?.id,
          modifierOptionId: option.id,
          groupName: group?.name ?? 'Grupo',
          optionName: option.name,
          adjustmentType: option.adjustmentType,
          priceDeltaCents: option.priceDeltaCents,
        ),
      );
    }
    return modifiers;
  }

  String? _cleanNullable(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

class _BarcodeScannerSheet extends StatefulWidget {
  const _BarcodeScannerSheet();

  @override
  State<_BarcodeScannerSheet> createState() => _BarcodeScannerSheetState();
}

class _BarcodeScannerSheetState extends State<_BarcodeScannerSheet> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppBottomSheetContainer(
      title: 'Ler codigo de barras',
      subtitle:
          'Aponte a camera para o codigo. Ao identificar, o item sera procurado e adicionado ao carrinho.',
      trailing: IconButton(
        tooltip: 'Fechar',
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(Icons.close_rounded),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: SizedBox(
              height: 320,
              width: double.infinity,
              child: MobileScanner(
                controller: _controller,
                onDetect: (capture) {
                  if (_handled) {
                    return;
                  }

                  for (final barcode in capture.barcodes) {
                    final rawValue = barcode.rawValue?.trim();
                    if (rawValue == null || rawValue.isEmpty) {
                      continue;
                    }

                    _handled = true;
                    Navigator.of(context).pop(rawValue);
                    return;
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
