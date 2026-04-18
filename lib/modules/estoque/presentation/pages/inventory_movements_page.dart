import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/widgets/app_card.dart';
import '../../../../app/core/widgets/app_list_tile_card.dart';
import '../../../../app/core/widgets/app_main_drawer.dart';
import '../../../../app/core/widgets/app_page_header.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import '../../../../app/core/widgets/app_state_card.dart';
import '../../../../app/core/widgets/app_status_badge.dart';
import '../../../../app/routes/route_names.dart';
import '../../../../app/theme/app_design_tokens.dart';
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
            (item) => _selectionKey(item) == _selectionKey(_selectedItem!),
          )
        ? _selectionKey(_selectedItem!)
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Movimentacoes de estoque')),
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
              title: 'Extrato de movimentacoes',
              subtitle:
                  'Consulte o historico cronologico de compras, vendas, cancelamentos, devolucoes, inventarios e ajustes.',
              badgeLabel: 'Rastreabilidade',
              badgeIcon: Icons.history_rounded,
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
            child: Row(
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
              layout.space5,
            ),
            child: AppSectionCard(
              title: 'Filtros',
              subtitle:
                  'Refine por periodo, tipo de movimento e produto ou variante.',
              child: Column(
                children: [
                  DropdownButtonFormField<String?>(
                    initialValue: selectedItemKey,
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Todos os itens'),
                      ),
                      for (final item in items)
                        DropdownMenuItem<String?>(
                          value: _selectionKey(item),
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
                    onChanged: (value) {
                      setState(() {
                        _selectedItem = _resolveSelectedItem(items, value);
                      });
                    },
                  ),
                  SizedBox(height: layout.space4),
                  DropdownButtonFormField<InventoryMovementType?>(
                    initialValue: _selectedType,
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
                    onChanged: (value) {
                      setState(() => _selectedType = value);
                    },
                  ),
                  SizedBox(height: layout.space4),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickDate(
                            context,
                            initialValue: _fromDate,
                            onSelected: (value) => setState(() {
                              _fromDate = value == null
                                  ? null
                                  : DateTime(
                                      value.year,
                                      value.month,
                                      value.day,
                                    );
                            }),
                          ),
                          icon: const Icon(Icons.event_available_outlined),
                          label: Text(
                            _fromDate == null
                                ? 'Inicio'
                                : AppFormatters.shortDate(_fromDate!),
                          ),
                        ),
                      ),
                      SizedBox(width: layout.space4),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickDate(
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
                          icon: const Icon(Icons.event_outlined),
                          label: Text(
                            _toDate == null
                                ? 'Fim'
                                : AppFormatters.shortDate(_toDate!),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_selectedItem != null ||
                      _selectedType != null ||
                      _fromDate != null ||
                      _toDate != null) ...[
                    SizedBox(height: layout.space3),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _selectedItem = null;
                            _selectedType = null;
                            _fromDate = null;
                            _toDate = null;
                          });
                        },
                        icon: const Icon(Icons.restart_alt_rounded),
                        label: const Text('Limpar filtros'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Expanded(
            child: movementsAsync.when(
              data: (movements) {
                if (movements.isEmpty) {
                  return Padding(
                    padding: EdgeInsets.all(layout.pagePadding),
                    child: const AppStateCard(
                      title: 'Sem movimentacoes para o filtro',
                      message:
                          'Nao ha movimentos registrados no periodo ou filtro selecionado.',
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
                  message: 'Buscando os ultimos movimentos do estoque.',
                  tone: AppStateTone.loading,
                  compact: true,
                ),
              ),
              error: (error, _) => Padding(
                padding: EdgeInsets.all(layout.pagePadding),
                child: AppStateCard(
                  title: 'Falha ao carregar movimentacoes',
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

  String _selectionKey(InventoryItem item) {
    return '${item.productId}:${item.productVariantId ?? 0}';
  }

  InventoryItem? _resolveSelectedItem(
    List<InventoryItem> items,
    String? value,
  ) {
    if (value == null) {
      return null;
    }
    for (final item in items) {
      if (_selectionKey(item) == value) {
        return item;
      }
    }
    return null;
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
