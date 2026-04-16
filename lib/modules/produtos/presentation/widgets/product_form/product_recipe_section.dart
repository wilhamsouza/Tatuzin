import 'package:flutter/material.dart';

import '../../../../../app/core/formatters/app_formatters.dart';
import '../../../../../app/core/utils/quantity_parser.dart';
import '../../../../../app/core/widgets/app_card.dart';
import '../../../../../app/core/widgets/app_section_card.dart';
import '../../../../../app/core/widgets/app_status_badge.dart';
import '../../../../../app/theme/app_design_tokens.dart';
import '../../../../insumos/domain/entities/supply.dart';
import '../../../domain/services/product_cost_calculator.dart';
import 'product_form_models.dart';

class ProductRecipeSection extends StatelessWidget {
  const ProductRecipeSection({
    super.key,
    required this.items,
    required this.summary,
    required this.isLoadingRecipe,
    required this.isLoadingSupplies,
    required this.onAddItem,
    required this.onEditItem,
    required this.onRemoveItem,
  });

  final List<EditableProductRecipeItemDraft> items;
  final ProductCostSummary summary;
  final bool isLoadingRecipe;
  final bool isLoadingSupplies;
  final VoidCallback onAddItem;
  final ValueChanged<int> onEditItem;
  final ValueChanged<int> onRemoveItem;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;

    return AppSectionCard(
      title: 'Ficha tecnica',
      subtitle:
          'Monte a composicao do produto com insumos locais e veja o custo variavel em tempo real.',
      trailing: FilledButton.tonalIcon(
        onPressed: isLoadingSupplies ? null : onAddItem,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Adicionar insumo'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isLoadingRecipe) const LinearProgressIndicator(minHeight: 3),
          if (isLoadingRecipe) SizedBox(height: layout.space4),
          if (items.isEmpty)
            AppCard(
              tone: AppCardTone.muted,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ficha tecnica opcional',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: layout.space3),
                  Text(
                    'Produtos sem ficha tecnica continuam vendaveis. Quando houver composicao, o custo salvo do produto passa a ser espelhado a partir desta ficha.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            )
          else ...[
            Wrap(
              spacing: layout.space3,
              runSpacing: layout.space3,
              children: [
                AppStatusBadge(
                  label:
                      '${items.length} ${items.length == 1 ? 'insumo' : 'insumos'}',
                  tone: AppStatusTone.info,
                ),
                AppStatusBadge(
                  label:
                      'Total ${AppFormatters.currencyFromCents(summary.variableCostSnapshotCents)}',
                  tone: AppStatusTone.success,
                ),
              ],
            ),
            SizedBox(height: layout.space4),
            for (var index = 0; index < items.length; index++) ...[
              _RecipeItemTile(
                item: items[index],
                costSummary: summary.items[index],
                onEdit: () => onEditItem(index),
                onRemove: () => onRemoveItem(index),
              ),
              if (index != items.length - 1) SizedBox(height: layout.space4),
            ],
          ],
        ],
      ),
    );
  }
}

class _RecipeItemTile extends StatelessWidget {
  const _RecipeItemTile({
    required this.item,
    required this.costSummary,
    required this.onEdit,
    required this.onRemove,
  });

  final EditableProductRecipeItemDraft item;
  final ProductCostComponentSummary costSummary;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    return AppCard(
      tone: AppCardTone.standard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.supply.name,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: layout.space2),
                    Text(
                      '${AppFormatters.quantityFromMil(item.quantityUsedMil)} ${item.supply.unitType} • ${AppFormatters.currencyFromCents(costSummary.unitUsageCostCentsRounded)}/${item.supply.unitType}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Editar item',
              ),
              IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Remover item',
              ),
            ],
          ),
          SizedBox(height: layout.space4),
          Wrap(
            spacing: layout.space3,
            runSpacing: layout.space3,
            children: [
              AppStatusBadge(
                label:
                    'Subtotal ${AppFormatters.currencyFromCents(costSummary.itemCostCents)}',
                tone: AppStatusTone.info,
              ),
              if (item.wasteBasisPoints > 0)
                AppStatusBadge(
                  label:
                      'Perda ${(item.wasteBasisPoints / 100).toStringAsFixed(2)}%',
                  tone: AppStatusTone.warning,
                ),
              if ((item.notes ?? '').trim().isNotEmpty)
                const AppStatusBadge(
                  label: 'Com observacao',
                  tone: AppStatusTone.neutral,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class ProductRecipeItemEditorSheet extends StatefulWidget {
  const ProductRecipeItemEditorSheet({
    super.key,
    required this.supplies,
    this.initialItem,
  });

  final List<Supply> supplies;
  final EditableProductRecipeItemDraft? initialItem;

  @override
  State<ProductRecipeItemEditorSheet> createState() =>
      _ProductRecipeItemEditorSheetState();
}

class _ProductRecipeItemEditorSheetState
    extends State<ProductRecipeItemEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _searchController;
  late final TextEditingController _quantityController;
  late final TextEditingController _wasteController;
  late final TextEditingController _notesController;

  int? _selectedSupplyId;

  Supply? get _selectedSupply {
    for (final supply in widget.supplies) {
      if (supply.id == _selectedSupplyId) {
        return supply;
      }
    }
    return widget.initialItem?.supply.id == _selectedSupplyId
        ? widget.initialItem?.supply
        : null;
  }

  @override
  void initState() {
    super.initState();
    final initial = widget.initialItem;
    _selectedSupplyId = initial?.supply.id;
    _searchController = TextEditingController(text: initial?.supply.name ?? '');
    _quantityController = TextEditingController(
      text: initial == null
          ? '1'
          : AppFormatters.quantityFromMil(initial.quantityUsedMil),
    );
    _wasteController = TextEditingController(
      text: initial == null
          ? ''
          : (initial.wasteBasisPoints / 100).toStringAsFixed(2),
    );
    _notesController = TextEditingController(text: initial?.notes ?? '');
  }

  @override
  void dispose() {
    _searchController.dispose();
    _quantityController.dispose();
    _wasteController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final theme = Theme.of(context);
    final query = _searchController.text.trim().toLowerCase();
    final filteredSupplies = widget.supplies
        .where((supply) {
          if (query.isEmpty) {
            return true;
          }
          final supplierName = supply.defaultSupplierName?.toLowerCase() ?? '';
          final sku = supply.sku?.toLowerCase() ?? '';
          return supply.name.toLowerCase().contains(query) ||
              supplierName.contains(query) ||
              sku.contains(query);
        })
        .toList(growable: false);
    final preview = _buildPreview();

    return Padding(
      padding: EdgeInsets.only(
        left: layout.pagePadding,
        right: layout.pagePadding,
        bottom: MediaQuery.of(context).viewInsets.bottom + layout.pagePadding,
      ),
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(layout.radiusXl),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.88,
          child: Padding(
            padding: EdgeInsets.all(layout.pagePadding),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.initialItem == null
                        ? 'Adicionar insumo'
                        : 'Editar item da ficha',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: layout.space2),
                  Text(
                    'Selecione o insumo e informe a quantidade de uso do produto.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  SizedBox(height: layout.space5),
                  TextFormField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      labelText: 'Buscar insumo',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  SizedBox(height: layout.space4),
                  if (_selectedSupply != null)
                    AppCard(
                      tone: AppCardTone.info,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selectedSupply!.name,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: layout.space2),
                          Text(
                            'Compra em ${_selectedSupply!.purchaseUnitType} • uso em ${_selectedSupply!.unitType} • fator ${_selectedSupply!.normalizedConversionFactor}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  if (_selectedSupply != null) SizedBox(height: layout.space4),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _quantityController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: _selectedSupply == null
                                ? 'Quantidade usada'
                                : 'Quantidade usada (${_selectedSupply!.unitType})',
                          ),
                          validator: (value) {
                            if (_selectedSupply == null) {
                              return 'Selecione um insumo';
                            }
                            if (QuantityParser.parseToMil(value ?? '') <= 0) {
                              return 'Informe uma quantidade valida';
                            }
                            return null;
                          },
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      SizedBox(width: layout.space4),
                      Expanded(
                        child: TextFormField(
                          controller: _wasteController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Perda (%)',
                            hintText: 'Opcional',
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: layout.space4),
                  TextFormField(
                    controller: _notesController,
                    decoration: const InputDecoration(
                      labelText: 'Observacao',
                      hintText: 'Opcional',
                    ),
                    minLines: 2,
                    maxLines: 3,
                  ),
                  SizedBox(height: layout.space4),
                  if (preview != null)
                    AppCard(
                      tone: AppCardTone.success,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Subtotal previsto',
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            AppFormatters.currencyFromCents(
                              preview.itemCostCents,
                            ),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  SizedBox(height: layout.space5),
                  Text(
                    'Insumos disponiveis',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: layout.space3),
                  Expanded(
                    child: filteredSupplies.isEmpty
                        ? Center(
                            child: Text(
                              'Nenhum insumo encontrado para esta busca.',
                              style: theme.textTheme.bodyMedium,
                              textAlign: TextAlign.center,
                            ),
                          )
                        : ListView.separated(
                            itemCount: filteredSupplies.length,
                            separatorBuilder: (_, __) =>
                                SizedBox(height: layout.space3),
                            itemBuilder: (context, index) {
                              final supply = filteredSupplies[index];
                              final selected = _selectedSupplyId == supply.id;
                              return AppCard(
                                onTap: () {
                                  setState(() {
                                    _selectedSupplyId = supply.id;
                                  });
                                },
                                tone: selected
                                    ? AppCardTone.brand
                                    : AppCardTone.standard,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      supply.name,
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    SizedBox(height: layout.space2),
                                    Text(
                                      '${supply.purchaseUnitType} -> ${supply.unitType} • ${AppFormatters.currencyFromCents(supply.lastPurchasePriceCents)}',
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                  SizedBox(height: layout.space5),
                  FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.check_rounded),
                    label: Text(
                      widget.initialItem == null
                          ? 'Adicionar a ficha'
                          : 'Salvar item',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  ProductCostComponentSummary? _buildPreview() {
    final selectedSupply = _selectedSupply;
    if (selectedSupply == null) {
      return null;
    }

    final quantityUsedMil = QuantityParser.parseToMil(_quantityController.text);
    if (quantityUsedMil <= 0) {
      return null;
    }

    final wasteBasisPoints =
        (double.tryParse(_wasteController.text.replaceAll(',', '.')) ?? 0) *
        100;
    final summary = ProductCostCalculator.calculate(
      salePriceCents: 0,
      items: [
        ProductCostComponentInput(
          supplyId: selectedSupply.id,
          supplyName: selectedSupply.name,
          purchaseUnitType: selectedSupply.purchaseUnitType,
          unitType: selectedSupply.unitType,
          conversionFactor: selectedSupply.conversionFactor,
          lastPurchasePriceCents: selectedSupply.lastPurchasePriceCents,
          quantityUsedMil: quantityUsedMil,
          wasteBasisPoints: wasteBasisPoints.round(),
          notes: _notesController.text,
        ),
      ],
    );
    return summary.items.isEmpty ? null : summary.items.first;
  }

  void _save() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final selectedSupply = _selectedSupply;
    if (selectedSupply == null) {
      return;
    }

    final wastePercent = double.tryParse(
      _wasteController.text.trim().replaceAll(',', '.'),
    );
    final draft = EditableProductRecipeItemDraft(
      supply: selectedSupply,
      quantityUsedMil: QuantityParser.parseToMil(_quantityController.text),
      wasteBasisPoints: ((wastePercent ?? 0) * 100).round(),
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
    );
    Navigator.of(context).pop(draft);
  }
}
