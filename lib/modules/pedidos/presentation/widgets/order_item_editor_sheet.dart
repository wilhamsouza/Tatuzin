import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/widgets/app_card.dart';
import '../../../../app/core/widgets/app_input.dart';
import '../../../produtos/domain/entities/modifier_group.dart';
import '../../../produtos/domain/entities/modifier_option.dart';
import '../../../produtos/presentation/providers/product_providers.dart';
import '../../domain/entities/operational_order_item_modifier.dart';
import '../providers/order_providers.dart';
import '../support/order_ui_support.dart';

class OrderItemEditorSeed {
  const OrderItemEditorSeed({
    this.orderItemId,
    required this.productId,
    required this.baseProductId,
    this.productVariantId,
    this.variantSkuSnapshot,
    this.variantColorSnapshot,
    this.variantSizeSnapshot,
    required this.productName,
    required this.unitPriceCents,
    required this.quantityUnits,
    required this.notes,
    this.selectedModifierOptionIds = const <int>{},
  });

  final int? orderItemId;
  final int productId;
  final int? baseProductId;
  final int? productVariantId;
  final String? variantSkuSnapshot;
  final String? variantColorSnapshot;
  final String? variantSizeSnapshot;
  final String productName;
  final int unitPriceCents;
  final int quantityUnits;
  final String? notes;
  final Set<int> selectedModifierOptionIds;

  bool get isEditing => orderItemId != null;
}

class OrderItemEditorResult {
  const OrderItemEditorResult({
    required this.orderItemId,
    required this.productId,
    required this.baseProductId,
    required this.productVariantId,
    required this.variantSkuSnapshot,
    required this.variantColorSnapshot,
    required this.variantSizeSnapshot,
    required this.productName,
    required this.unitPriceCents,
    required this.quantityUnits,
    required this.notes,
    required this.modifiers,
  });

  final int? orderItemId;
  final int productId;
  final int? baseProductId;
  final int? productVariantId;
  final String? variantSkuSnapshot;
  final String? variantColorSnapshot;
  final String? variantSizeSnapshot;
  final String productName;
  final int unitPriceCents;
  final int quantityUnits;
  final String? notes;
  final List<OperationalOrderItemModifierInput> modifiers;

  bool get isEditing => orderItemId != null;
}

class OrderItemEditorSheet extends ConsumerStatefulWidget {
  const OrderItemEditorSheet({super.key, this.seed});

  final OrderItemEditorSeed? seed;

  @override
  ConsumerState<OrderItemEditorSheet> createState() =>
      _OrderItemEditorSheetState();
}

class _OrderItemEditorSheetState extends ConsumerState<OrderItemEditorSheet> {
  final _searchController = TextEditingController();
  final _notesController = TextEditingController();
  final Set<int> _selectedOptionIds = <int>{};
  final Map<int, ModifierOption> _optionsById = <int, ModifierOption>{};
  final List<_ModifierGroupBundle> _modifierBundles = <_ModifierGroupBundle>[];
  OrderSellableProductOption? _selectedOption;
  String _selectedCategory = 'Todos';
  String _search = '';
  int _quantityUnits = 1;
  bool _loadingModifiers = false;
  bool _submitted = false;

  bool get _isEditing => widget.seed != null;

  @override
  void initState() {
    super.initState();
    _quantityUnits = widget.seed?.quantityUnits ?? 1;
    _notesController.text = widget.seed?.notes ?? '';
    _selectedOptionIds.addAll(
      widget.seed?.selectedModifierOptionIds ?? const <int>{},
    );
    if (_isEditing) {
      _loadModifiersForSeed();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final catalogAsync = _isEditing
        ? null
        : ref.watch(orderCatalogOptionGroupsProvider(_search));
    final seedAvailabilityAsync = _isEditing
        ? ref.watch(
            orderSellableProductAvailabilityProvider(
              OrderSellableProductKey(
                productId: widget.seed!.productId,
                productVariantId: widget.seed!.productVariantId,
              ),
            ),
          )
        : null;
    final seedAvailabilityLabel = seedAvailabilityAsync?.maybeWhen(
      data: (availability) => _availabilityLabel(
        availableQuantityMil: availability.availableQuantityMil,
        reservedQuantityMil: availability.reservedQuantityMil,
      ),
      orElse: () => null,
    );
    final selectedModifierDelta = _selectedModifierDeltaCents;
    final unitPriceCents = _selectedUnitPriceCents;
    final estimatedTotal =
        (unitPriceCents + selectedModifierDelta) * _quantityUnits;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.9,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isEditing ? 'Editar item' : 'Adicionar item',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _isEditing
                              ? 'Ajuste quantidade, adicionais, remocoes e observacao.'
                              : 'Escolha o produto, monte o item e confirme para entrar no pedido.',
                          style: theme.textTheme.bodySmall,
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
              Expanded(
                child: ListView(
                  children: [
                    _buildSectionTitle(context, 'Produto'),
                    if (_isEditing)
                      _LockedProductCard(
                        productName: widget.seed!.productName,
                        variantLabel: operationalOrderVariantSnapshotLabel(
                          sku: widget.seed!.variantSkuSnapshot,
                          color: widget.seed!.variantColorSnapshot,
                          size: widget.seed!.variantSizeSnapshot,
                        ),
                        unitPriceCents: widget.seed!.unitPriceCents,
                        availabilityLabel: seedAvailabilityLabel,
                      )
                    else ...[
                      AppInput(
                        controller: _searchController,
                        prefixIcon: const Icon(Icons.search_rounded),
                        hintText: 'Buscar produto pelo nome',
                        onChanged: (value) {
                          setState(() {
                            _search = value.trim();
                            _selectedCategory = 'Todos';
                          });
                        },
                      ),
                      const SizedBox(height: 10),
                      catalogAsync!.when(
                        data: (groups) {
                          if (groups.isEmpty) {
                            return AppCard(
                              color: colorScheme.surfaceContainerLow,
                              child: const Padding(
                                padding: EdgeInsets.all(16),
                                child: Text(
                                  'Nenhum produto disponivel para o pedido.',
                                ),
                              ),
                            );
                          }

                          final categories = <String>[
                            'Todos',
                            ...groups.map((group) => group.label),
                          ];
                          final visibleOptions = groups
                              .where(
                                (group) =>
                                    _selectedCategory == 'Todos' ||
                                    group.label == _selectedCategory,
                              )
                              .expand((group) => group.options)
                              .toList(growable: false);

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: categories
                                      .map(
                                        (category) => Padding(
                                          padding: const EdgeInsets.only(
                                            right: 8,
                                          ),
                                          child: ChoiceChip(
                                            label: Text(category),
                                            selected:
                                                _selectedCategory == category,
                                            onSelected: (_) {
                                              setState(
                                                () => _selectedCategory =
                                                    category,
                                              );
                                            },
                                          ),
                                        ),
                                      )
                                      .toList(growable: false),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: visibleOptions
                                    .map(
                                      (option) => SizedBox(
                                        width: 170,
                                        child: _ProductSelectionCard(
                                          option: option,
                                          selected:
                                              operationalOrderIsSameSellableProduct(
                                                _selectedOption?.product,
                                                option.product,
                                              ),
                                          onTap: () => _selectProduct(option),
                                        ),
                                      ),
                                    )
                                    .toList(growable: false),
                              ),
                            ],
                          );
                        },
                        loading: () => const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: CircularProgressIndicator(),
                          ),
                        ),
                        error: (error, _) => AppCard(
                          color: colorScheme.errorContainer.withValues(
                            alpha: 0.45,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text('Falha ao carregar catalogo: $error'),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    _buildSectionTitle(context, 'Quantidade'),
                    _QuantityStepper(
                      quantityUnits: _quantityUnits,
                      onDecrease: _quantityUnits > 1
                          ? () => setState(() => _quantityUnits--)
                          : null,
                      onIncrease: () => setState(() => _quantityUnits++),
                    ),
                    const SizedBox(height: 18),
                    _buildSectionTitle(context, 'Observacao do item'),
                    AppInput(
                      controller: _notesController,
                      labelText: 'Ex.: sem cebola, embalar separado...',
                      minLines: 2,
                      maxLines: 3,
                    ),
                    if (_loadingModifiers) ...[
                      const SizedBox(height: 18),
                      const Center(child: CircularProgressIndicator()),
                    ] else if (_modifierBundles.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      _buildSectionTitle(context, 'Adicionais e remocoes'),
                      const SizedBox(height: 8),
                      ..._modifierBundles.map(
                        (bundle) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _ModifierGroupCard(
                            bundle: bundle,
                            selectedOptionIds: _selectedOptionIds,
                            showError: _submitted,
                            onToggle: (option, nextValue) => _toggleOption(
                              group: bundle.group,
                              option: option,
                              options: bundle.options,
                              nextValue: nextValue,
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    _buildSectionTitle(context, 'Resumo'),
                    AppCard(
                      color: colorScheme.surfaceContainerLow,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selectedOption?.product.displayName ??
                                widget.seed?.productName ??
                                'Selecione um produto para continuar',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (_selectedVariantLabel != null) ...[
                            Text(_selectedVariantLabel!),
                            const SizedBox(height: 8),
                          ],
                          Text('Quantidade: $_quantityUnits'),
                          Text(
                            unitPriceCents == 0
                                ? 'Valor base: --'
                                : 'Valor base: ${AppFormatters.currencyFromCents(unitPriceCents)}',
                          ),
                          if (_selectedOptionIds.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _selectedOptionIds
                                  .map((optionId) => _optionsById[optionId])
                                  .whereType<ModifierOption>()
                                  .map(
                                    (option) => Chip(
                                      label: Text(
                                        option.priceDeltaCents == 0
                                            ? option.name
                                            : '${option.name} (${AppFormatters.currencyFromCents(option.priceDeltaCents)})',
                                      ),
                                    ),
                                  )
                                  .toList(growable: false),
                            ),
                          ],
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              const Expanded(
                                child: Text('Total estimado do item'),
                              ),
                              Text(
                                unitPriceCents == 0
                                    ? '--'
                                    : AppFormatters.currencyFromCents(
                                        estimatedTotal,
                                      ),
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _canSubmit ? _submit : null,
                  icon: const Icon(Icons.check_rounded),
                  label: Text(
                    _isEditing ? 'Salvar item' : 'Adicionar no pedido',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }

  bool get _canSubmit => _isEditing || _selectedOption != null;

  int get _selectedUnitPriceCents {
    if (_selectedOption != null) {
      return _selectedOption!.product.salePriceCents;
    }
    return widget.seed?.unitPriceCents ?? 0;
  }

  int get _selectedModifierDeltaCents {
    var total = 0;
    for (final optionId in _selectedOptionIds) {
      total += _optionsById[optionId]?.priceDeltaCents ?? 0;
    }
    return total;
  }

  Future<void> _loadModifiersForSeed() async {
    setState(() {
      _loadingModifiers = true;
      _submitted = false;
    });
    final baseProductId = widget.seed?.baseProductId;
    if (baseProductId == null) {
      if (!mounted) {
        return;
      }
      setState(() => _loadingModifiers = false);
      return;
    }

    await _loadModifiers(baseProductId);
  }

  Future<void> _selectProduct(OrderSellableProductOption option) async {
    final product = option.product;
    setState(() {
      _selectedOption = option;
      if (_quantityUnits * 1000 > option.availableQuantityMil) {
        _quantityUnits = option.availableQuantityMil ~/ 1000;
        if (_quantityUnits < 1) {
          _quantityUnits = 1;
        }
      }
      _selectedOptionIds.clear();
      _optionsById.clear();
      _modifierBundles.clear();
      _loadingModifiers = true;
      _submitted = false;
    });

    if (product.baseProductId == null) {
      if (!mounted) {
        return;
      }
      setState(() => _loadingModifiers = false);
      return;
    }

    await _loadModifiers(product.baseProductId!);
  }

  Future<void> _loadModifiers(int baseProductId) async {
    final localCatalog = ref.read(localCatalogRepositoryProvider);
    final bundles = <_ModifierGroupBundle>[];
    final optionsById = <int, ModifierOption>{};

    final groups = await localCatalog.listModifierGroups(baseProductId);
    for (final group in groups) {
      final options = await localCatalog.listModifierOptions(group.id);
      final activeOptions = options.where((option) => option.isActive).toList()
        ..sort((left, right) => left.sortOrder.compareTo(right.sortOrder));
      if (activeOptions.isEmpty) {
        continue;
      }
      bundles.add(_ModifierGroupBundle(group: group, options: activeOptions));
      for (final option in activeOptions) {
        optionsById[option.id] = option;
      }
    }

    bundles.sort((left, right) {
      if (left.group.isRequired == right.group.isRequired) {
        return left.group.name.compareTo(right.group.name);
      }
      return left.group.isRequired ? -1 : 1;
    });

    if (!mounted) {
      return;
    }

    setState(() {
      _modifierBundles
        ..clear()
        ..addAll(bundles);
      _optionsById
        ..clear()
        ..addAll(optionsById);
      _selectedOptionIds.removeWhere((id) => !optionsById.containsKey(id));
      _loadingModifiers = false;
    });
  }

  void _toggleOption({
    required ModifierGroup group,
    required ModifierOption option,
    required List<ModifierOption> options,
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

      final selectedCount = _selectionCountForGroup(group.id);
      if (group.maxSelections != null &&
          selectedCount >= group.maxSelections!) {
        return;
      }
      _selectedOptionIds.add(option.id);
    });
  }

  int _selectionCountForGroup(int groupId) {
    var count = 0;
    for (final optionId in _selectedOptionIds) {
      if (_optionsById[optionId]?.groupId == groupId) {
        count++;
      }
    }
    return count;
  }

  String? _validateSelections() {
    for (final bundle in _modifierBundles) {
      final group = bundle.group;
      final minimumRequired = group.isRequired && group.minSelections == 0
          ? 1
          : group.minSelections;
      final selectedCount = _selectionCountForGroup(group.id);
      if (selectedCount < minimumRequired) {
        return 'Selecione no minimo $minimumRequired opcao(oes) em ${group.name}.';
      }
      if (group.maxSelections != null && selectedCount > group.maxSelections!) {
        return 'Selecione no maximo ${group.maxSelections} opcao(oes) em ${group.name}.';
      }
    }
    return null;
  }

  void _submit() {
    setState(() => _submitted = true);
    final selectedOption = _selectedOption;
    if (!_isEditing && selectedOption != null) {
      final quantityMil = _quantityUnits * 1000;
      if (quantityMil > selectedOption.availableQuantityMil) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                operationalOrderAvailabilityErrorMessage(
                  productName: selectedOption.product.displayName,
                  availableQuantityMil: selectedOption.availableQuantityMil,
                  sku: selectedOption.product.sellableVariantSku,
                  color: selectedOption.product.sellableVariantColorLabel,
                  size: selectedOption.product.sellableVariantSizeLabel,
                ),
              ),
            ),
          );
        return;
      }
    }
    final validationError = _validateSelections();
    if (validationError != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(validationError)));
      return;
    }

    final selectedProduct = selectedOption?.product;
    final productId = selectedProduct?.id ?? widget.seed!.productId;
    final baseProductId =
        selectedProduct?.baseProductId ?? widget.seed?.baseProductId;
    final productVariantId =
        selectedProduct?.sellableVariantId ?? widget.seed?.productVariantId;
    final variantSkuSnapshot =
        selectedProduct?.sellableVariantSku ?? widget.seed?.variantSkuSnapshot;
    final variantColorSnapshot =
        selectedProduct?.sellableVariantColorLabel ??
        widget.seed?.variantColorSnapshot;
    final variantSizeSnapshot =
        selectedProduct?.sellableVariantSizeLabel ??
        widget.seed?.variantSizeSnapshot;
    final productName =
        selectedProduct?.displayName ?? widget.seed!.productName;
    final unitPriceCents =
        selectedProduct?.salePriceCents ?? widget.seed!.unitPriceCents;

    Navigator.of(context).pop(
      OrderItemEditorResult(
        orderItemId: widget.seed?.orderItemId,
        productId: productId,
        baseProductId: baseProductId,
        productVariantId: productVariantId,
        variantSkuSnapshot: variantSkuSnapshot,
        variantColorSnapshot: variantColorSnapshot,
        variantSizeSnapshot: variantSizeSnapshot,
        productName: productName,
        unitPriceCents: unitPriceCents,
        quantityUnits: _quantityUnits,
        notes: _cleanNullable(_notesController.text),
        modifiers: _buildModifierInputs(),
      ),
    );
  }

  List<OperationalOrderItemModifierInput> _buildModifierInputs() {
    final inputs = <OperationalOrderItemModifierInput>[];
    for (final optionId in _selectedOptionIds) {
      final option = _optionsById[optionId];
      if (option == null) {
        continue;
      }
      _ModifierGroupBundle? bundle;
      for (final entry in _modifierBundles) {
        if (entry.group.id == option.groupId) {
          bundle = entry;
          break;
        }
      }
      inputs.add(
        OperationalOrderItemModifierInput(
          modifierGroupId: bundle?.group.id,
          modifierOptionId: option.id,
          groupNameSnapshot: bundle?.group.name,
          optionNameSnapshot: option.name,
          adjustmentTypeSnapshot: option.adjustmentType,
          priceDeltaCents: option.priceDeltaCents,
          quantity: 1,
        ),
      );
    }
    return inputs;
  }

  String? _cleanNullable(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  String? get _selectedVariantLabel {
    final selected = _selectedOption?.product;
    if (selected != null) {
      return operationalOrderVariantSnapshotLabel(
        sku: selected.sellableVariantSku,
        color: selected.sellableVariantColorLabel,
        size: selected.sellableVariantSizeLabel,
      );
    }
    final seed = widget.seed;
    if (seed == null) {
      return null;
    }
    return operationalOrderVariantSnapshotLabel(
      sku: seed.variantSkuSnapshot,
      color: seed.variantColorSnapshot,
      size: seed.variantSizeSnapshot,
    );
  }

  String _availabilityLabel({
    required int availableQuantityMil,
    required int reservedQuantityMil,
  }) {
    return 'Disponivel: ${operationalOrderFormatQuantityMil(availableQuantityMil)} • Reservado: ${operationalOrderFormatQuantityMil(reservedQuantityMil)}';
  }
}

class _LockedProductCard extends StatelessWidget {
  const _LockedProductCard({
    required this.productName,
    required this.variantLabel,
    required this.unitPriceCents,
    required this.availabilityLabel,
  });

  final String productName;
  final String? variantLabel;
  final int unitPriceCents;
  final String? availabilityLabel;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.inventory_2_rounded),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  productName,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                if (variantLabel != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    variantLabel!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 4),
                Text(AppFormatters.currencyFromCents(unitPriceCents)),
                if (availabilityLabel != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    availabilityLabel!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductSelectionCard extends StatelessWidget {
  const _ProductSelectionCard({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final OrderSellableProductOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final product = option.product;
    final colorScheme = Theme.of(context).colorScheme;
    final variantLabel = operationalOrderVariantSnapshotLabel(
      sku: product.sellableVariantSku,
      color: product.sellableVariantColorLabel,
      size: product.sellableVariantSizeLabel,
    );

    return AppCard(
      onTap: onTap,
      color: selected ? colorScheme.primaryContainer : colorScheme.surface,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  product.displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: selected ? colorScheme.onPrimaryContainer : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.add_circle_outline,
                color: selected
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.primary,
              ),
            ],
          ),
          if (variantLabel != null) ...[
            const SizedBox(height: 6),
            Text(
              variantLabel,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: selected
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            AppFormatters.currencyFromCents(product.salePriceCents),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: selected ? colorScheme.onPrimaryContainer : null,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            (product.categoryName?.trim().isNotEmpty ?? false)
                ? product.categoryName!.trim()
                : 'Sem categoria',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: selected
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Disp.: ${operationalOrderFormatQuantityMil(option.availableQuantityMil)} • Res.: ${operationalOrderFormatQuantityMil(option.reservedQuantityMil)}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: selected
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuantityStepper extends StatelessWidget {
  const _QuantityStepper({
    required this.quantityUnits,
    required this.onDecrease,
    required this.onIncrease,
  });

  final int quantityUnits;
  final VoidCallback? onDecrease;
  final VoidCallback onIncrease;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          IconButton.filledTonal(
            onPressed: onDecrease,
            icon: const Icon(Icons.remove_rounded),
          ),
          const Spacer(),
          Column(
            children: [
              Text(
                '$quantityUnits',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                quantityUnits == 1 ? 'unidade' : 'unidades',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const Spacer(),
          IconButton.filled(
            onPressed: onIncrease,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
    );
  }
}

class _ModifierGroupCard extends StatelessWidget {
  const _ModifierGroupCard({
    required this.bundle,
    required this.selectedOptionIds,
    required this.showError,
    required this.onToggle,
  });

  final _ModifierGroupBundle bundle;
  final Set<int> selectedOptionIds;
  final bool showError;
  final void Function(ModifierOption option, bool nextValue) onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final selectedCount = bundle.options
        .where((option) => selectedOptionIds.contains(option.id))
        .length;
    final minimumRequired =
        bundle.group.isRequired && bundle.group.minSelections == 0
        ? 1
        : bundle.group.minSelections;
    final hasError = showError && selectedCount < minimumRequired;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasError ? colorScheme.error : colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  bundle.group.name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Chip(
                label: Text(
                  bundle.group.isRequired ? 'Obrigatorio' : 'Opcional',
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Min. $minimumRequired${bundle.group.maxSelections == null ? '' : ' • Max. ${bundle.group.maxSelections}'}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: bundle.options
                .map((option) {
                  final selected = selectedOptionIds.contains(option.id);
                  final label = option.priceDeltaCents == 0
                      ? option.name
                      : '${option.name} (${AppFormatters.currencyFromCents(option.priceDeltaCents)})';

                  return (bundle.group.maxSelections == 1)
                      ? ChoiceChip(
                          label: Text(label),
                          selected: selected,
                          onSelected: (value) => onToggle(option, value),
                        )
                      : FilterChip(
                          label: Text(label),
                          selected: selected,
                          onSelected: (value) => onToggle(option, value),
                        );
                })
                .toList(growable: false),
          ),
          if (hasError) ...[
            const SizedBox(height: 10),
            Text(
              'Selecione pelo menos $minimumRequired opcao(oes) neste grupo.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ModifierGroupBundle {
  const _ModifierGroupBundle({required this.group, required this.options});

  final ModifierGroup group;
  final List<ModifierOption> options;
}
