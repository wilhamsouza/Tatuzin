import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/auth/owner_providers.dart';
import '../../../core/widgets/owner_formatters.dart';
import '../../../core/widgets/owner_management_widgets.dart';
import '../data/owner_inventory_api.dart';
import 'owner_inventory_widgets.dart';

class OwnerNewCountDialog extends ConsumerStatefulWidget {
  const OwnerNewCountDialog({super.key});
  @override
  ConsumerState<OwnerNewCountDialog> createState() => _NewCountState();
}

class _NewCountState extends ConsumerState<OwnerNewCountDialog> {
  final name = TextEditingController();
  final requestId = inventoryKey();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (name.text.trim().isEmpty) {
      setState(() => error = 'Informe um nome para a contagem.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final data = await ref.read(ownerInventoryApiProvider).post(
        '/inventory/counts',
        {'name': name.text.trim(), 'requestId': requestId},
      );
      final s = inventoryMap(data['session']);
      if (s['id'] == null) throw StateError('Missing session');
      inventoryRefresh(ref);
      if (!mounted) return;
      final router = GoRouter.of(context);
      Navigator.of(context).pop();
      router.push('/inventory/counts/${s['id']}');
    } catch (e) {
      if (mounted) setState(() => error = inventoryError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Nova contagem'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Escolha os itens na próxima etapa. Nenhuma quantidade será alterada ao criar a contagem.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: name,
              enabled: !busy,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: 'Nome da contagem',
                hintText: 'Ex.: Conferência da loja',
              ),
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
        child: Text(busy ? 'Criando…' : 'Criar contagem'),
      ),
    ],
  );
}

class OwnerInventoryCountPage extends ConsumerStatefulWidget {
  const OwnerInventoryCountPage({super.key, required this.sessionId});
  final String sessionId;
  @override
  ConsumerState<OwnerInventoryCountPage> createState() => _CountState();
}

class _CountState extends ConsumerState<OwnerInventoryCountPage> {
  bool busy = false;
  String? error;
  final keys = <String, String>{};
  Future<void> action(String action, InventoryMap session) async {
    final message = switch (action) {
      'apply' =>
        'Aplicar as diferenças revisadas ao estoque central? Esta operação gera movimentações e não pode ser editada depois. Operações ainda não enviadas por outros aparelhos não estão incluídas.',
      'review' =>
        'Confirmar a revisão de todos os itens contados? O estoque será conferido novamente no servidor.',
      'cancel' =>
        'Cancelar esta contagem? Os registros serão preservados e nenhum ajuste será aplicado.',
      _ => 'Confirmar a operação?',
    };
    if (!await confirmInventory(
      context,
      title: switch (action) {
        'apply' => 'Aplicar contagem',
        'review' => 'Revisar contagem',
        _ => 'Cancelar contagem',
      },
      message: message,
    )) {
      return;
    }
    if (!mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    final revision = inventoryInt(session['revision']);
    final key = keys.putIfAbsent('$action-$revision', inventoryKey);
    try {
      await ref.read(ownerInventoryApiProvider).post(
        '/inventory/counts/${widget.sessionId}/$action',
        {'requestId': key, 'expectedRevision': revision},
      );
      inventoryRefresh(ref);
    } catch (e) {
      if (mounted) setState(() => error = inventoryError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> removeItem(InventoryMap session, InventoryMap item) async {
    if (!await confirmInventory(
      context,
      title: 'Retirar item da contagem',
      message:
          'Retirar este item e sua quantidade contada? O saldo de estoque não será alterado.',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref.read(ownerInventoryApiProvider).put(
        '/inventory/counts/${widget.sessionId}/items',
        {
          'expectedRevision': session['revision'],
          'items': [
            {
              'productId': item['productId'],
              'productVariantId': item['productVariantId'],
              'countedStockMil': null,
              'expectedStockRevision':
                  item['stockRevision'] ?? item['expectedStockRevision'],
              'remove': true,
            },
          ],
        },
      );
      inventoryRefresh(ref);
    } catch (e) {
      if (mounted) setState(() => error = inventoryError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cap = ref.watch(ownerInventoryCapabilitiesProvider).asData?.value;
    final user = ref.watch(ownerAuthControllerProvider).session?.user.id;
    return InventoryResource(
      resource: '/inventory/counts/${widget.sessionId}',
      builder: (data) {
        final s = inventoryMap(data['session']);
        final items = inventoryRows(data['items']);
        final status = inventoryText(s['status']);
        final finalState = const ['APPLIED', 'CANCELED'].contains(status);
        final own = s['assigneeUserId'] == user;
        final edit =
            cap?['enabled'] == true &&
            cap?['canCount'] == true &&
            own &&
            !finalState;
        final pending = items.where((i) => i['countedStockMil'] == null).length;
        final stale = items.any(
          (i) => i['isStale'] == true || i['stale'] == true,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OwnerPageIntro(
              title: inventoryText(s['name'], 'Contagem'),
              subtitle:
                  '${inventoryStatus(status)} · Atualizada ${OwnerFormatters.date(s['updatedAt'])}',
              icon: Icons.fact_check_outlined,
              trailing: IconButton(
                tooltip: 'Atualizar contagem',
                onPressed: busy ? null : () => inventoryRefresh(ref),
                icon: const Icon(Icons.refresh),
              ),
            ),
            const SizedBox(height: 16),
            InventorySection(
              title: 'Conferência do estoque',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Responsável: ${inventoryText(s['assigneeName'] ?? inventoryMap(s['assignee'])['name'], own ? 'Você' : 'Responsável da sessão')}',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${items.length - pending} de ${items.length} itens contados · $pending pendentes',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Conte as quantidades físicas. Itens em branco continuam pendentes; zero deve ser informado explicitamente. A aplicação exige conexão e considera apenas operações já recebidas pelo servidor.',
                  ),
                  if (!own && !finalState)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        'Somente o responsável pode preencher esta contagem. Solicite a transferência se precisar continuar.',
                      ),
                    ),
                  if (stale)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        'O saldo mudou durante a contagem. Confira novamente os itens sinalizados antes de revisar.',
                      ),
                    ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      if (edit)
                        OutlinedButton.icon(
                          onPressed: busy
                              ? null
                              : () => showDialog<void>(
                                  context: context,
                                  builder: (_) => _SelectCountItems(
                                    session: s,
                                    existing: items,
                                  ),
                                ),
                          icon: const Icon(Icons.add),
                          label: const Text('Selecionar itens'),
                        ),
                      if (!finalState && cap?['canTransferCounts'] == true)
                        TextButton(
                          onPressed: busy
                              ? null
                              : () => showDialog<void>(
                                  context: context,
                                  builder: (_) =>
                                      _TransferCountDialog(session: s),
                                ),
                          child: const Text('Transferir responsável'),
                        ),
                      if (edit && items.isNotEmpty && pending == 0 && !stale)
                        FilledButton.tonal(
                          onPressed: busy ? null : () => action('review', s),
                          child: const Text('Revisar contagem'),
                        ),
                      if (edit && status == 'REVIEWED' && !stale)
                        FilledButton(
                          onPressed: busy ? null : () => action('apply', s),
                          child: const Text('Aplicar ao estoque'),
                        ),
                      if (edit)
                        TextButton(
                          onPressed: busy ? null : () => action('cancel', s),
                          child: const Text('Cancelar contagem'),
                        ),
                      TextButton(
                        onPressed: () => context.go('/inventory?tab=movements'),
                        child: const Text('Ver movimentações'),
                      ),
                    ],
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            InventorySection(
              title: 'Itens da contagem',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (items.isEmpty)
                    const InventoryEmpty(
                      'Selecione os produtos ou variações que serão conferidos.',
                    ),
                  for (final item in items)
                    _CountItemRow(
                      item: item,
                      editable: edit && !busy,
                      onRemove: () => removeItem(s, item),
                      onCount: () => showDialog<void>(
                        context: context,
                        builder: (_) =>
                            _CountQuantityDialog(session: s, item: item),
                      ),
                    ),
                ],
              ),
            ),
            if (inventoryRows(data['history']).isNotEmpty) ...[
              const SizedBox(height: 16),
              InventorySection(
                title: 'Histórico da contagem',
                child: Column(
                  children: [
                    for (final event in inventoryRows(data['history']))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          const {
                                'COUNT_CREATE': 'Contagem criada',
                                'COUNT_UPDATE':
                                    'Responsável ou informações atualizados',
                                'COUNT_ITEMS': 'Itens conferidos',
                                'COUNT_REVIEW': 'Contagem revisada',
                                'COUNT_APPLY': 'Contagem aplicada',
                                'COUNT_CANCEL': 'Contagem cancelada',
                              }[event['operation']] ??
                              'Contagem atualizada',
                        ),
                        subtitle: Text(
                          '${inventoryText(event['actorName'], 'Responsável não registrado')} · ${OwnerFormatters.date(event['createdAt'])}',
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () => context.canPop()
                  ? context.pop()
                  : context.go('/inventory?tab=counts'),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Voltar às contagens'),
            ),
          ],
        );
      },
    );
  }
}

class _CountItemRow extends StatelessWidget {
  const _CountItemRow({
    required this.item,
    required this.editable,
    required this.onCount,
    required this.onRemove,
  });
  final InventoryMap item;
  final bool editable;
  final VoidCallback onCount, onRemove;
  @override
  Widget build(BuildContext context) {
    final unit = inventoryText(item['unitMeasure'], 'un');
    final stale = item['isStale'] == true || item['stale'] == true;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(inventoryText(item['productName'] ?? item['name'])),
            subtitle: Text(
              '${inventoryText(item['sku'], 'Sem código')} · ${inventoryText(item['variantName'], '')}\nReferência: ${inventoryQuantity(item['referenceStockMil'] ?? item['systemStockMil'] ?? item['currentStockMil'], unit)}\nContado: ${item['countedStockMil'] == null ? 'Pendente' : inventoryQuantity(item['countedStockMil'], unit)}${item['differenceMil'] == null ? '' : '\nDiferença: ${inventoryQuantity(item['differenceMil'], unit)}'}${stale ? '\nSaldo alterado: confira novamente' : ''}',
            ),
          ),
          if (editable)
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton(
                onPressed: onCount,
                child: Text(
                  stale
                      ? 'Conferir novamente'
                      : item['countedStockMil'] == null
                      ? 'Informar contagem'
                      : 'Corrigir contagem',
                ),
              ),
            ),
          if (editable)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onRemove,
                child: const Text('Retirar da contagem'),
              ),
            ),
          const Divider(),
        ],
      ),
    );
  }
}

class _CountQuantityDialog extends ConsumerStatefulWidget {
  const _CountQuantityDialog({required this.session, required this.item});
  final InventoryMap session, item;
  @override
  ConsumerState<_CountQuantityDialog> createState() => _QuantityState();
}

class _QuantityState extends ConsumerState<_CountQuantityDialog> {
  final value = TextEditingController();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    value.dispose();
    super.dispose();
  }

  Future<void> save(InventoryMap current) async {
    final amount = inventoryScaled(value.text);
    if (amount == null) {
      setState(
        () => error =
            'Informe a quantidade contada, inclusive zero quando necessário.',
      );
      return;
    }
    if (current['stockRevision'] is! num) {
      setState(
        () => error =
            'A revisão do saldo não está disponível. Atualize a página.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref.read(ownerInventoryApiProvider).put(
        '/inventory/counts/${widget.session['id']}/items',
        {
          'expectedRevision': widget.session['revision'],
          'items': [
            {
              'productId': widget.item['productId'],
              'productVariantId': widget.item['productVariantId'],
              'countedStockMil': amount,
              'expectedStockRevision': current['stockRevision'],
            },
          ],
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
  Widget build(BuildContext context) {
    final i = widget.item;
    return AlertDialog(
      title: const Text('Quantidade contada'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: InventoryResource(
            resource:
                '/inventory/items/${i['productId']}${i['productVariantId'] == null ? '' : '?productVariantId=${i['productVariantId']}'}',
            builder: (data) {
              final current = inventoryMap(data['item']);
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    inventoryText(current['name'] ?? current['productName']),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Saldo central atual: ${inventoryQuantity(current['currentStockMil'], inventoryText(current['unitMeasure'], 'un'))}',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: value,
                    enabled: !busy,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText:
                          'Quantidade física (${inventoryText(current['unitMeasure'], 'un')})',
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Confira fisicamente o item. Esta etapa salva a contagem sem alterar o saldo.',
                  ),
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: busy ? null : () => save(current),
                    child: Text(busy ? 'Salvando…' : 'Salvar contagem'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Fechar'),
        ),
      ],
    );
  }
}

class _SelectCountItems extends ConsumerStatefulWidget {
  const _SelectCountItems({required this.session, required this.existing});
  final InventoryMap session;
  final List<InventoryMap> existing;
  @override
  ConsumerState<_SelectCountItems> createState() => _SelectItemsState();
}

class _SelectItemsState extends ConsumerState<_SelectCountItems> {
  final search = TextEditingController();
  String query = '';
  int page = 1;
  bool busy = false;
  String? error;
  final selected = <String, InventoryMap>{};
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (selected.isEmpty) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref.read(ownerInventoryApiProvider).put(
        '/inventory/counts/${widget.session['id']}/items',
        {
          'expectedRevision': widget.session['revision'],
          'items': selected.values
              .map(
                (i) => {
                  'productId': i['productId'],
                  'productVariantId': i['productVariantId'],
                  'countedStockMil': null,
                  'expectedStockRevision': i['stockRevision'],
                },
              )
              .toList(),
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
    title: const Text('Selecionar itens'),
    content: SizedBox(
      width: 600,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: search,
              decoration: InputDecoration(
                labelText: 'Nome ou SKU',
                suffixIcon: IconButton(
                  tooltip: 'Buscar',
                  onPressed: () => setState(() {
                    query = search.text;
                    page = 1;
                  }),
                  icon: const Icon(Icons.search),
                ),
              ),
              onSubmitted: (s) => setState(() {
                query = s;
                page = 1;
              }),
            ),
            const SizedBox(height: 16),
            InventoryResource(
              resource: Uri(
                path: '/inventory',
                queryParameters: {
                  'query': query,
                  'page': '$page',
                  'pageSize': '20',
                  'filter': 'all',
                },
              ).toString(),
              builder: (data) => Column(
                children: [
                  if (inventoryRows(data['items']).isEmpty)
                    const InventoryEmpty('Nenhum item encontrado.'),
                  for (final item in inventoryRows(data['items']))
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value:
                          selected.containsKey(
                            '${item['productId']}:${item['productVariantId']}',
                          ) ||
                          widget.existing.any(
                            (e) =>
                                e['productId'] == item['productId'] &&
                                e['productVariantId'] ==
                                    item['productVariantId'],
                          ),
                      title: Text(
                        inventoryText(item['name'] ?? item['productName']),
                      ),
                      subtitle: Text(
                        '${inventoryText(item['sku'], 'Sem código')} · ${inventoryText(item['variantName'], '')}',
                      ),
                      onChanged:
                          busy ||
                              item['stockRevision'] is! num ||
                              widget.existing.any(
                                (e) =>
                                    e['productId'] == item['productId'] &&
                                    e['productVariantId'] ==
                                        item['productVariantId'],
                              )
                          ? null
                          : (v) => setState(() {
                              final key =
                                  '${item['productId']}:${item['productVariantId']}';
                              if (v == true) {
                                selected[key] = item;
                              } else {
                                selected.remove(key);
                              }
                            }),
                    ),
                  InventoryPager(
                    data: data,
                    page: page,
                    onPage: (p) => setState(() => page = p),
                  ),
                ],
              ),
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
        onPressed: busy || selected.isEmpty ? null : save,
        child: Text(
          busy ? 'Adicionando…' : 'Adicionar ${selected.length} itens',
        ),
      ),
    ],
  );
}

class _TransferCountDialog extends ConsumerStatefulWidget {
  const _TransferCountDialog({required this.session});
  final InventoryMap session;
  @override
  ConsumerState<_TransferCountDialog> createState() => _TransferState();
}

class _TransferState extends ConsumerState<_TransferCountDialog> {
  String? target, error;
  bool busy = false;
  Future<void> save() async {
    if (target == null) return;
    if (!await confirmInventory(
      context,
      title: 'Transferir contagem',
      message:
          'O novo responsável poderá continuar esta contagem. Rascunhos anteriores precisarão respeitar a revisão atual.',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref.read(ownerInventoryApiProvider).patch(
        '/inventory/counts/${widget.session['id']}',
        {
          'expectedRevision': widget.session['revision'],
          'assigneeUserId': target,
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
    title: const Text('Transferir responsável'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InventoryResource(
              resource: '/inventory/count-assignees',
              builder: (data) => DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: target,
                decoration: const InputDecoration(labelText: 'Responsável'),
                items: [
                  for (final user in inventoryRows(data['items']))
                    DropdownMenuItem(
                      value: inventoryText(user['userId']),
                      child: Text(inventoryText(user['name'])),
                    ),
                ],
                onChanged: busy ? null : (v) => setState(() => target = v),
              ),
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
        onPressed: busy || target == null ? null : save,
        child: Text(busy ? 'Transferindo…' : 'Transferir'),
      ),
    ],
  );
}
