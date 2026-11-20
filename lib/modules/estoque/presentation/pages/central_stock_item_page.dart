import '../../../../app/core/widgets/product_stock_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/utils/quantity_parser.dart';
import '../../../../app/routes/route_names.dart';
import '../../data/central_inventory_api.dart';
import 'stock_workspace_page.dart';

class CentralStockItemPage extends ConsumerStatefulWidget {
  const CentralStockItemPage({super.key, required this.item});
  final InventoryJson item;
  @override
  ConsumerState<CentralStockItemPage> createState() => _StockItemState();
}

class _StockItemState extends ConsumerState<CentralStockItemPage> {
  InventoryJson? latest;
  String? error;
  bool canAdjust = false, canInitialize = false;
  @override
  void initState() {
    super.initState();
    Future.microtask(_refresh);
  }

  Future<void> _refresh() async {
    try {
      final data = await ref
          .read(centralInventoryApiProvider)
          .read(
            '/items/${widget.item['productId']}',
            query: {
              if (widget.item['productVariantId'] != null)
                'productVariantId': widget.item['productVariantId'],
            },
            allowCache: false,
          );
      final cap = await ref
          .read(centralInventoryApiProvider)
          .read('/capabilities', allowCache: false);
      if (mounted) {
        setState(() {
          canAdjust = cap['canAdjust'] == true;
          canInitialize = cap['canInitializeStock'] == true;
          latest = inventoryJson(data['item']);
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = stockError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = latest ?? widget.item;
    final unit = inventoryText(item['unitMeasure'], 'un');
    return Scaffold(
      appBar: AppBar(title: const Text('Item de estoque')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            stockItemName(item),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          Text('SKU ${inventoryText(item['sku'], 'não informado')}'),
          const SizedBox(height: 20),
          Text(
            'Saldo físico: ${stockQuantity(item['currentStockMil'], unit)}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (item['reservedStockMil'] != null)
            Text('Reservado: ${stockQuantity(item['reservedStockMil'], unit)}'),
          if (item['availableStockMil'] != null)
            Text(
              'Disponível: ${stockQuantity(item['availableStockMil'], unit)}',
            ),
          Text('Mínimo: ${stockQuantity(item['minimumStockMil'], unit)}'),
          const SizedBox(height: 12),
          if (error != null)
            StockNotice(
              message: error!,
              action: 'Atualizar',
              onAction: _refresh,
            ),
          if (canAdjust)
            FilledButton.icon(
              onPressed: () => _adjust(item),
              icon: const Icon(Icons.swap_vert),
              label: const Text('Movimentar estoque'),
            ),
          if (canInitialize &&
              inventoryNumber(item['stockRevision']) == 0 &&
              inventoryNumber(item['currentStockMil']) == 0)
            FilledButton.icon(
              onPressed: () => _adjust(item, initialize: true),
              icon: const Icon(Icons.add_box_outlined),
              label: const Text('Informar saldo inicial'),
            ),
          if (canAdjust)
            OutlinedButton.icon(
              onPressed: () => _settings(item),
              icon: const Icon(Icons.tune),
              label: const Text('Limites de reposição'),
            ),
          TextButton.icon(
            onPressed: () => context.push(
              '${AppRoutePaths.inventoryMovements}?productId=${item['productId']}',
            ),
            icon: const Icon(Icons.history),
            label: const Text('Ver movimentações'),
          ),
          const StockNotice(
            message:
                'A confirmação exige conexão. Entradas de compras devem ser registradas no fluxo de Compras.',
          ),
        ],
      ),
    );
  }

  Future<void> _settings(InventoryJson item) async {
    final minimum = TextEditingController(
      text: stockQuantity(item['minimumStockMil']).split(' ').first,
    );
    final reorder = TextEditingController(
      text: item['reorderPointMil'] == null
          ? ''
          : stockQuantity(item['reorderPointMil']).split(' ').first,
    );
    final values = await showDialog<InventoryJson>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Limites de reposição'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: minimum,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Estoque mínimo'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reorder,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Ponto de reposição (opcional)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              try {
                final min = QuantityParser.parseToMil(minimum.text);
                final point = reorder.text.trim().isEmpty
                    ? null
                    : QuantityParser.parseToMil(reorder.text);
                if (min >= 0 && (point == null || point >= 0)) {
                  Navigator.of(dialog).pop(<String, dynamic>{
                    'minimumStockMil': min,
                    'reorderPointMil': point,
                  });
                }
              } catch (_) {
                /* Invalid input stays available for correction. */
              }
            },
            child: const Text('Salvar online'),
          ),
        ],
      ),
    );
    minimum.dispose();
    reorder.dispose();
    if (values == null) return;
    try {
      await ref.read(centralInventoryApiProvider).write(
        'PATCH',
        '/items/${item['productId']}/settings${item['productVariantId'] == null ? '' : '?productVariantId=${item['productVariantId']}'}',
        {'expectedRevision': item['stockRevision'], ...values},
      );
      await _refresh();
    } catch (e) {
      if (mounted) setState(() => error = stockError(e));
    }
  }

  Future<void> _adjust(InventoryJson item, {bool initialize = false}) async {
    final draft = <String, dynamic>{
      'id': 'adjust-${inventoryRequestId()}',
      'requestId': inventoryRequestId(),
      'name': 'Ajuste de ${stockItemName(item)}',
      'item': item,
      'kind': 'adjustment',
      'initialize': initialize,
    };
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProductStockSurface(
          child: CentralStockAdjustmentPage(draft: draft),
        ),
      ),
    );
    if (mounted) await _refresh();
  }
}

class CentralStockAdjustmentPage extends ConsumerStatefulWidget {
  const CentralStockAdjustmentPage({super.key, required this.draft});
  final InventoryJson draft;
  @override
  ConsumerState<CentralStockAdjustmentPage> createState() =>
      _StockAdjustmentState();
}

class _StockAdjustmentState extends ConsumerState<CentralStockAdjustmentPage> {
  final quantity = TextEditingController(),
      reason = TextEditingController(),
      notes = TextEditingController();
  bool incoming = true, busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    quantity.text = inventoryText(widget.draft['quantity'], '');
    reason.text = inventoryText(widget.draft['reason'], '');
    notes.text = inventoryText(widget.draft['notes'], '');
    incoming = widget.draft['incoming'] != false;
  }

  @override
  void dispose() {
    quantity.dispose();
    reason.dispose();
    notes.dispose();
    super.dispose();
  }

  InventoryJson _draft() => {
    ...widget.draft,
    'quantity': quantity.text,
    'reason': reason.text,
    'notes': notes.text,
    'incoming': incoming,
  };
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Movimentar estoque')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          stockItemName(inventoryJson(widget.draft['item'])),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        if (widget.draft['initialize'] != true)
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Entrada'),
                selected: incoming,
                onSelected: busy
                    ? null
                    : (_) => setState(() => incoming = true),
              ),
              ChoiceChip(
                label: const Text('Saída'),
                selected: !incoming,
                onSelected: busy
                    ? null
                    : (_) => setState(() => incoming = false),
              ),
            ],
          ),
        const SizedBox(height: 16),
        TextField(
          controller: quantity,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Quantidade'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: reason,
          maxLength: 180,
          decoration: const InputDecoration(labelText: 'Motivo obrigatório'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: notes,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Observações'),
        ),
        if (error != null) StockNotice(message: error!),
        OutlinedButton(
          onPressed: busy
              ? null
              : () async {
                  await ref
                      .read(centralInventoryApiProvider)
                      .saveDraft(_draft());
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Rascunho salvo neste aparelho. O saldo não foi alterado.',
                        ),
                      ),
                    );
                  }
                },
          child: const Text('Salvar rascunho'),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: busy ? null : _confirm,
          child: Text(busy ? 'Confirmando…' : 'Revisar e confirmar online'),
        ),
      ],
    ),
  );
  Future<void> _confirm() async {
    try {
      final amount = QuantityParser.parseToMil(quantity.text);
      if (amount <= 0 || reason.text.trim().isEmpty) {
        throw ArgumentError('Informe quantidade maior que zero e motivo.');
      }
      final item = inventoryJson(widget.draft['item']);
      final delta = incoming ? amount : -amount;
      final approved = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Confirmar movimentação'),
          content: Text(
            '${incoming ? 'Entrada' : 'Saída'} de ${stockQuantity(amount, inventoryText(item['unitMeasure'], 'un'))}.\nSaldo de referência: ${stockQuantity(item['currentStockMil'])}\nNovo saldo: ${stockQuantity(inventoryNumber(item['currentStockMil']) + delta)}\nMotivo: ${reason.text.trim()}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialog).pop(false),
              child: const Text('Voltar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialog).pop(true),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      );
      if (approved != true) return;
      setState(() => busy = true);
      final api = ref.read(centralInventoryApiProvider);
      await api.saveDraft(_draft());
      final confirmed = await api.write(
        'POST',
        widget.draft['initialize'] == true
            ? '/initial-balances'
            : '/adjustments',
        {
          'requestId': widget.draft['requestId'],
          'productId': item['productId'],
          'productVariantId': item['productVariantId'],
          'expectedRevision': item['stockRevision'],
          'quantityDeltaMil': delta,
          'reason': reason.text.trim(),
          'notes': notes.text.trim(),
        },
      );
      await api.removeDraft(inventoryText(widget.draft['id']));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              confirmed['localRefreshPending'] == true
                  ? 'Movimentação confirmada no servidor. Atualize o saldo deste aparelho em Estoque antes de vender.'
                  : 'Movimentação confirmada e saldo deste aparelho atualizado.',
            ),
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error =
              '${stockError(e)}\nEm caso de conflito, volte e atualize o item antes de preparar outro ajuste.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}
