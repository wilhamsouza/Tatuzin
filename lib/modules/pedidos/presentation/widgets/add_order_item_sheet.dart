import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/widgets/app_card.dart';
import '../../../../app/core/widgets/app_input.dart';
import '../../../produtos/domain/entities/modifier_group.dart';
import '../../../produtos/domain/entities/modifier_option.dart';
import '../../../produtos/domain/entities/product.dart';
import '../../../produtos/presentation/providers/product_providers.dart';
import '../../domain/entities/operational_order_item_modifier.dart';
import '../providers/order_providers.dart';

class AddOperationalOrderItemResult {
  const AddOperationalOrderItemResult({
    required this.product,
    required this.quantityUnits,
    required this.notes,
    required this.modifiers,
  });

  final Product product;
  final int quantityUnits;
  final String? notes;
  final List<OperationalOrderItemModifierInput> modifiers;
}

class AddOrderItemSheet extends ConsumerStatefulWidget {
  const AddOrderItemSheet({super.key});

  @override
  ConsumerState<AddOrderItemSheet> createState() => _AddOrderItemSheetState();
}

class _AddOrderItemSheetState extends ConsumerState<AddOrderItemSheet> {
  final _searchController = TextEditingController();
  final _notesController = TextEditingController();
  final Set<int> _selectedOptionIds = <int>{};
  final Map<int, ModifierOption> _optionsById = <int, ModifierOption>{};
  final List<_ModifierGroupBundle> _modifierBundles = <_ModifierGroupBundle>[];
  Product? _selectedProduct;
  String _search = '';
  int _quantityUnits = 1;
  bool _loadingModifiers = false;
  bool _submitted = false;

  @override
  void dispose() {
    _searchController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catalogAsync = ref.watch(orderCatalogProvider(_search));
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final selectedModifierDelta = _selectedModifierDeltaCents;
    final estimatedTotal = _selectedProduct == null
        ? 0
        : (_selectedProduct!.salePriceCents + selectedModifierDelta) *
              _quantityUnits;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.88,
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
                          'Adicionar item',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Selecione o produto, ajuste a quantidade e confirme os modificadores.',
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
                    AppInput(
                      controller: _searchController,
                      prefixIcon: const Icon(Icons.search_rounded),
                      hintText: 'Buscar produto pelo nome ou codigo',
                      onChanged: (value) =>
                          setState(() => _search = value.trim()),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 220,
                      child: catalogAsync.when(
                        data: (products) {
                          if (products.isEmpty) {
                            return AppCard(
                              color: colorScheme.surfaceContainerLow,
                              child: const Center(
                                child: Text('Nenhum produto encontrado.'),
                              ),
                            );
                          }
                          return ListView.separated(
                            itemCount: products.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final product = products[index];
                              final selected =
                                  _selectedProduct?.id == product.id;
                              return _SelectableProductTile(
                                product: product,
                                selected: selected,
                                onTap: () => _selectProduct(product),
                              );
                            },
                          );
                        },
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (error, _) => AppCard(
                          color: colorScheme.errorContainer.withValues(
                            alpha: 0.45,
                          ),
                          child: Center(
                            child: Text('Falha ao buscar catalogo: $error'),
                          ),
                        ),
                      ),
                    ),
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
                      _buildSectionTitle(context, 'Modificadores e adicionais'),
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
                            _selectedProduct?.displayName ??
                                'Selecione um produto para continuar',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text('Quantidade: $_quantityUnits'),
                          Text(
                            _selectedProduct == null
                                ? 'Valor base: --'
                                : 'Valor base: ${AppFormatters.currencyFromCents(_selectedProduct!.salePriceCents)}',
                          ),
                          if (_selectedOptionIds.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Selecionados',
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
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
                                _selectedProduct == null
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
                  onPressed: _selectedProduct == null ? null : _submit,
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Adicionar no pedido'),
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

  Future<void> _selectProduct(Product product) async {
    setState(() {
      _selectedProduct = product;
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

    final localCatalog = ref.read(localCatalogRepositoryProvider);
    final groups = await localCatalog.listModifierGroups(
      product.baseProductId!,
    );
    for (final group in groups) {
      final options = await localCatalog.listModifierOptions(group.id);
      final activeOptions = options.where((option) => option.isActive).toList()
        ..sort((left, right) => left.sortOrder.compareTo(right.sortOrder));
      if (activeOptions.isEmpty) {
        continue;
      }
      _modifierBundles.add(
        _ModifierGroupBundle(group: group, options: activeOptions),
      );
      for (final option in activeOptions) {
        _optionsById[option.id] = option;
      }
    }

    _modifierBundles.sort((left, right) {
      if (left.group.isRequired == right.group.isRequired) {
        return left.group.name.compareTo(right.group.name);
      }
      return left.group.isRequired ? -1 : 1;
    });

    if (!mounted) {
      return;
    }
    setState(() => _loadingModifiers = false);
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

  int get _selectedModifierDeltaCents {
    var total = 0;
    for (final optionId in _selectedOptionIds) {
      total += _optionsById[optionId]?.priceDeltaCents ?? 0;
    }
    return total;
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
    final validationError = _validateSelections();
    if (validationError != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(validationError)));
      return;
    }

    Navigator.of(context).pop(
      AddOperationalOrderItemResult(
        product: _selectedProduct!,
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
}

class _SelectableProductTile extends StatelessWidget {
  const _SelectableProductTile({
    required this.product,
    required this.selected,
    required this.onTap,
  });

  final Product product;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AppCard(
      onTap: onTap,
      color: selected ? colorScheme.primaryContainer : null,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.displayName,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: selected ? colorScheme.onPrimaryContainer : null,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  AppFormatters.currencyFromCents(product.salePriceCents),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: selected ? colorScheme.onPrimaryContainer : null,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Icon(
            selected ? Icons.check_circle_rounded : Icons.add_circle_outline,
            color: selected
                ? colorScheme.onPrimaryContainer
                : colorScheme.primary,
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
