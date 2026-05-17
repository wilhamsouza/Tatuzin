import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/widgets/app_card.dart';
import '../../../../app/core/widgets/app_list_tile_card.dart';
import '../../../../app/core/widgets/app_main_drawer.dart';
import '../../../../app/core/widgets/app_page_header.dart';
import '../../../../app/core/widgets/app_state_card.dart';
import '../../../../app/core/widgets/app_status_badge.dart';
import '../../../../app/routes/route_names.dart';
import '../../../../app/core/theme/app_design_tokens.dart';
import '../../domain/entities/inventory_adjustment_input.dart';
import '../../domain/entities/inventory_item.dart';
import '../../domain/entities/inventory_movement.dart';
import '../providers/inventory_providers.dart';

class InventoryMovementsPage extends ConsumerStatefulWidget {
  const InventoryMovementsPage({super.key});

  @override
  ConsumerState<InventoryMovementsPage> createState() =>
      _InventoryMovementsPageState();
}

class _InventoryMovementsPageState
    extends ConsumerState<InventoryMovementsPage> {
  InventoryItem? _selectedItem;
  InventoryMovementType? _selectedType;
  DateTime? _fromDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime? _toDate;
  bool _filtersExpanded = false;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final itemsAsync = ref.watch(inventoryItemOptionsProvider);
    final query = InventoryMovementQuery(
      productId: _selectedItem?.productId,
      productVariantId: _selectedItem?.productVariantId,
      movementType: _selectedType,
      createdFrom: _fromDate,
      createdTo: _toDate,
    );
    final movementsAsync = ref.watch(inventoryMovementsProvider(query));
    final items = itemsAsync.valueOrNull ?? const <InventoryItem>[];
    final selectedItemKey = _selectedItem == null
        ? null
        : items.any(
            (item) =>
                _inventoryItemSelectionKey(item) ==
                _inventoryItemSelectionKey(_selectedItem!),
          )
        ? _inventoryItemSelectionKey(_selectedItem!)
        : null;
    final canPop = Navigator.of(context).canPop();

    return Scaffold(
      appBar: AppBar(
        leading: canPop ? const BackButton() : null,
        title: const Text('Movimentações de estoque'),
      ),
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
              title: 'Extrato de movimentações',
              subtitle:
                  'Histórico de compras, vendas, devoluções, inventários e ajustes.',
              badgeLabel: 'Rastreabilidade',
              badgeIcon: Icons.history_rounded,
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              layout.pagePadding,
              0,
              layout.pagePadding,
              layout.space4,
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => context.goNamed(AppRouteNames.inventory),
                    icon: const Icon(Icons.inventory_2_outlined),
                    label: const Text('Estoque atual'),
                  ),
                ),
                SizedBox(width: layout.space4),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () =>
                        context.pushNamed(AppRouteNames.inventoryAdjustment),
                    icon: const Icon(Icons.tune_rounded),
                    label: const Text('Novo ajuste'),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              layout.pagePadding,
              0,
              layout.pagePadding,
              layout.space4,
            ),
            child: _MovementFiltersCard(
              expanded: _filtersExpanded,
              selectedItemKey: selectedItemKey,
              items: items,
              selectedType: _selectedType,
              fromDate: _fromDate,
              toDate: _toDate,
              activeLabels: _activeFilterLabels(),
              onToggleExpanded: () {
                setState(() => _filtersExpanded = !_filtersExpanded);
              },
              onItemChanged: (value) {
                setState(() {
                  _selectedItem = _resolveSelectedItem(items, value);
                });
              },
              onTypeChanged: (value) {
                setState(() => _selectedType = value);
              },
              onPickFromDate: () => _pickDate(
                context,
                initialValue: _fromDate,
                onSelected: (value) => setState(() {
                  _fromDate = value == null
                      ? null
                      : DateTime(value.year, value.month, value.day);
                }),
              ),
              onPickToDate: () => _pickDate(
                context,
                initialValue: _toDate,
                onSelected: (value) => setState(() {
                  _toDate = value == null
                      ? null
                      : DateTime(
                          value.year,
                          value.month,
                          value.day,
                          23,
                          59,
                          59,
                        );
                }),
              ),
              onClear: _hasActiveFilters()
                  ? () {
                      setState(() {
                        _selectedItem = null;
                        _selectedType = null;
                        _fromDate = null;
                        _toDate = null;
                      });
                    }
                  : null,
            ),
          ),
          Expanded(
            child: movementsAsync.when(
              data: (movements) {
                if (movements.isEmpty) {
                  return Padding(
                    padding: EdgeInsets.all(layout.pagePadding),
                    child: const AppStateCard(
                      title: 'Sem movimentações para o filtro',
                      message:
                          'Não há movimentos registrados no período ou filtro selecionado.',
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(inventoryMovementsProvider(query));
                    await ref.read(inventoryMovementsProvider(query).future);
                  },
                  child: ListView.separated(
                    padding: EdgeInsets.fromLTRB(
                      layout.pagePadding,
                      0,
                      layout.pagePadding,
                      layout.pagePadding,
                    ),
                    itemCount: movements.length,
                    separatorBuilder: (_, __) =>
                        SizedBox(height: layout.space4),
                    itemBuilder: (context, index) {
                      return _InventoryMovementTile(movement: movements[index]);
                    },
                  ),
                );
              },
              loading: () => Padding(
                padding: EdgeInsets.all(layout.pagePadding),
                child: const AppStateCard(
                  title: 'Carregando extrato',
                  message: 'Buscando os últimos movimentos do estoque.',
                  tone: AppStateTone.loading,
                  compact: true,
                ),
              ),
              error: (error, _) => Padding(
                padding: EdgeInsets.all(layout.pagePadding),
                child: AppStateCard(
                  title: 'Falha ao carregar movimentações',
                  message: '$error',
                  tone: AppStateTone.error,
                  compact: true,
                  actionLabel: 'Tentar novamente',
                  onAction: () =>
                      ref.invalidate(inventoryMovementsProvider(query)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  InventoryItem? _resolveSelectedItem(
    List<InventoryItem> items,
    String? value,
  ) {
    if (value == null) {
      return null;
    }
    for (final item in items) {
      if (_inventoryItemSelectionKey(item) == value) {
        return item;
      }
    }
    return null;
  }

  bool _hasActiveFilters() {
    return _selectedItem != null ||
        _selectedType != null ||
        _fromDate != null ||
        _toDate != null;
  }

  List<String> _activeFilterLabels() {
    return [
      if (_selectedItem != null) _selectedItem!.displayName,
      if (_selectedType != null) _selectedType!.label,
      if (_fromDate != null) 'Desde ${AppFormatters.shortDate(_fromDate!)}',
      if (_toDate != null) 'Até ${AppFormatters.shortDate(_toDate!)}',
    ];
  }

  Future<void> _pickDate(
    BuildContext context, {
    required DateTime? initialValue,
    required ValueChanged<DateTime?> onSelected,
  }) async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initialValue ?? today,
      firstDate: DateTime(2020),
      lastDate: DateTime(today.year + 5),
    );
    if (picked == null) {
      return;
    }
    onSelected(picked);
  }
}

String _inventoryItemSelectionKey(InventoryItem item) {
  return '${item.productId}:${item.productVariantId ?? 0}';
}

class _MovementFiltersCard extends StatelessWidget {
  const _MovementFiltersCard({
    required this.expanded,
    required this.selectedItemKey,
    required this.items,
    required this.selectedType,
    required this.fromDate,
    required this.toDate,
    required this.activeLabels,
    required this.onToggleExpanded,
    required this.onItemChanged,
    required this.onTypeChanged,
    required this.onPickFromDate,
    required this.onPickToDate,
    required this.onClear,
  });

  final bool expanded;
  final String? selectedItemKey;
  final List<InventoryItem> items;
  final InventoryMovementType? selectedType;
  final DateTime? fromDate;
  final DateTime? toDate;
  final List<String> activeLabels;
  final VoidCallback onToggleExpanded;
  final ValueChanged<String?> onItemChanged;
  final ValueChanged<InventoryMovementType?> onTypeChanged;
  final VoidCallback onPickFromDate;
  final VoidCallback onPickToDate;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    return AppCard(
      padding: EdgeInsets.all(layout.compactCardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.filter_list_rounded,
                size: layout.iconMd,
                color: Theme.of(context).colorScheme.primary,
              ),
              SizedBox(width: layout.space3),
              Expanded(
                child: Text(
                  activeLabels.isEmpty
                      ? 'Filtros'
                      : 'Filtros (${activeLabels.length})',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              TextButton.icon(
                onPressed: onToggleExpanded,
                icon: Icon(
                  expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                ),
                label: Text(expanded ? 'Ocultar' : 'Editar'),
              ),
            ],
          ),
          if (activeLabels.isNotEmpty) ...[
            SizedBox(height: layout.space3),
            Wrap(
              spacing: layout.space2,
              runSpacing: layout.space2,
              children: [
                for (final label in activeLabels)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: AppStatusBadge(
                      label: label,
                      tone: AppStatusTone.info,
                    ),
                  ),
              ],
            ),
          ],
          if (expanded) ...[
            SizedBox(height: layout.space4),
            DropdownButtonFormField<String?>(
              initialValue: selectedItemKey,
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Todos os itens'),
                ),
                for (final item in items)
                  DropdownMenuItem<String?>(
                    value: _inventoryItemSelectionKey(item),
                    child: Text(
                      item.selectorLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              decoration: const InputDecoration(
                labelText: 'Produto ou variante',
              ),
              onChanged: onItemChanged,
            ),
            SizedBox(height: layout.space3),
            DropdownButtonFormField<InventoryMovementType?>(
              initialValue: selectedType,
              items: [
                const DropdownMenuItem<InventoryMovementType?>(
                  value: null,
                  child: Text('Todos os tipos'),
                ),
                for (final type in InventoryMovementType.values)
                  DropdownMenuItem<InventoryMovementType?>(
                    value: type,
                    child: Text(type.label),
                  ),
              ],
              decoration: const InputDecoration(labelText: 'Tipo'),
              onChanged: onTypeChanged,
            ),
            SizedBox(height: layout.space3),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onPickFromDate,
                    icon: const Icon(Icons.event_available_outlined),
                    label: Text(
                      fromDate == null
                          ? 'Início'
                          : AppFormatters.shortDate(fromDate!),
                    ),
                  ),
                ),
                SizedBox(width: layout.space3),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onPickToDate,
                    icon: const Icon(Icons.event_outlined),
                    label: Text(
                      toDate == null ? 'Fim' : AppFormatters.shortDate(toDate!),
                    ),
                  ),
                ),
              ],
            ),
            if (onClear != null) ...[
              SizedBox(height: layout.space2),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onClear,
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: const Text('Limpar filtros'),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _InventoryMovementTile extends StatelessWidget {
  const _InventoryMovementTile({required this.movement});

  final InventoryMovement movement;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final isInbound = movement.movementType.isInbound;
    final tone = isInbound ? AppCardTone.success : AppCardTone.warning;
    final reason =
        movement.reason == null ||
            (movement.movementType != InventoryMovementType.adjustmentIn &&
                movement.movementType != InventoryMovementType.adjustmentOut)
        ? null
        : inventoryAdjustmentReasonFromStorage(movement.reason).label;
    final footerLines = <String>[
      if ((movement.sku ?? '').trim().isNotEmpty) 'SKU ${movement.sku!.trim()}',
      if (reason != null) 'Motivo $reason',
      if ((movement.notes ?? '').trim().isNotEmpty) movement.notes!,
    ];

    return AppListTileCard(
      title: movement.displayName,
      subtitle: movement.referenceLabel,
      tone: tone,
      leading: DecoratedBox(
        decoration: BoxDecoration(
          color: isInbound
              ? context.appColors.success.surface
              : context.appColors.warning.surface,
          borderRadius: BorderRadius.circular(layout.radiusMd),
        ),
        child: Padding(
          padding: EdgeInsets.all(layout.space4),
          child: Icon(
            isInbound ? Icons.south_west_rounded : Icons.north_east_rounded,
            color: isInbound
                ? context.appColors.success.base
                : context.appColors.warning.base,
          ),
        ),
      ),
      badges: [
        AppStatusBadge(
          label: movement.movementType.label,
          tone: isInbound ? AppStatusTone.success : AppStatusTone.warning,
        ),
        AppStatusBadge(
          label:
              '${movement.quantityDeltaMil >= 0 ? '+' : ''}${AppFormatters.quantityFromMil(movement.quantityDeltaMil)}',
          tone: isInbound ? AppStatusTone.success : AppStatusTone.warning,
        ),
        AppStatusBadge(
          label:
              'Antes ${AppFormatters.quantityFromMil(movement.stockBeforeMil)}',
          tone: AppStatusTone.neutral,
        ),
        AppStatusBadge(
          label:
              'Depois ${AppFormatters.quantityFromMil(movement.stockAfterMil)}',
          tone: AppStatusTone.info,
        ),
        AppStatusBadge(
          label: AppFormatters.shortDateTime(movement.createdAt),
          tone: AppStatusTone.info,
        ),
      ],
      footer: footerLines.isEmpty
          ? null
          : Text(
              footerLines.join('  |  '),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
    );
  }
}
