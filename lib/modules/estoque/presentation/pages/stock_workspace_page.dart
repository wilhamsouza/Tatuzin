import '../../../../app/core/widgets/product_stock_surface.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/entitlements/plan_entitlements.dart';
import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/errors/app_exceptions.dart';
import '../../../../app/core/session/session_provider.dart';
import '../../../../app/core/widgets/app_main_drawer.dart';
import '../../data/central_inventory_api.dart';
import '../providers/inventory_providers.dart';
import 'inventory_count_page.dart';
import 'central_count_page.dart';
import 'central_stock_item_page.dart';

String stockQuantity(Object? value, [String unit = 'un']) =>
    '${AppFormatters.quantityFromMil(inventoryNumber(value))} $unit';
String stockItemName(InventoryJson item) =>
    inventoryText(item['name'] ?? item['productName']);
String stockCountStatus(Object? status) =>
    const {
      'OPEN': 'Aberta',
      'COUNTING': 'Em contagem',
      'REVIEWED': 'Revisada',
      'APPLIED': 'Aplicada',
      'CANCELED': 'Cancelada',
    }[status] ??
    inventoryText(status);
String stockTimestamp(Object? value) {
  final time = value is String ? DateTime.tryParse(value) : null;
  return time == null
      ? 'Horário não informado'
      : AppFormatters.shortDateTime(time.toLocal());
}

String stockError(Object error) =>
    error.toString().replaceFirst('Exception: ', '');

String stockMovementLabel(Object? value) =>
    const {
      'SALE_OUT': 'Venda',
      'SALE_CANCEL_IN': 'Cancelamento de venda',
      'RETURN_IN': 'Devolução',
      'PURCHASE_IN': 'Compra',
      'ADJUSTMENT_IN': 'Ajuste de entrada',
      'ADJUSTMENT_OUT': 'Ajuste de saída',
      'COUNT_IN': 'Contagem: entrada',
      'COUNT_OUT': 'Contagem: saída',
      'COUNT_ADJUSTMENT_IN': 'Contagem: entrada',
      'COUNT_ADJUSTMENT_OUT': 'Contagem: saída',
      'INITIAL_BALANCE': 'Saldo inicial',
      'INITIAL': 'Saldo inicial',
      'COUNT_ADJUSTMENT': 'Ajuste de contagem',
      'STOCK_CHANGE': 'Movimentação operacional',
    }[value] ??
    inventoryText(value, 'Movimentação');
String stockOriginLabel(Object? value) =>
    const {
      'manual_adjustment': 'Ajuste manual',
      'inventory_count': 'Contagem',
      'initial_balance': 'Saldo inicial',
      'sale': 'Venda',
      'sale_return': 'Devolução',
      'sale_cancel': 'Cancelamento de venda',
      'purchase': 'Compra',
    }[value] ??
    inventoryText(value);

class StockWorkspacePage extends ConsumerStatefulWidget {
  const StockWorkspacePage({super.key, this.initialTab = 0, this.productId});
  final int initialTab;
  final String? productId;
  @override
  ConsumerState<StockWorkspacePage> createState() => _StockWorkspaceState();
}

class _StockWorkspaceState extends ConsumerState<StockWorkspacePage> {
  final search = TextEditingController();
  Timer? debounce;
  int tab = 0, page = 1, total = 0, generation = 0;
  String filter = 'all';
  String? movementType;
  DateTimeRange? movementPeriod;
  String? failure;
  bool loading = true, localOnly = false;
  InventoryJson cap = {}, data = {};
  List<InventoryJson> items = [], drafts = [];
  @override
  void initState() {
    super.initState();
    tab = widget.initialTab;
    Future.microtask(_reload);
  }

  @override
  void dispose() {
    search.dispose();
    debounce?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    if (!mounted) return;
    final currentGeneration = ++generation;
    setState(() {
      loading = true;
      failure = null;
      localOnly = false;
    });
    final api = ref.read(centralInventoryApiProvider);
    InventoryJson nextCap = {}, nextData = {};
    List<InventoryJson> nextItems = [], nextDrafts = [];
    String? nextFailure;
    bool nextLocal = false;
    try {
      try {
        nextCap = await api.read('/capabilities');
      } catch (_) {
        nextCap = {};
      }
      if (tab == 0 || nextCap['enabled'] == true) {
        final resource = switch (tab) {
          1 => '/movements',
          2 => '/counts',
          _ => '',
        };
        nextData = await api.read(
          resource,
          query: {
            'page': page,
            'pageSize': 30,
            if (tab == 0 && search.text.trim().isNotEmpty)
              'query': search.text.trim(),
            if (tab == 0) 'filter': filter,
            if (tab == 1 && movementType != null) 'type': movementType,
            if (tab == 1 && movementPeriod != null)
              'startDate': movementPeriod!.start
                  .toIso8601String()
                  .split('T')
                  .first,
            if (tab == 1 && movementPeriod != null)
              'endDate': movementPeriod!.end.toIso8601String().split('T').first,
            if (widget.productId != null && tab != 2)
              'productId': widget.productId,
          },
        );
        nextItems = inventoryRows(nextData['items']);
      }
      nextDrafts = await api.drafts();
    } catch (error) {
      nextFailure = stockError(error);
      if (tab == 0 &&
          error is! AuthenticationException &&
          !(error is NetworkRequestException &&
              (error.cause == 401 || error.cause == 403))) {
        try {
          final local = await ref
              .read(localInventoryRepositoryProvider)
              .listItems(query: search.text);
          final filtered = local.where(
            (item) => switch (filter) {
              'inactive' => !item.isActive,
              'zeroed' => item.currentStockMil <= 0,
              'belowMinimum' =>
                item.minimumStockMil > 0 &&
                    item.currentStockMil < item.minimumStockMil,
              _ => true,
            },
          );
          nextItems = filtered
              .map(
                (item) => <String, dynamic>{
                  'name': item.displayName,
                  'sku': item.sku,
                  'unitMeasure': item.unitMeasure,
                  'currentStockMil': item.currentStockMil,
                  'minimumStockMil': item.minimumStockMil,
                  'isActive': item.isActive,
                  'localOnly': true,
                },
              )
              .toList();
          nextLocal = true;
        } catch (_) {
          nextItems = [];
        }
      }
      try {
        nextDrafts = await api.drafts();
      } catch (_) {
        /* Tenant changed. */
      }
    }
    if (mounted && currentGeneration == generation) {
      setState(() {
        cap = nextCap;
        data = nextData;
        items = nextItems;
        drafts = nextDrafts;
        failure = nextFailure;
        localOnly = nextLocal;
        loading = false;
        total = inventoryNumber(inventoryJson(data['pagination'])['total']);
      });
    }
  }

  bool get _canCount =>
      ref.read(appSessionProvider).canAccessPermission('stock.adjust') &&
      ref.read(appSessionProvider).hasFeature(FeatureKey.inventoryAdvanced);

  @override
  Widget build(BuildContext context) {
    ref.listen(sessionRuntimeKeyProvider, (previous, next) {
      if (previous != null && previous != next) {
        items = [];
        drafts = [];
        _reload();
      }
    });
    final subtitle = localOnly || data['isCached'] == true
        ? 'Dados locais · confirmação exige conexão'
        : data['cachedAt'] == null
        ? 'Saldos, movimentos e conferência'
        : 'Atualizado ${stockTimestamp(data['cachedAt'])}';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Estoque'),
        actions: [
          IconButton(
            tooltip: 'Atualizar estoque',
            onPressed: loading ? null : _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      drawer: const AppMainDrawer(),
      floatingActionButton: tab == 2 && _canCount
          ? FloatingActionButton.extended(
              onPressed: _newCount,
              icon: const Icon(Icons.add_task),
              label: const Text('Nova contagem'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<int>(
                    showSelectedIcon: false,
                    segments: [
                      const ButtonSegment(
                        value: 0,
                        icon: Icon(Icons.inventory_2_outlined),
                        label: Text('Saldos'),
                      ),
                      const ButtonSegment(
                        value: 1,
                        icon: Icon(Icons.history),
                        label: Text('Movimentações'),
                      ),
                      if (ref
                          .watch(appSessionProvider)
                          .hasFeature(FeatureKey.inventoryAdvanced))
                        const ButtonSegment(
                          value: 2,
                          icon: Icon(Icons.fact_check_outlined),
                          label: Text('Contagens'),
                        ),
                    ],
                    selected: {tab},
                    onSelectionChanged: (value) {
                      setState(() {
                        tab = value.first;
                        page = 1;
                      });
                      _reload();
                    },
                  ),
                ),
                if (tab == 1) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.date_range),
                        label: Text(
                          movementPeriod == null
                              ? 'Selecionar período'
                              : '${movementPeriod!.start.day}/${movementPeriod!.start.month} a ${movementPeriod!.end.day}/${movementPeriod!.end.month}',
                        ),
                        onPressed: () async {
                          final selected = await showDateRangePicker(
                            context: context,
                            initialDateRange: movementPeriod,
                            firstDate: DateTime(2000),
                            lastDate: DateTime.now().add(
                              const Duration(days: 1),
                            ),
                          );
                          if (selected != null && mounted) {
                            setState(() {
                              movementPeriod = selected;
                              page = 1;
                            });
                            _reload();
                          }
                        },
                      ),
                      SizedBox(
                        width: 260,
                        child: DropdownButtonFormField<String>(
                          initialValue: movementType,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Tipo de movimento',
                          ),
                          items: [
                            const DropdownMenuItem<String>(
                              value: null,
                              child: Text('Todos'),
                            ),
                            for (final kind in const {
                              'SALE_OUT': 'Venda',
                              'STOCK_CHANGE': 'Movimentação operacional',
                              'ADJUSTMENT_IN': 'Ajuste de entrada',
                              'ADJUSTMENT_OUT': 'Ajuste de saída',
                              'COUNT_ADJUSTMENT': 'Ajuste de contagem',
                              'INITIAL': 'Saldo inicial',
                            }.entries)
                              DropdownMenuItem(
                                value: kind.key,
                                child: Text(
                                  kind.value,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (value) {
                            setState(() {
                              movementType = value;
                              page = 1;
                            });
                            _reload();
                          },
                        ),
                      ),
                      if (movementPeriod != null || movementType != null)
                        TextButton(
                          onPressed: () {
                            setState(() {
                              movementPeriod = null;
                              movementType = null;
                              page = 1;
                            });
                            _reload();
                          },
                          child: const Text('Limpar filtros'),
                        ),
                    ],
                  ),
                ],
                if (tab == 0) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: search,
                    decoration: const InputDecoration(
                      hintText: 'Buscar produto ou SKU',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (_) {
                      debounce?.cancel();
                      debounce = Timer(const Duration(milliseconds: 300), () {
                        page = 1;
                        _reload();
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final f in const {
                          'all': 'Todos',
                          'belowMinimum': 'Abaixo do mínimo',
                          'zeroed': 'Sem estoque',
                          'inactive': 'Inativos',
                        }.entries)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(f.value),
                              selected: filter == f.key,
                              onSelected: (_) {
                                setState(() {
                                  filter = f.key;
                                  page = 1;
                                });
                                _reload();
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (loading) const LinearProgressIndicator(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                key: PageStorageKey('stock-workspace-$tab'),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                children: [
                  if (failure != null)
                    StockNotice(
                      message:
                          '$failure${localOnly ? '\nExibindo o saldo deste aparelho.' : ''}',
                      action: 'Tentar novamente',
                      onAction: _reload,
                    ),
                  if (tab != 0 && cap['enabled'] != true)
                    const StockNotice(
                      message:
                          'A operação compartilhada de estoque ainda não está disponível para esta empresa.',
                    ),
                  if (tab == 0)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Operações ainda não enviadas por outros aparelhos não estão incluídas no saldo central.',
                      ),
                    ),
                  if (tab == 2) ...[
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const ProductStockSurface(
                            child: InventoryCountPage(readOnlyHistory: true),
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.history),
                      label: const Text('Histórico antigo deste aparelho'),
                    ),
                    for (final draft in drafts.where(
                      (row) => row['kind'] != 'adjustment',
                    ))
                      Card(
                        child: ListTile(
                          isThreeLine: true,
                          leading: const Icon(Icons.edit_note),
                          title: Text(inventoryText(draft['name'])),
                          subtitle: const Text(
                            'Rascunho neste aparelho\nAinda não altera o estoque',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _openDraft(draft),
                        ),
                      ),
                  ],
                  if (tab == 0)
                    for (final draft in drafts.where(
                      (row) => row['kind'] == 'adjustment',
                    ))
                      Card(
                        child: ListTile(
                          title: Text(inventoryText(draft['name'])),
                          subtitle: const Text(
                            'Ajuste em rascunho · saldo não alterado',
                          ),
                          onTap: () => _openDraft(draft),
                          trailing: const Icon(Icons.chevron_right),
                        ),
                      ),
                  if (!loading && items.isEmpty)
                    StockNotice(
                      message: switch (tab) {
                        1 => 'Nenhuma movimentação encontrada.',
                        2 => 'Nenhuma contagem compartilhada encontrada.',
                        _ =>
                          'Nenhum item encontrado. Ajuste a busca ou cadastre um produto.',
                      },
                    ),
                  for (final item in items)
                    switch (tab) {
                      1 => _movement(item),
                      2 => _count(item),
                      _ => _balance(item),
                    },
                  if (total > 30)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          tooltip: 'Página anterior',
                          onPressed: page > 1
                              ? () {
                                  page--;
                                  _reload();
                                }
                              : null,
                          icon: const Icon(Icons.chevron_left),
                        ),
                        Flexible(
                          child: Text('Página $page · $total registros'),
                        ),
                        IconButton(
                          tooltip: 'Próxima página',
                          onPressed: page * 30 < total
                              ? () {
                                  page++;
                                  _reload();
                                }
                              : null,
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _balance(InventoryJson item) {
    final quantity = inventoryNumber(item['currentStockMil']);
    final minimum = inventoryNumber(item['minimumStockMil']);
    final active = item['isActive'] != false && item['status'] != 'inactive';
    final status = !active
        ? 'Inativo'
        : quantity <= 0
        ? 'Sem estoque'
        : minimum > 0 && quantity < minimum
        ? 'Abaixo do mínimo'
        : 'Disponível';
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        title: Text(stockItemName(item)),
        subtitle: Text(
          [
            if (item['sku'] != null) 'SKU ${item['sku']}',
            if (item['variantName'] != null) inventoryText(item['variantName']),
            '${stockQuantity(quantity, inventoryText(item['unitMeasure'], 'un'))} · $status',
          ].join('\n'),
        ),
        trailing: item['localOnly'] == true
            ? const Icon(Icons.cloud_off)
            : const Icon(Icons.chevron_right),
        onTap: item['localOnly'] == true ? null : () => _detail(item),
      ),
    );
  }

  Widget _movement(InventoryJson item) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            stockItemName(item),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Text(
            '${stockMovementLabel(item['type'] ?? item['movementType'])} · ${stockQuantity(item['quantityDeltaMil'], inventoryText(item['unitMeasure'], 'un'))}',
          ),
          if (item['stockBeforeMil'] != null)
            Text(
              'Saldo ${stockQuantity(item['stockBeforeMil'])} → ${stockQuantity(item['stockAfterMil'])}',
            ),
          Text(
            'Responsável: ${inventoryText(item['responsibleName'] ?? item['actorName'] ?? inventoryJson(item['actor'])['name'], 'Responsável não registrado')}',
          ),
          if (item['origin'] != null)
            Text('Origem: ${stockOriginLabel(item['origin'])}'),
          Text(stockTimestamp(item['createdAt'])),
          if (item['reason'] != null) Text(inventoryText(item['reason'])),
        ],
      ),
    ),
  );
  Widget _count(InventoryJson item) => Card(
    child: ListTile(
      title: Text(inventoryText(item['name'])),
      subtitle: Text(
        '${stockCountStatus(item['status'])}\nResponsável: ${inventoryText(item['assigneeName'] ?? inventoryJson(item['assignee'])['name'], inventoryText(item['assigneeUserId']))}',
      ),
      isThreeLine: true,
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        await context.push('/estoque/contagens/${item['id']}');
        _reload();
      },
    ),
  );
  Future<void> _detail(InventoryJson item) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            ProductStockSurface(child: CentralStockItemPage(item: item)),
      ),
    );
    _reload();
  }

  Future<void> _newCount() async {
    final controller = TextEditingController(
      text: 'Contagem ${DateTime.now().day}/${DateTime.now().month}',
    );
    final name = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Nova contagem'),
        content: TextField(
          controller: controller,
          maxLength: 180,
          decoration: const InputDecoration(labelText: 'Nome da contagem'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.of(dialog).pop(controller.text.trim());
              }
            },
            child: const Text('Preparar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || !mounted) return;
    final api = ref.read(centralInventoryApiProvider);
    final draft = api.newDraft(name);
    await api.saveDraft(draft);
    if (mounted) await _openDraft(draft);
  }

  Future<void> _openDraft(InventoryJson draft) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProductStockSurface(
          child: draft['kind'] == 'adjustment'
              ? CentralStockAdjustmentPage(draft: draft)
              : CentralCountPage(draft: draft),
        ),
      ),
    );
    _reload();
  }
}

class StockNotice extends StatelessWidget {
  const StockNotice({
    super.key,
    required this.message,
    this.action,
    this.onAction,
  });
  final String message;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message),
        if (action != null)
          TextButton(onPressed: onAction, child: Text(action!)),
      ],
    ),
  );
}
