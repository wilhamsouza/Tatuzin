import '../../../../app/core/widgets/product_stock_surface.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/session/session_provider.dart';
import '../../../../app/core/utils/quantity_parser.dart';
import '../../../../app/routes/route_names.dart';
import '../../data/central_inventory_api.dart';
import 'stock_workspace_page.dart';

class CentralCountPage extends ConsumerStatefulWidget {
  const CentralCountPage({super.key, this.countId, this.draft});
  final String? countId;
  final InventoryJson? draft;
  @override
  ConsumerState<CentralCountPage> createState() => _CentralCountState();
}

class _CentralCountState extends ConsumerState<CentralCountPage> {
  InventoryJson session = {}, draft = {};
  List<InventoryJson> items = [], removed = [];
  bool busy = true, cached = false, canTransfer = false, draftLoaded = false;
  String? error;
  final keys = <String, String>{};
  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    try {
      if (widget.draft != null && !draftLoaded) {
        draftLoaded = true;
        draft = {...widget.draft!};
        session = inventoryJson(draft['session']);
        items = inventoryRows(draft['items']);
        removed = inventoryRows(draft['removedItems']);
      } else {
        final data = await ref
            .read(centralInventoryApiProvider)
            .read('/counts/${session['id'] ?? widget.countId}');
        session = inventoryJson(data['session']);
        items = inventoryRows(data['items']);
        cached = data['isCached'] == true;
      }
      final capabilities = await ref
          .read(centralInventoryApiProvider)
          .read('/capabilities');
      canTransfer = capabilities['canTransferCounts'] == true;
      error = null;
    } catch (e) {
      error = stockError(e);
    }
    if (mounted) setState(() => busy = false);
  }

  bool get editable =>
      !['APPLIED', 'CANCELED'].contains(session['status']) &&
      ref.read(appSessionProvider).canAccessPermission('stock.adjust') &&
      (session.isEmpty ||
          session['assigneeUserId'] ==
              ref.read(centralInventoryApiProvider).userId);
  String get name =>
      inventoryText(session['name'] ?? draft['name'], 'Contagem');
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(name),
      actions: [
        IconButton(
          tooltip: 'Atualizar contagem',
          onPressed: busy || draft.isNotEmpty
              ? null
              : () {
                  setState(() => busy = true);
                  _load();
                },
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [
        Text(
          session.isEmpty
              ? 'Rascunho neste aparelho'
              : stockCountStatus(session['status']),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (session['assigneeUserId'] != null)
          Text(
            'Responsável: ${inventoryText(session['assigneeName'], inventoryText(session['assigneeUserId']))}',
          ),
        if (cached)
          const StockNotice(
            message:
                'Dados locais. Publique as alterações quando houver conexão.',
          ),
        const StockNotice(
          message:
              'Selecione os itens e informe o que foi contado. Item pendente não significa zero. A aplicação exige sincronização e conexão.',
        ),
        if (error != null) StockNotice(message: error!),
        if (error != null && draft.isNotEmpty && session['id'] != null)
          OutlinedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ProductStockSurface(
                  child: CentralCountPage(
                    countId: inventoryText(session['id']),
                  ),
                ),
              ),
            ),
            child: const Text(
              'Conferir versão do servidor sem descartar rascunho',
            ),
          ),
        if (busy) const LinearProgressIndicator(),
        if (editable)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: busy ? null : _selectItems,
                icon: const Icon(Icons.playlist_add),
                label: const Text('Selecionar itens'),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : _saveLocal,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Salvar rascunho'),
              ),
              FilledButton.icon(
                onPressed: busy ? null : _publish,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: const Text('Salvar online'),
              ),
            ],
          ),
        const SizedBox(height: 12),
        Text(
          '${items.where((row) => row['countedStockMil'] != null).length}/${items.length} itens contados',
        ),
        for (final item in items)
          Card(
            child: ListTile(
              title: Text(stockItemName(item)),
              subtitle: Text(
                '${inventoryText(item['sku'], 'Sem SKU')}\nReferência: ${stockQuantity(item['referenceStockMil'] ?? item['currentStockMil'], inventoryText(item['unitMeasure'], 'un'))}\nContado: ${item['countedStockMil'] == null ? 'Pendente' : stockQuantity(item['countedStockMil'], inventoryText(item['unitMeasure'], 'un'))}${item['countedStockMil'] == null ? '' : ' · Diferença ${stockQuantity(inventoryNumber(item['countedStockMil']) - inventoryNumber(item['referenceStockMil'] ?? item['currentStockMil']), inventoryText(item['unitMeasure'], 'un'))}'}',
              ),
              isThreeLine: true,
              trailing: editable
                  ? Icon(
                      item['isStale'] == true
                          ? Icons.warning_amber
                          : Icons.edit_outlined,
                    )
                  : null,
              onTap: editable && !busy ? () => _enter(item) : null,
            ),
          ),
        if (editable && session.isNotEmpty) ...[
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: busy ? null : () => _transition('review'),
            child: const Text('Revisar contagem'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: busy || session['status'] != 'REVIEWED'
                ? null
                : () => _transition('apply'),
            child: const Text('Aplicar diferenças ao estoque'),
          ),
          TextButton(
            onPressed: busy ? null : () => _transition('cancel'),
            child: const Text('Cancelar contagem'),
          ),
        ],
        if (session['status'] == 'APPLIED')
          TextButton.icon(
            onPressed: () => context.push(AppRoutePaths.inventoryMovements),
            icon: const Icon(Icons.history),
            label: const Text('Ver movimentações geradas'),
          ),
        if (!editable && !['APPLIED', 'CANCELED'].contains(session['status']))
          const StockNotice(
            message: 'Somente o responsável pode editar esta contagem.',
          ),
        if (canTransfer &&
            session.isNotEmpty &&
            !['APPLIED', 'CANCELED'].contains(session['status']))
          TextButton(
            onPressed: busy ? null : _transfer,
            child: const Text('Transferir responsabilidade'),
          ),
      ],
    ),
  );

  Future<void> _saveLocal() async {
    final api = ref.read(centralInventoryApiProvider);
    draft = {
      ...draft,
      'id': draft['id'] ?? 'draft-${session['id']}',
      'requestId': draft['requestId'] ?? inventoryRequestId(),
      'name': name,
      'session': session,
      'items': items,
      'removedItems': removed,
    };
    await api.saveDraft(draft);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Rascunho salvo. O estoque não foi alterado.'),
        ),
      );
    }
  }

  Future<void> _publish() async {
    setState(() => busy = true);
    try {
      await _saveLocal();
      final result = await ref
          .read(centralInventoryApiProvider)
          .publishDraft(draft);
      session = inventoryJson(result['session']);
      items = inventoryRows(result['items']);
      draft = {};
      removed = [];
      cached = false;
      error = null;
    } catch (e) {
      error =
          '${stockError(e)}\nO rascunho foi preservado. Conflitos exigem atualizar e conferir os itens; não há sobrescrita automática.';
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _selectItems() async {
    final chosen = await showDialog<List<InventoryJson>>(
      context: context,
      builder: (_) => _CountItemsDialog(selected: items),
    );
    if (chosen == null || !mounted) return;
    final selectedKeys = chosen.map(inventoryItemKey).toSet();
    removed.addAll(
      items.where((row) => !selectedKeys.contains(inventoryItemKey(row))),
    );
    removed.removeWhere((row) => selectedKeys.contains(inventoryItemKey(row)));
    setState(() => items = chosen);
    await _saveLocal();
  }

  Future<void> _enter(InventoryJson item) async {
    // Recount requires a fresh explicit measurement, never prefilled with an
    // older value when the stock revision changed.
    final text = TextEditingController();
    InventoryJson baseline = item;
    try {
      final data = await ref
          .read(centralInventoryApiProvider)
          .read(
            '/items/${item['productId']}',
            query: {
              if (item['productVariantId'] != null)
                'productVariantId': item['productVariantId'],
            },
            allowCache: false,
          );
      baseline = {...item, ...inventoryJson(data['item'])};
    } catch (_) {
      /* Offline entry retains the last known stock revision. */
    }
    if (!mounted) {
      text.dispose();
      return;
    }
    final value = await showDialog<int>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(stockItemName(item)),
        content: TextField(
          controller: text,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Quantidade contada',
            helperText: 'Informe zero apenas se conferiu e não há unidades.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () {
              if (text.text.trim().isEmpty) return;
              try {
                final amount = QuantityParser.parseToMil(text.text);
                if (amount >= 0) Navigator.of(dialog).pop(amount);
              } catch (_) {}
            },
            child: const Text('Registrar contagem'),
          ),
        ],
      ),
    );
    text.dispose();
    if (value == null || !mounted) return;
    setState(() {
      final index = items.indexWhere(
        (row) => inventoryItemKey(row) == inventoryItemKey(item),
      );
      items[index] = {
        ...baseline,
        'referenceStockMil':
            baseline['currentStockMil'] ?? baseline['referenceStockMil'],
        'countedStockMil': value,
        'expectedStockRevision':
            baseline['stockRevision'] ?? baseline['expectedStockRevision'],
        'isStale': false,
      };
    });
    await _saveLocal();
  }

  Future<void> _transition(String action) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(switch (action) {
          'apply' => 'Aplicar diferenças?',
          'cancel' => 'Cancelar contagem?',
          _ => 'Revisar contagem?',
        }),
        content: Text(
          action == 'apply'
              ? 'Esta operação gera ajustes auditados e confirma o saldo no servidor. Operações offline de outros aparelhos podem ainda não estar incluídas.'
              : 'O histórico desta contagem será preservado.',
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
    try {
      if (draft.isNotEmpty) {
        throw StateError(
          'Salve o rascunho online antes de revisar ou aplicar.',
        );
      }
      final result = await ref
          .read(centralInventoryApiProvider)
          .write('POST', '/counts/${session['id']}/$action', {
            'requestId': keys.putIfAbsent(action, inventoryRequestId),
            'expectedRevision': session['revision'],
          });
      session = inventoryJson(result['session']);
      items = inventoryRows(result['items']);
      error = null;
      keys.remove(action);
    } catch (e) {
      error = stockError(e);
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _transfer() async {
    setState(() => busy = true);
    try {
      final data = await ref
          .read(centralInventoryApiProvider)
          .read('/count-assignees', allowCache: false);
      if (!mounted) return;
      final choices = inventoryRows(data['items']);
      final id = await showDialog<String>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Transferir responsabilidade'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (choices.isEmpty)
                    const Text('Nenhum responsável autorizado disponível.'),
                  for (final choice in choices)
                    ListTile(
                      title: Text(inventoryText(choice['name'])),
                      selected: choice['userId'] == session['assigneeUserId'],
                      onTap: () => Navigator.of(
                        dialog,
                      ).pop(inventoryText(choice['userId'])),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialog).pop(),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      );
      if (id == null) return;
      final result = await ref.read(centralInventoryApiProvider).write(
        'PATCH',
        '/counts/${session['id']}',
        {'expectedRevision': session['revision'], 'assigneeUserId': id},
      );
      session = inventoryJson(result['session']);
      error = null;
    } catch (e) {
      error = stockError(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

class _CountItemsDialog extends ConsumerStatefulWidget {
  const _CountItemsDialog({required this.selected});
  final List<InventoryJson> selected;
  @override
  ConsumerState<_CountItemsDialog> createState() => _CountItemsState();
}

class _CountItemsState extends ConsumerState<_CountItemsDialog> {
  late final Map<String, InventoryJson> selected = {
    for (final item in widget.selected) inventoryItemKey(item): item,
  };
  List<InventoryJson> options = [];
  String search = '';
  Timer? debounce;
  int page = 1, total = 0, generation = 0;
  bool busy = true;
  String? error;
  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final current = ++generation;
    setState(() => busy = true);
    try {
      final data = await ref
          .read(centralInventoryApiProvider)
          .read(
            '',
            query: {
              'page': page,
              'pageSize': 30,
              if (search.isNotEmpty) 'query': search,
            },
          );
      if (!mounted || current != generation) return;
      setState(() {
        options = inventoryRows(data['items']);
        total = inventoryNumber(inventoryJson(data['pagination'])['total']);
        error = null;
      });
    } catch (e) {
      if (mounted && current == generation) {
        setState(() => error = stockError(e));
      }
    }
    if (mounted && current == generation) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Itens da contagem'),
    content: SizedBox(
      width: 500,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            decoration: const InputDecoration(
              hintText: 'Buscar produto ou SKU',
            ),
            onChanged: (v) {
              search = v;
              page = 1;
              debounce?.cancel();
              debounce = Timer(const Duration(milliseconds: 300), _load);
            },
          ),
          if (busy) const LinearProgressIndicator(),
          if (error != null)
            StockNotice(
              message: error!,
              action: 'Tentar novamente',
              onAction: _load,
            ),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (final item in options)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(stockItemName(item)),
                      subtitle: Text(inventoryText(item['sku'], 'Sem SKU')),
                      value: selected.containsKey(inventoryItemKey(item)),
                      onChanged: (value) => setState(() {
                        if (value == true) {
                          selected[inventoryItemKey(item)] = {
                            ...item,
                            'countedStockMil': null,
                            'expectedStockRevision': item['stockRevision'],
                          };
                        } else {
                          selected.remove(inventoryItemKey(item));
                        }
                      }),
                    ),
                ],
              ),
            ),
          ),
          if (total > 30)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Página anterior',
                  onPressed: page > 1
                      ? () {
                          page--;
                          _load();
                        }
                      : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Text('$page'),
                IconButton(
                  tooltip: 'Próxima página',
                  onPressed: page * 30 < total
                      ? () {
                          page++;
                          _load();
                        }
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(selected.values.toList()),
        child: Text('Selecionar ${selected.length}'),
      ),
    ],
  );
}
