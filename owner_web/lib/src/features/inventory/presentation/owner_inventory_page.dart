import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/owner_async_view.dart';
import '../../../core/widgets/owner_formatters.dart';
import '../../../core/widgets/owner_management_widgets.dart';
import '../data/owner_inventory_api.dart';
import 'owner_inventory_widgets.dart';
import 'owner_inventory_count_page.dart';

class OwnerInventoryPage extends ConsumerStatefulWidget {
  const OwnerInventoryPage({super.key});
  @override
  ConsumerState<OwnerInventoryPage> createState() => _InventoryState();
}

class _InventoryState extends ConsumerState<OwnerInventoryPage> {
  final search = TextEditingController();
  Timer? debounce;
  String? lastQuery;
  @override
  void dispose() {
    search.dispose();
    debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final caps = ref.watch(ownerInventoryCapabilitiesProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const OwnerPageIntro(
          title: 'Estoque',
          subtitle:
              'Acompanhe os saldos, entenda as mudanças e confira as quantidades.',
          icon: Icons.inventory_2_outlined,
        ),
        const SizedBox(height: 16),
        OwnerAsyncView(
          value: caps,
          onRetry: () => ref.invalidate(ownerInventoryCapabilitiesProvider),
          builder: (cap) {
            if (cap['canRead'] != true) {
              return InventoryEmpty(
                cap['enabled'] == false
                    ? 'A operação de estoque ainda não está liberada para esta empresa.'
                    : 'Você não tem permissão para consultar estoque.',
                action: TextButton(
                  onPressed: () => context.go('/products/analysis'),
                  child: const Text('Análise de produtos'),
                ),
              );
            }
            final q = inventoryUri(context).queryParameters;
            if (lastQuery != (q['query'] ?? '')) {
              lastQuery = q['query'] ?? '';
              search.text = lastQuery!;
            }
            final tab =
                const ['balances', 'movements', 'counts'].contains(q['tab'])
                ? q['tab']!
                : 'balances';
            final page = int.tryParse(q['page'] ?? '1') ?? 1;
            final canAdjust =
                cap['enabled'] == true && cap['canAdjust'] == true;
            final canCount = cap['enabled'] == true && cap['canCount'] == true;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in const {
                      'balances': 'Saldos',
                      'movements': 'Movimentações',
                      'counts': 'Contagens',
                    }.entries)
                      ChoiceChip(
                        label: Text(t.value),
                        selected: tab == t.key,
                        onSelected: (_) => inventoryNavigateFilter(context, {
                          'tab': t.key,
                          'page': null,
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                if (cap['enabled'] != true)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: Text(
                      'Consulta disponível. Ajustes e contagens ainda não foram liberados para esta empresa.',
                    ),
                  ),
                if (tab == 'balances') ...[
                  const Text(
                    'Saldo central confirmado. Vendas ainda não enviadas por outros aparelhos não estão incluídas.',
                  ),
                  const SizedBox(height: 12),
                  InventoryResource(
                    resource: '/inventory/summary',
                    builder: (data) {
                      final s = inventoryMap(data['summary']);
                      return Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          for (final e in {
                            'Itens monitorados': s['totalItemsCount'],
                            'Abaixo do mínimo': s['belowMinimumItemsCount'],
                            'Sem estoque': s['zeroedItemsCount'],
                          }.entries)
                            Chip(
                              label: Text(
                                '${e.key}: ${e.value is num ? e.value : 'Indisponível'}',
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  InventorySection(
                    child: Column(
                      children: [
                        TextField(
                          controller: search,
                          decoration: const InputDecoration(
                            labelText: 'Buscar produto ou SKU',
                            prefixIcon: Icon(Icons.search),
                          ),
                          onChanged: (v) {
                            debounce?.cancel();
                            debounce = Timer(
                              const Duration(milliseconds: 300),
                              () {
                                if (mounted) {
                                  inventoryNavigateFilter(context, {
                                    'query': v,
                                    'page': null,
                                  });
                                }
                              },
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final f in const {
                              'all': 'Todos',
                              'belowMinimum': 'Abaixo do mínimo',
                              'zeroed': 'Sem estoque',
                              'inactive': 'Inativos',
                            }.entries)
                              ChoiceChip(
                                label: Text(f.value),
                                selected: (q['filter'] ?? 'all') == f.key,
                                onSelected: (_) => inventoryNavigateFilter(
                                  context,
                                  {'filter': f.key, 'page': null},
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  InventoryResource(
                    resource: Uri(
                      path: '/inventory',
                      queryParameters: {
                        'page': '$page',
                        'pageSize': '20',
                        'query': q['query'] ?? '',
                        'filter': q['filter'] ?? 'all',
                        if (q['productId'] != null)
                          'productId': q['productId']!,
                        if (q['productVariantId'] != null)
                          'productVariantId': q['productVariantId']!,
                      },
                    ).toString(),
                    builder: (data) {
                      final rows = inventoryRows(data['items']);
                      return InventorySection(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (rows.isEmpty)
                              const InventoryEmpty(
                                'Nenhum item encontrado para os filtros selecionados.',
                              ),
                            LayoutBuilder(
                              builder: (context, c) {
                                if (c.maxWidth >= 850 &&
                                    MediaQuery.textScalerOf(
                                          context,
                                        ).scale(14) <=
                                        21) {
                                  return DataTable(
                                    horizontalMargin: 0,
                                    columnSpacing: 18,
                                    columns: const [
                                      DataColumn(label: Text('Item')),
                                      DataColumn(label: Text('Saldo físico')),
                                      DataColumn(label: Text('Situação')),
                                      DataColumn(label: Text('Ações')),
                                    ],
                                    rows: [
                                      for (final item in rows)
                                        DataRow(
                                          cells: [
                                            DataCell(
                                              SizedBox(
                                                width: 260,
                                                child: Text(
                                                  '${inventoryText(item['name'] ?? item['productName'])}\n${inventoryText(item['sku'], 'Sem código')} ${inventoryText(item['variantName'], '')}',
                                                ),
                                              ),
                                            ),
                                            DataCell(
                                              Text(
                                                inventoryQuantity(
                                                  item['currentStockMil'],
                                                  inventoryText(
                                                    item['unitMeasure'],
                                                    'un',
                                                  ),
                                                ),
                                              ),
                                            ),
                                            DataCell(
                                              Text(
                                                inventoryStatus(item['status']),
                                              ),
                                            ),
                                            DataCell(
                                              IconButton(
                                                tooltip:
                                                    'Ver saldo e histórico',
                                                icon: const Icon(
                                                  Icons.chevron_right,
                                                ),
                                                onPressed: () => _detail(item),
                                              ),
                                            ),
                                          ],
                                        ),
                                    ],
                                  );
                                }
                                return Column(
                                  children: [
                                    for (final item in rows)
                                      ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        title: Text(
                                          inventoryText(
                                            item['name'] ?? item['productName'],
                                          ),
                                        ),
                                        subtitle: Text(
                                          '${inventoryText(item['sku'], 'Sem código')} · ${inventoryText(item['variantName'], '')}\n${inventoryQuantity(item['currentStockMil'], inventoryText(item['unitMeasure'], 'un'))} · ${inventoryStatus(item['status'])}',
                                        ),
                                        isThreeLine: true,
                                        trailing: const Icon(
                                          Icons.chevron_right,
                                        ),
                                        onTap: () => _detail(item),
                                      ),
                                  ],
                                );
                              },
                            ),
                            InventoryPager(
                              data: data,
                              page: page,
                              onPage: (p) => inventoryNavigateFilter(context, {
                                'page': '$p',
                              }),
                            ),
                            if (canAdjust)
                              const Text(
                                'Abra um item para registrar entrada ou saída com motivo e confirmação.',
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ] else if (tab == 'movements') ...[
                  InventorySection(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final d in [7, 30, 90])
                              OutlinedButton(
                                onPressed: () =>
                                    inventoryNavigateFilter(context, {
                                      'startDate': DateTime.now()
                                          .toUtc()
                                          .subtract(Duration(days: d - 1))
                                          .toIso8601String()
                                          .substring(0, 10),
                                      'endDate': DateTime.now()
                                          .toUtc()
                                          .toIso8601String()
                                          .substring(0, 10),
                                      'page': null,
                                    }),
                                child: Text('Últimos $d dias'),
                              ),
                            if (q['productId'] != null)
                              TextButton(
                                onPressed: () =>
                                    inventoryNavigateFilter(context, {
                                      'productId': null,
                                      'productVariantId': null,
                                      'page': null,
                                    }),
                                child: const Text('Todos os produtos'),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: q['type'] ?? '',
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Tipo'),
                          items: [
                            for (final e in const {
                              '': 'Todos',
                              'ADJUSTMENT_IN': 'Entrada manual',
                              'ADJUSTMENT_OUT': 'Saída manual',
                              'COUNT_ADJUSTMENT': 'Contagem',
                              'STOCK_CHANGE': 'Operação de estoque',
                              'INITIAL': 'Saldo inicial',
                            }.entries)
                              DropdownMenuItem(
                                value: e.key,
                                child: Text(e.value),
                              ),
                          ],
                          onChanged: (v) => inventoryNavigateFilter(context, {
                            'type': v,
                            'page': null,
                          }),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  InventoryResource(
                    resource: Uri(
                      path: '/inventory/movements',
                      queryParameters: {
                        'page': '$page',
                        'pageSize': '20',
                        for (final k in [
                          'startDate',
                          'endDate',
                          'productId',
                          'productVariantId',
                          'type',
                        ])
                          if (q[k]?.isNotEmpty == true) k: q[k]!,
                      },
                    ).toString(),
                    builder: (data) => InventorySection(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (inventoryRows(data['items']).isEmpty)
                            const InventoryEmpty(
                              'Nenhuma movimentação encontrada neste período.',
                            ),
                          for (final m in inventoryRows(data['items']))
                            InventoryMovementRow(movement: m),
                          InventoryPager(
                            data: data,
                            page: page,
                            onPage: (p) => inventoryNavigateFilter(context, {
                              'page': '$p',
                            }),
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final status in const {
                        '': 'Todas',
                        'OPEN': 'Abertas',
                        'COUNTING': 'Em contagem',
                        'REVIEWED': 'Revisadas',
                        'APPLIED': 'Aplicadas',
                        'CANCELED': 'Canceladas',
                      }.entries)
                        ChoiceChip(
                          label: Text(status.value),
                          selected: (q['status'] ?? '') == status.key,
                          onSelected: (_) => inventoryNavigateFilter(context, {
                            'status': status.key,
                            'page': null,
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (canCount)
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: () => showDialog<void>(
                          context: context,
                          builder: (_) => const OwnerNewCountDialog(),
                        ),
                        icon: const Icon(Icons.add_task_outlined),
                        label: const Text('Nova contagem'),
                      ),
                    ),
                  const SizedBox(height: 12),
                  InventoryResource(
                    resource:
                        '/inventory/counts?page=$page&pageSize=20${q['status'] == null ? '' : '&status=${q['status']}'}',
                    builder: (data) => InventorySection(
                      child: Column(
                        children: [
                          if (inventoryRows(data['items']).isEmpty)
                            const InventoryEmpty(
                              'Nenhuma contagem. Crie uma para conferir as quantidades da loja.',
                            ),
                          for (final s in inventoryRows(data['items']))
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(inventoryText(s['name'])),
                              subtitle: Text(
                                '${inventoryStatus(s['status'])} · ${OwnerFormatters.date(s['updatedAt'])}\n${inventoryText(s['assigneeName'] ?? inventoryMap(s['assignee'])['name'], 'Responsável definido na sessão')}',
                              ),
                              isThreeLine: true,
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () =>
                                  context.push('/inventory/counts/${s['id']}'),
                            ),
                          InventoryPager(
                            data: data,
                            page: page,
                            onPage: (p) => inventoryNavigateFilter(context, {
                              'page': '$p',
                            }),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  void _detail(InventoryMap item) => context.push(
    '/inventory/items/${item['productId']}${item['productVariantId'] == null ? '' : '?productVariantId=${item['productVariantId']}'}',
  );
}

class InventoryMovementRow extends StatelessWidget {
  const InventoryMovementRow({super.key, required this.movement});
  final InventoryMap movement;
  @override
  Widget build(BuildContext context) {
    final m = movement;
    return Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            '${inventoryText(m['productName'] ?? m['name'], 'Movimentação de estoque')} · ${inventoryQuantity(m['quantityDeltaMil'], inventoryText(m['unitMeasure'], 'un'))}',
          ),
          subtitle: Text(
            '${inventoryText(m['reason'] ?? m['type'] ?? m['movementType'] ?? m['origin'], 'Movimentação registrada')}\n${inventoryText(m['actorName'] ?? m['responsibleName'] ?? inventoryMap(m['actor'])['name'], 'Responsável não registrado')} · ${OwnerFormatters.date(m['createdAt'])}\nSaldo: ${inventoryQuantity(m['stockBeforeMil'], inventoryText(m['unitMeasure'], 'un'))} → ${inventoryQuantity(m['stockAfterMil'], inventoryText(m['unitMeasure'], 'un'))}${m['referenceId'] == null ? '' : '\nReferência: ${m['referenceId']}'}',
          ),
          isThreeLine: false,
        ),
        const Divider(),
      ],
    );
  }
}

class OwnerInventoryItemPage extends ConsumerWidget {
  const OwnerInventoryItemPage({
    super.key,
    required this.productId,
    this.variantId,
  });
  final String productId;
  final String? variantId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resource = Uri(
      path: '/inventory/items/$productId',
      queryParameters: variantId == null
          ? null
          : {'productVariantId': variantId!},
    ).toString();
    final cap = ref.watch(ownerInventoryCapabilitiesProvider).asData?.value;
    return InventoryResource(
      resource: resource,
      builder: (data) {
        final item = inventoryMap(data['item']);
        final unit = inventoryText(item['unitMeasure'], 'un');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OwnerPageIntro(
              title: inventoryText(item['name'] ?? item['productName']),
              subtitle:
                  '${inventoryText(item['sku'], 'Sem código')} · ${inventoryText(item['variantName'], 'Saldo por item')}',
              icon: Icons.inventory_2_outlined,
            ),
            const SizedBox(height: 16),
            InventorySection(
              title: 'Saldo confirmado',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    inventoryQuantity(item['currentStockMil'], unit),
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  if (item['reservedStockMil'] is num)
                    Text(
                      'Reservado: ${inventoryQuantity(item['reservedStockMil'], unit)}',
                    ),
                  if (item['availableStockMil'] is num)
                    Text(
                      'Disponível: ${inventoryQuantity(item['availableStockMil'], unit)}',
                    ),
                  Text(
                    'Mínimo: ${inventoryQuantity(item['minimumStockMil'], unit)}',
                  ),
                  Text(
                    'Atualização: ${OwnerFormatters.date(item['updatedAt'])}',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Operações ainda não enviadas por outros aparelhos não estão incluídas.',
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      if (cap?['enabled'] == true &&
                          cap?['canAdjust'] == true &&
                          item['stockRevision'] is num)
                        FilledButton.icon(
                          onPressed: () => showDialog<void>(
                            context: context,
                            builder: (_) =>
                                OwnerStockAdjustmentDialog(item: item),
                          ),
                          icon: const Icon(Icons.swap_vert),
                          label: const Text('Movimentar estoque'),
                        ),
                      if (cap?['enabled'] == true &&
                          cap?['canAdjust'] == true &&
                          item['stockRevision'] is num)
                        OutlinedButton.icon(
                          onPressed: () => showDialog<void>(
                            context: context,
                            builder: (_) =>
                                OwnerInventorySettingsDialog(item: item),
                          ),
                          icon: const Icon(Icons.tune),
                          label: const Text('Reposição'),
                        ),
                      OutlinedButton(
                        onPressed: () => context.push('/products/$productId'),
                        child: const Text('Ver produto'),
                      ),
                      TextButton(
                        onPressed: () => context.go(
                          '/inventory?tab=movements&productId=$productId${variantId == null ? '' : '&productVariantId=$variantId'}',
                        ),
                        child: const Text('Histórico completo'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            InventoryResource(
              resource:
                  '/inventory/movements?productId=$productId${variantId == null ? '' : '&productVariantId=$variantId'}&page=1&pageSize=20',
              builder: (d) => InventorySection(
                title: 'Últimas movimentações',
                child: Column(
                  children: [
                    if (inventoryRows(d['items']).isEmpty)
                      const InventoryEmpty('Nenhuma movimentação registrada.'),
                    for (final m in inventoryRows(d['items']))
                      InventoryMovementRow(movement: m),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class OwnerStockAdjustmentDialog extends ConsumerStatefulWidget {
  const OwnerStockAdjustmentDialog({super.key, required this.item});
  final InventoryMap item;
  @override
  ConsumerState<OwnerStockAdjustmentDialog> createState() => _AdjustmentState();
}

class _AdjustmentState extends ConsumerState<OwnerStockAdjustmentDialog> {
  final quantity = TextEditingController(),
      reason = TextEditingController(),
      notes = TextEditingController();
  final form = GlobalKey<FormState>();
  final requestId = inventoryKey();
  bool entry = true, busy = false;
  String? error;
  @override
  void dispose() {
    quantity.dispose();
    reason.dispose();
    notes.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    final amount = inventoryScaled(quantity.text)! * (entry ? 1 : -1);
    final unit = inventoryText(widget.item['unitMeasure'], 'un');
    if (!await confirmInventory(
      context,
      title: 'Confirmar movimentação',
      message:
          '${entry ? 'Entrada' : 'Saída'} de ${inventoryQuantity(amount.abs(), unit)} em ${inventoryText(widget.item['name'] ?? widget.item['productName'])}.\nSaldo previsto: ${inventoryQuantity(inventoryInt(widget.item['currentStockMil']) + amount, unit)}.\nMotivo: ${reason.text.trim()}',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref.read(ownerInventoryApiProvider).post('/inventory/adjustments', {
        'requestId': requestId,
        'productId': widget.item['productId'],
        'productVariantId': widget.item['productVariantId'],
        'expectedRevision': widget.item['stockRevision'],
        'quantityDeltaMil': amount,
        'reason': reason.text.trim(),
        'notes': notes.text.trim(),
      });
      inventoryRefresh(ref);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => error = inventoryError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Movimentar estoque'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                inventoryText(
                  widget.item['name'] ?? widget.item['productName'],
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<bool>(
                initialValue: entry,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Operação'),
                items: const [
                  DropdownMenuItem(value: true, child: Text('Entrada')),
                  DropdownMenuItem(value: false, child: Text('Saída')),
                ],
                onChanged: busy
                    ? null
                    : (v) => setState(() => entry = v ?? true),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: quantity,
                enabled: !busy,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText:
                      'Quantidade (${inventoryText(widget.item['unitMeasure'], 'un')})',
                ),
                validator: (v) {
                  final n = inventoryScaled(v ?? '');
                  return n == null || n <= 0
                      ? 'Informe uma quantidade maior que zero'
                      : null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: reason,
                enabled: !busy,
                maxLength: 180,
                decoration: const InputDecoration(
                  labelText: 'Motivo obrigatório',
                ),
                validator: (v) => v == null || v.trim().length < 3
                    ? 'Descreva o motivo'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: notes,
                enabled: !busy,
                maxLines: 2,
                maxLength: 500,
                decoration: const InputDecoration(labelText: 'Observações'),
              ),
              const Text(
                'Compras devem ser registradas no fluxo de compras para evitar entradas duplicadas.',
              ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.of(context).pop(),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: busy ? null : save,
        child: Text(busy ? 'Confirmando…' : 'Revisar movimentação'),
      ),
    ],
  );
}

class OwnerInventorySettingsDialog extends ConsumerStatefulWidget {
  const OwnerInventorySettingsDialog({super.key, required this.item});
  final InventoryMap item;
  @override
  ConsumerState<OwnerInventorySettingsDialog> createState() =>
      _InventorySettingsState();
}

class _InventorySettingsState
    extends ConsumerState<OwnerInventorySettingsDialog> {
  late final TextEditingController minimum, reorder;
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    minimum = TextEditingController(
      text: OwnerFormatters.quantityFromMil(
        inventoryInt(widget.item['minimumStockMil']),
      ),
    );
    reorder = TextEditingController(
      text: widget.item['reorderPointMil'] == null
          ? ''
          : OwnerFormatters.quantityFromMil(
              inventoryInt(widget.item['reorderPointMil']),
            ),
    );
  }

  @override
  void dispose() {
    minimum.dispose();
    reorder.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final min = inventoryScaled(minimum.text);
    final point = reorder.text.trim().isEmpty
        ? null
        : inventoryScaled(reorder.text);
    if (min == null || (reorder.text.trim().isNotEmpty && point == null)) {
      setState(
        () => error = 'Informe quantidades válidas, sem valores negativos.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    final i = widget.item;
    try {
      await ref.read(ownerInventoryApiProvider).patch(
        '/inventory/items/${i['productId']}${i['productVariantId'] == null ? '' : '?productVariantId=${i['productVariantId']}'}',
        {
          'expectedRevision': i['stockRevision'],
          'minimumStockMil': min,
          'reorderPointMil': point,
        },
      );
      inventoryRefresh(ref);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => error = inventoryError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Reposição'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              inventoryText(widget.item['name'] ?? widget.item['productName']),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: minimum,
              enabled: !busy,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText:
                    'Estoque mínimo (${inventoryText(widget.item['unitMeasure'], 'un')})',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reorder,
              enabled: !busy,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Ponto de reposição — opcional',
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Estas configurações não alteram a quantidade em estoque.',
            ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.of(context).pop(),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: busy ? null : save,
        child: Text(busy ? 'Salvando…' : 'Salvar configurações'),
      ),
    ],
  );
}
