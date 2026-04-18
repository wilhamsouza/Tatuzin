import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/utils/quantity_parser.dart';
import '../../../../app/core/widgets/app_bottom_sheet_container.dart';
import '../../../../app/core/widgets/app_feedback.dart';
import '../../../../app/core/widgets/app_list_tile_card.dart';
import '../../../../app/core/widgets/app_main_drawer.dart';
import '../../../../app/core/widgets/app_page_header.dart';
import '../../../../app/core/widgets/app_search_field.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import '../../../../app/core/widgets/app_state_card.dart';
import '../../../../app/core/widgets/app_status_badge.dart';
import '../../../../app/routes/route_names.dart';
import '../../../../app/theme/app_design_tokens.dart';
import '../../domain/entities/inventory_adjustment_input.dart';
import '../../domain/entities/inventory_item.dart';
import '../providers/inventory_providers.dart';

class InventoryAdjustmentPage extends ConsumerStatefulWidget {
  const InventoryAdjustmentPage({super.key});

  @override
  ConsumerState<InventoryAdjustmentPage> createState() =>
      _InventoryAdjustmentPageState();
}

class _InventoryAdjustmentPageState
    extends ConsumerState<InventoryAdjustmentPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _quantityController;
  late final TextEditingController _notesController;
  InventoryItem? _selectedItem;
  InventoryAdjustmentDirection _direction =
      InventoryAdjustmentDirection.inbound;
  InventoryAdjustmentReason _reason = InventoryAdjustmentReason.correction;

  @override
  void initState() {
    super.initState();
    _quantityController = TextEditingController();
    _notesController = TextEditingController();
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final activeItemsAsync = ref.watch(inventoryActiveItemOptionsProvider);
    final actionState = ref.watch(inventoryActionControllerProvider);
    final activeItems = activeItemsAsync.valueOrNull ?? const <InventoryItem>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Ajuste manual de estoque')),
      drawer: const AppMainDrawer(),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            layout.pagePadding,
            layout.pagePadding,
            layout.pagePadding,
            layout.pagePadding,
          ),
          children: [
            const AppPageHeader(
              title: 'Ajuste manual',
              subtitle:
                  'Registre entradas e saidas controladas sem trocar a origem do saldo atual.',
              badgeLabel: 'Controle',
              badgeIcon: Icons.tune_rounded,
              emphasized: true,
            ),
            SizedBox(height: layout.space5),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => context.pushNamed(AppRouteNames.inventory),
                    icon: const Icon(Icons.inventory_2_outlined),
                    label: const Text('Estoque atual'),
                  ),
                ),
                SizedBox(width: layout.space4),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () =>
                        context.pushNamed(AppRouteNames.inventoryMovements),
                    icon: const Icon(Icons.history_rounded),
                    label: const Text('Ver extrato'),
                  ),
                ),
              ],
            ),
            SizedBox(height: layout.space5),
            AppSectionCard(
              title: 'Item',
              subtitle:
                  'Selecione o produto simples ou a variante que recebera o ajuste.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_selectedItem == null)
                    const AppStateCard(
                      title: 'Nenhum item selecionado',
                      message:
                          'Escolha um SKU operacional ativo antes de registrar o ajuste.',
                      compact: true,
                    )
                  else
                    _SelectedInventoryItemCard(item: _selectedItem!),
                  SizedBox(height: layout.space4),
                  OutlinedButton.icon(
                    onPressed: activeItemsAsync.isLoading
                        ? null
                        : () => _selectItem(context, activeItems),
                    icon: const Icon(Icons.search_rounded),
                    label: Text(
                      activeItemsAsync.isLoading
                          ? 'Carregando itens'
                          : 'Selecionar item',
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: layout.space5),
            AppSectionCard(
              title: 'Ajuste',
              subtitle:
                  'Escolha o tipo, informe a quantidade e registre o motivo.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: layout.space3,
                    runSpacing: layout.space3,
                    children: [
                      for (final direction
                          in InventoryAdjustmentDirection.values)
                        ChoiceChip(
                          label: Text(direction.label),
                          selected: _direction == direction,
                          onSelected: (_) =>
                              setState(() => _direction = direction),
                        ),
                    ],
                  ),
                  SizedBox(height: layout.space4),
                  TextFormField(
                    controller: _quantityController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Quantidade',
                      hintText: 'Ex.: 1 ou 1,250',
                    ),
                    validator: (value) {
                      if (QuantityParser.parseToMil(value ?? '') <= 0) {
                        return 'Informe uma quantidade maior que zero';
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: layout.space4),
                  DropdownButtonFormField<InventoryAdjustmentReason>(
                    initialValue: _reason,
                    decoration: const InputDecoration(labelText: 'Motivo'),
                    items: [
                      for (final reason in InventoryAdjustmentReason.values)
                        DropdownMenuItem<InventoryAdjustmentReason>(
                          value: reason,
                          child: Text(reason.label),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() => _reason = value);
                    },
                  ),
                  SizedBox(height: layout.space4),
                  TextFormField(
                    controller: _notesController,
                    decoration: const InputDecoration(
                      labelText: 'Observacao',
                      hintText: 'Opcional',
                    ),
                    minLines: 2,
                    maxLines: 4,
                  ),
                ],
              ),
            ),
            SizedBox(height: layout.space5),
            if (_selectedItem != null)
              AppSectionCard(
                title: 'Saldo atual',
                subtitle:
                    'A validacao respeita a configuracao local de estoque negativo.',
                child: Wrap(
                  spacing: layout.space3,
                  runSpacing: layout.space3,
                  children: [
                    AppStatusBadge(
                      label:
                          'Saldo ${AppFormatters.quantityFromMil(_selectedItem!.currentStockMil)} ${_selectedItem!.unitMeasure}',
                      tone: AppStatusTone.info,
                    ),
                    AppStatusBadge(
                      label:
                          'Minimo ${AppFormatters.quantityFromMil(_selectedItem!.minimumStockMil)} ${_selectedItem!.unitMeasure}',
                      tone: AppStatusTone.neutral,
                    ),
                    AppStatusBadge(
                      label: _selectedItem!.allowNegativeStock
                          ? 'Aceita estoque negativo'
                          : 'Nao aceita estoque negativo',
                      tone: _selectedItem!.allowNegativeStock
                          ? AppStatusTone.warning
                          : AppStatusTone.success,
                    ),
                  ],
                ),
              ),
            SizedBox(height: layout.space5),
            FilledButton.icon(
              onPressed: actionState.isLoading ? null : _submit,
              icon: actionState.isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_circle_outline_rounded),
              label: Text(
                actionState.isLoading ? 'Salvando ajuste' : 'Confirmar ajuste',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectItem(
    BuildContext context,
    List<InventoryItem> items,
  ) async {
    final selected = await showModalBottomSheet<InventoryItem>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _InventoryItemPickerSheet(items: items),
    );
    if (selected == null) {
      return;
    }
    setState(() => _selectedItem = selected);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_selectedItem == null) {
      AppFeedback.error(context, 'Selecione um item antes de ajustar.');
      return;
    }

    try {
      await ref
          .read(inventoryActionControllerProvider.notifier)
          .adjustStock(
            InventoryAdjustmentInput(
              productId: _selectedItem!.productId,
              productVariantId: _selectedItem!.productVariantId,
              direction: _direction,
              quantityMil: QuantityParser.parseToMil(_quantityController.text),
              reason: _reason,
              notes: _notesController.text.trim().isEmpty
                  ? null
                  : _notesController.text.trim(),
            ),
          );

      final updated = await ref
          .read(inventoryRepositoryProvider)
          .findItem(
            productId: _selectedItem!.productId,
            productVariantId: _selectedItem!.productVariantId,
          );
      if (!mounted) {
        return;
      }

      setState(() {
        _selectedItem = updated;
        _quantityController.clear();
        _notesController.clear();
        _direction = InventoryAdjustmentDirection.inbound;
        _reason = InventoryAdjustmentReason.correction;
      });
      AppFeedback.success(context, 'Ajuste de estoque registrado com sucesso.');
    } catch (error) {
      if (!mounted) {
        return;
      }
      AppFeedback.error(context, 'Nao foi possivel registrar o ajuste: $error');
    }
  }
}

class _SelectedInventoryItemCard extends StatelessWidget {
  const _SelectedInventoryItemCard({required this.item});

  final InventoryItem item;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.appColors.selection.surface,
        borderRadius: BorderRadius.circular(context.appLayout.radiusLg),
        border: Border.all(color: context.appColors.selection.border),
      ),
      child: Padding(
        padding: EdgeInsets.all(context.appLayout.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.displayName,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            SizedBox(height: context.appLayout.space2),
            Wrap(
              spacing: context.appLayout.space3,
              runSpacing: context.appLayout.space3,
              children: [
                if ((item.sku ?? '').trim().isNotEmpty)
                  AppStatusBadge(
                    label: 'SKU ${item.sku!.trim()}',
                    tone: AppStatusTone.info,
                  ),
                AppStatusBadge(
                  label:
                      'Saldo ${AppFormatters.quantityFromMil(item.currentStockMil)} ${item.unitMeasure}',
                  tone: AppStatusTone.success,
                ),
                AppStatusBadge(
                  label:
                      'Venda ${AppFormatters.currencyFromCents(item.salePriceCents)}',
                  tone: AppStatusTone.neutral,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InventoryItemPickerSheet extends StatefulWidget {
  const _InventoryItemPickerSheet({required this.items});

  final List<InventoryItem> items;

  @override
  State<_InventoryItemPickerSheet> createState() =>
      _InventoryItemPickerSheetState();
}

class _InventoryItemPickerSheetState extends State<_InventoryItemPickerSheet> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final filteredItems = widget.items
        .where(_matchesSearch)
        .toList(growable: false);

    return AppBottomSheetContainer(
      title: 'Selecionar item',
      subtitle: 'Busque por nome, SKU, cor ou tamanho.',
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.72,
        child: Column(
          children: [
            AppSearchField(
              controller: _searchController,
              hintText: 'Buscar item operacional',
              onChanged: (_) => setState(() {}),
              onClear: () {
                _searchController.clear();
                setState(() {});
              },
            ),
            SizedBox(height: layout.space4),
            Expanded(
              child: filteredItems.isEmpty
                  ? const AppStateCard(
                      title: 'Nenhum item encontrado',
                      message:
                          'Tente outra busca para localizar o SKU que deseja ajustar.',
                      compact: true,
                    )
                  : ListView.separated(
                      itemCount: filteredItems.length,
                      separatorBuilder: (_, __) =>
                          SizedBox(height: layout.space3),
                      itemBuilder: (context, index) {
                        final item = filteredItems[index];
                        return AppListTileCard(
                          title: item.displayName,
                          subtitle: (item.sku ?? '').trim().isEmpty
                              ? 'Produto ativo'
                              : 'SKU ${item.sku!.trim()}',
                          badges: [
                            AppStatusBadge(
                              label:
                                  'Saldo ${AppFormatters.quantityFromMil(item.currentStockMil)} ${item.unitMeasure}',
                              tone: AppStatusTone.info,
                            ),
                            AppStatusBadge(
                              label:
                                  'Minimo ${AppFormatters.quantityFromMil(item.minimumStockMil)} ${item.unitMeasure}',
                              tone: AppStatusTone.neutral,
                            ),
                          ],
                          onTap: () => Navigator.of(context).pop(item),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  bool _matchesSearch(InventoryItem item) {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return true;
    }

    final haystack = [
      item.productName,
      item.sku,
      item.variantColorLabel,
      item.variantSizeLabel,
    ].whereType<String>().join(' ').toLowerCase();
    return haystack.contains(query);
  }
}
