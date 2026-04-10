import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/widgets/app_main_drawer.dart';
import '../../../../app/core/widgets/app_input.dart';
import '../../../../app/core/widgets/app_status_badge.dart';
import '../../../../app/routes/route_names.dart';
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
    final productsAsync = ref.watch(salesCatalogProvider);
    final cart = ref.watch(cartProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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
          final horizontalPadding = constraints.maxWidth >= 900 ? 20.0 : 12.0;
          final tileHeight = constraints.maxWidth >= 900 ? 248.0 : 236.0;
          final maxTileWidth = constraints.maxWidth >= 1200
              ? 248.0
              : constraints.maxWidth >= 720
              ? 220.0
              : 196.0;

          return Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  8,
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
                  onOpenOrders: () => context.pushNamed(AppRouteNames.orders),
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
                      return Center(
                        child: Padding(
                          padding: EdgeInsets.all(horizontalPadding),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Nenhum produto dispon\u00edvel com esse filtro.',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: () =>
                                    context.pushNamed(AppRouteNames.orders),
                                icon: const Icon(Icons.receipt_long_rounded),
                                label: const Text('Abrir pedidos operacionais'),
                              ),
                            ],
                          ),
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
                          8,
                          horizontalPadding,
                          cart.isEmpty ? 20 : 108,
                        ),
                        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: maxTileWidth,
                          mainAxisExtent: tileHeight,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                        itemCount: products.length,
                        itemBuilder: (context, index) {
                          return _ProductTile(product: products[index]);
                        },
                      ),
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => Center(
                    child: Padding(
                      padding: EdgeInsets.all(horizontalPadding),
                      child: Text('Falha ao carregar cat\u00e1logo: $error'),
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
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: _BottomCartBar(
                    cartItems: cart.totalItems,
                    totalCents: cart.totalCents,
                    onOpenCart: () => context.pushNamed(AppRouteNames.cart),
                    onOpenCheckout: () =>
                        context.pushNamed(AppRouteNames.checkout),
                  ),
                ),
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
    required this.onOpenOrders,
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
  final VoidCallback onOpenOrders;
  final VoidCallback onOpenCart;
  final VoidCallback? onOpenCheckout;

  @override
  Widget build(BuildContext context) {
    final canClear = controller.text.trim().isNotEmpty;
    final colorScheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const AppStatusBadge(
              label: 'PDV',
              tone: AppStatusTone.info,
              icon: Icons.point_of_sale_rounded,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Venda r\u00e1pida',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: AppInput(
                controller: controller,
                textInputAction: TextInputAction.search,
                prefixIcon: const Icon(Icons.search, size: 20),
                hintText: 'Buscar produto, modelo, variação ou código',
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
                width: 48,
                height: 48,
                child: FilledButton.tonal(
                  onPressed: onScan,
                  style: FilledButton.styleFrom(
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Icon(
                    Icons.qr_code_scanner_rounded,
                    size: 22,
                    color: colorScheme.primary,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _HeaderActionIconButton(
              tooltip: 'Hist\u00f3rico',
              icon: Icons.history_rounded,
              onTap: onOpenHistory,
            ),
            const SizedBox(width: 6),
            _HeaderActionIconButton(
              tooltip: 'Pedidos',
              icon: Icons.receipt_long_rounded,
              onTap: onOpenOrders,
            ),
            const SizedBox(width: 6),
            _HeaderActionIconButton(
              tooltip: cartIsEmpty ? 'Carrinho' : 'Carrinho ($cartItems)',
              icon: Icons.shopping_cart_checkout_rounded,
              onTap: onOpenCart,
              badgeCount: cartItems,
            ),
            const SizedBox(width: 6),
            _HeaderActionIconButton(
              tooltip: 'Checkout',
              icon: Icons.point_of_sale_rounded,
              onTap: onOpenCheckout,
              isEnabled: onOpenCheckout != null,
            ),
          ],
        ),
      ],
    );
  }
}

class _HeaderActionIconButton extends StatelessWidget {
  const _HeaderActionIconButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.badgeCount = 0,
    this.isEnabled = true,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onTap;
  final int badgeCount;
  final bool isEnabled;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final enabled = isEnabled && onTap != null;

    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 42,
        height: 42,
        child: OutlinedButton(
          onPressed: enabled ? onTap : null,
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.zero,
            side: BorderSide(
              color: colorScheme.outlineVariant.withValues(
                alpha: enabled ? 1 : 0.6,
              ),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Badge(
            isLabelVisible: badgeCount > 0,
            label: Text('$badgeCount'),
            child: Icon(
              icon,
              size: 18,
              color: enabled
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
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
      height: 42,
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
              minimumSize: const Size(0, 42),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: child,
          )
        : OutlinedButton(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              minimumSize: const Size(0, 42),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: child,
          );
  }
}

class _ProductTile extends ConsumerWidget {
  const _ProductTile({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final outOfStock = product.stockMil < 1000;
    final stockLabel =
        'Estoque ${AppFormatters.quantityFromMil(product.stockMil)}';
    final details = [
      product.unitMeasure,
      stockLabel,
      if (product.modifierGroupCount > 0)
        '${product.modifierGroupCount} complementos',
      if (product.barcode?.isNotEmpty ?? false) 'C\u00f3d. ${product.barcode}',
    ];

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      elevation: 0,
      child: InkWell(
        onTap: outOfStock ? null : () => _addProduct(context, ref),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (product.hasPhoto) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    height: 72,
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
                const SizedBox(height: 10),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      product.displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 34,
                    height: 34,
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
                        tooltip: 'Adicionar ao carrinho',
                        onPressed: outOfStock
                            ? null
                            : () => _addProduct(context, ref),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        icon: Icon(
                          outOfStock
                              ? Icons.block_rounded
                              : Icons.add_shopping_cart_rounded,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                AppFormatters.currencyFromCents(product.salePriceCents),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                details.join(' • '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 11.5,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Text(
                outOfStock ? 'Sem estoque' : 'Toque para adicionar',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: outOfStock ? colorScheme.error : colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addProduct(BuildContext context, WidgetRef ref) async {
    final added = await _addProductWithCompatibility(context, ref);
    if (added == null || !context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            added
                ? '${product.displayName} adicionado ao carrinho.'
                : 'N\u00e3o foi poss\u00edvel adicionar mais unidades por falta de estoque.',
          ),
        ),
      );
  }

  Future<bool?> _addProductWithCompatibility(
    BuildContext context,
    WidgetRef ref,
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
              labelText: 'Observacao do item (opcional)',
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
              label: const Text('Adicionar no carrinho'),
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

    final localCatalog = ref.read(localCatalogRepositoryProvider);
    final groups = await localCatalog.listModifierGroups(baseProductId);
    for (final group in groups) {
      _groupsById[group.id] = group;
      final options = await localCatalog.listModifierOptions(group.id);
      for (final option in options) {
        _optionsById[option.id] = option;
      }
    }

    if (!mounted) {
      return;
    }
    setState(() => _isLoading = false);
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Ler c\u00f3digo de barras',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: 'Fechar',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 8),
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
          const SizedBox(height: 12),
          const Text(
            'Aponte a c\u00e2mera para o c\u00f3digo. Ao identificar, o item ser\u00e1 procurado e adicionado ao carrinho.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
