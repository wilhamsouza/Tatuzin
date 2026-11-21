import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/owner_formatters.dart';
import '../../../core/widgets/owner_management_widgets.dart';
import '../../inventory/data/owner_inventory_api.dart';
import '../../inventory/presentation/owner_inventory_widgets.dart';

class OwnerCatalogPage extends ConsumerStatefulWidget {
  const OwnerCatalogPage({super.key});
  @override
  ConsumerState<OwnerCatalogPage> createState() => _CatalogState();
}

class _CatalogState extends ConsumerState<OwnerCatalogPage> {
  final search = TextEditingController();
  Timer? debounce;
  String? lastQuery;
  @override
  void dispose() {
    debounce?.cancel();
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = inventoryUri(context).queryParameters;
    final page = int.tryParse(q['page'] ?? '1') ?? 1;
    if (lastQuery != (q['search'] ?? '')) {
      lastQuery = q['search'] ?? '';
      search.text = lastQuery!;
    }
    final cap = ref.watch(ownerInventoryCapabilitiesProvider).asData?.value;
    final canWrite =
        cap?['enabled'] == true && cap?['canWriteProducts'] == true;
    final query = <String, String>{
      'page': '$page',
      'pageSize': '20',
      if (q['search']?.isNotEmpty == true) 'search': q['search']!,
      if (q['categoryId']?.isNotEmpty == true) 'categoryId': q['categoryId']!,
      if (q['isActive']?.isNotEmpty == true) 'isActive': q['isActive']!,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OwnerPageIntro(
          title: 'Produtos',
          subtitle: 'Organize seu catálogo, preços e variações.',
          icon: Icons.sell_outlined,
          trailing: canWrite
              ? FilledButton.icon(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => const OwnerProductFormDialog(),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('Novo produto'),
                )
              : null,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            OutlinedButton.icon(
              onPressed: () => context.go('/inventory'),
              icon: const Icon(Icons.inventory_2_outlined),
              label: const Text('Estoque'),
            ),
            TextButton.icon(
              onPressed: () => context.go('/products/analysis'),
              icon: const Icon(Icons.analytics_outlined),
              label: const Text('Análise de produtos'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        InventorySection(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: search,
                decoration: const InputDecoration(
                  labelText: 'Buscar nome, SKU ou código',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) {
                  debounce?.cancel();
                  debounce = Timer(const Duration(milliseconds: 300), () {
                    if (mounted) {
                      inventoryNavigateFilter(context, {
                        'search': value,
                        'page': null,
                      });
                    }
                  });
                },
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final e in const {
                    '': 'Todos',
                    'true': 'Ativos',
                    'false': 'Inativos',
                  }.entries)
                    ChoiceChip(
                      label: Text(e.value),
                      selected: (q['isActive'] ?? '') == e.key,
                      onSelected: (_) => inventoryNavigateFilter(context, {
                        'isActive': e.key,
                        'page': null,
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              InventoryResource(
                resource: '/categories?page=1&pageSize=100',
                builder: (data) => DropdownButtonFormField<String>(
                  initialValue: q['categoryId'] ?? '',
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Categoria'),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Todas as categorias'),
                    ),
                    if (q['categoryId'] != null &&
                        !inventoryRows(
                          data['items'],
                        ).any((c) => c['id'] == q['categoryId']))
                      DropdownMenuItem(
                        value: q['categoryId'],
                        child: const Text('Categoria selecionada'),
                      ),
                    for (final c in inventoryRows(data['items']))
                      DropdownMenuItem(
                        value: inventoryText(c['id']),
                        child: Text(
                          inventoryText(c['name']),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => inventoryNavigateFilter(context, {
                    'categoryId': v,
                    'page': null,
                  }),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        InventoryResource(
          resource: Uri(path: '/products', queryParameters: query).toString(),
          builder: (data) {
            final rows = inventoryRows(data['items']);
            return InventorySection(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (rows.isEmpty)
                    const InventoryEmpty(
                      'Nenhum produto encontrado. Ajuste os filtros ou cadastre seu primeiro item.',
                    ),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth >= 850 &&
                          MediaQuery.textScalerOf(context).scale(14) <= 21) {
                        return DataTable(
                          showCheckboxColumn: false,
                          horizontalMargin: 0,
                          columnSpacing: 18,
                          columns: const [
                            DataColumn(label: Text('Produto')),
                            DataColumn(label: Text('Código')),
                            DataColumn(label: Text('Preço')),
                            DataColumn(label: Text('Situação')),
                          ],
                          rows: [
                            for (final p in rows)
                              DataRow(
                                onSelectChanged: (_) =>
                                    context.push('/products/${p['id']}'),
                                cells: [
                                  DataCell(
                                    SizedBox(
                                      width: 260,
                                      child: Text(
                                        '${inventoryText(p['name'])}\n${inventoryRows(p['variants']).length} variações',
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      inventoryText(p['barcode'], 'Sem código'),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      OwnerFormatters.moneyFromCents(
                                        inventoryInt(p['salePriceCents']),
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      p['isActive'] == true
                                          ? 'Ativo'
                                          : 'Inativo',
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        );
                      }
                      return Column(
                        children: [
                          for (final p in rows)
                            _CatalogRow(product: p, canWrite: canWrite),
                        ],
                      );
                    },
                  ),
                  InventoryPager(
                    data: data,
                    page: page,
                    onPage: (p) =>
                        inventoryNavigateFilter(context, {'page': '$p'}),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _CatalogRow extends StatelessWidget {
  const _CatalogRow({required this.product, required this.canWrite});
  final InventoryMap product;
  final bool canWrite;
  @override
  Widget build(BuildContext context) {
    final variants = inventoryRows(product['variants']);
    return Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const CircleAvatar(child: Icon(Icons.sell_outlined)),
          title: Text(inventoryText(product['name'])),
          subtitle: Text(
            '${inventoryText(product['barcode'], 'Sem código')} · ${product['isActive'] == true ? 'Ativo' : 'Inativo'}\n${OwnerFormatters.moneyFromCents(inventoryInt(product['salePriceCents']))}',
          ),
          isThreeLine: true,
          trailing: IconButton(
            tooltip: 'Ver produto',
            onPressed: () => context.push('/products/${product['id']}'),
            icon: const Icon(Icons.chevron_right),
          ),
          onTap: () => context.push('/products/${product['id']}'),
        ),
        if (variants.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('${variants.length} variações'),
            children: [
              for (final v in variants)
                ListTile(
                  title: Text(
                    '${inventoryText(v['sku'])} · ${inventoryText(v['colorLabel'])} / ${inventoryText(v['sizeLabel'])}',
                  ),
                  subtitle: Text(v['isActive'] == true ? 'Ativa' : 'Inativa'),
                  onTap: () => context.push(
                    '/inventory?productId=${product['id']}&productVariantId=${v['id']}',
                  ),
                ),
            ],
          ),
        const Divider(),
      ],
    );
  }
}

class OwnerProductDetailPage extends ConsumerWidget {
  const OwnerProductDetailPage({super.key, required this.productId});
  final String productId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cap = ref.watch(ownerInventoryCapabilitiesProvider).asData?.value;
    final write = cap?['enabled'] == true && cap?['canWriteProducts'] == true;
    return InventoryResource(
      resource: '/products/$productId',
      builder: (data) {
        final p = inventoryMap(data['product']);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OwnerPageIntro(
              title: inventoryText(p['name']),
              subtitle:
                  '${inventoryText(p['barcode'], 'Sem código')} · ${p['isActive'] == true ? 'Ativo' : 'Inativo'}',
              icon: Icons.sell_outlined,
              trailing: write
                  ? FilledButton.icon(
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => OwnerProductFormDialog(product: p),
                      ),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Editar produto'),
                    )
                  : null,
            ),
            const SizedBox(height: 16),
            InventorySection(
              title: 'Informações do produto',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    OwnerFormatters.moneyFromCents(
                      inventoryInt(p['salePriceCents']),
                    ),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  if (cap?['canViewCosts'] == true &&
                      p['costPriceCents'] is num)
                    Text(
                      'Custo: ${OwnerFormatters.moneyFromCents(inventoryInt(p['costPriceCents']))}',
                    ),
                  if (p['description'] != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(inventoryText(p['description'])),
                    ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () =>
                        context.push('/inventory?productId=$productId'),
                    icon: const Icon(Icons.inventory_2_outlined),
                    label: const Text('Ver no estoque'),
                  ),
                ],
              ),
            ),
            if (inventoryRows(p['variants']).isNotEmpty) ...[
              const SizedBox(height: 16),
              InventorySection(
                title: 'Variações',
                child: Column(
                  children: [
                    for (final v in inventoryRows(p['variants']))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(inventoryText(v['sku'])),
                        subtitle: Text(
                          '${inventoryText(v['colorLabel'])} / ${inventoryText(v['sizeLabel'])} · ${v['isActive'] == true ? 'Ativa' : 'Inativa'}',
                        ),
                        onTap: () => context.push(
                          '/inventory?productId=$productId&productVariantId=${v['id']}',
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () =>
                  context.canPop() ? context.pop() : context.go('/products'),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Voltar ao catálogo'),
            ),
          ],
        );
      },
    );
  }
}

class OwnerProductFormDialog extends ConsumerStatefulWidget {
  const OwnerProductFormDialog({super.key, this.product});
  final InventoryMap? product;
  @override
  ConsumerState<OwnerProductFormDialog> createState() => _ProductFormState();
}

class _ProductFormState extends ConsumerState<OwnerProductFormDialog> {
  final form = GlobalKey<FormState>();
  late final TextEditingController name,
      barcode,
      description,
      price,
      cost,
      unit;
  late final List<InventoryMap> variants;
  late bool active;
  bool busy = false;
  String? error, category;
  late final String localUuid;
  @override
  void initState() {
    super.initState();
    final p = widget.product ?? {};
    name = TextEditingController(text: inventoryText(p['name'], ''));
    barcode = TextEditingController(text: inventoryText(p['barcode'], ''));
    description = TextEditingController(
      text: inventoryText(p['description'], ''),
    );
    price = TextEditingController(
      text: (inventoryInt(p['salePriceCents']) / 100)
          .toStringAsFixed(2)
          .replaceAll('.', ','),
    );
    cost = TextEditingController(
      text: (inventoryInt(p['costPriceCents']) / 100)
          .toStringAsFixed(2)
          .replaceAll('.', ','),
    );
    unit = TextEditingController(text: inventoryText(p['unitMeasure'], 'un'));
    variants = inventoryRows(
      p['variants'],
    ).map((v) => Map<String, dynamic>.from(v)).toList();
    active = p['isActive'] != false;
    category = p['categoryId'] as String?;
    localUuid = inventoryText(p['localUuid'], inventoryKey());
  }

  @override
  void dispose() {
    for (final c in [name, barcode, description, price, cost, unit]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    final isNew = widget.product == null;
    final body = <String, dynamic>{
      'metadataOnly': true,
      'name': name.text.trim(),
      'barcode': barcode.text.trim().isEmpty ? null : barcode.text.trim(),
      'description': description.text.trim().isEmpty
          ? null
          : description.text.trim(),
      'salePriceCents': inventoryScaled(price.text, scale: 100),
      'unitMeasure': unit.text.trim(),
      'isActive': active,
      'categoryId': category,
      if (widget.product?['catalogRevision'] is num)
        'expectedCatalogRevision': inventoryInt(
          widget.product!['catalogRevision'],
        ),
      if (isNew) ...{
        'localUuid': localUuid,
        'niche': 'moda',
        'productType': unit.text.trim() == 'kg' ? 'peso' : 'unidade',
      },
      if (ref
                  .read(ownerInventoryCapabilitiesProvider)
                  .asData
                  ?.value['canViewCosts'] ==
              true &&
          (isNew ||
              (widget.product?['costSource'] != 'recipe_snapshot' &&
                  inventoryScaled(cost.text, scale: 100) !=
                      widget.product?['costPriceCents']))) ...{
        'costPriceCents': inventoryScaled(cost.text, scale: 100),
        'manualCostCents': inventoryScaled(cost.text, scale: 100),
      },
      'variants': variants
          .map(
            (v) => {
              if (v['id'] is String) 'id': v['id'],
              'sku': v['sku'],
              'colorLabel': v['colorLabel'],
              'sizeLabel': v['sizeLabel'],
              'priceAdditionalCents': inventoryInt(v['priceAdditionalCents']),
              'sortOrder': variants.indexOf(v),
              'isActive': v['isActive'] != false,
            },
          )
          .toList(),
      if (variants.isNotEmpty &&
          (isNew || inventoryRows(widget.product?['variants']).isEmpty)) ...{
        'catalogType': 'variant',
        'modelName': name.text.trim(),
        'variantLabel': 'Cor e tamanho',
      },
    };
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final api = ref.read(ownerInventoryApiProvider);
      if (isNew) {
        await api.post('/products', body);
      } else {
        await api.put('/products/${widget.product!['id']}', body);
      }
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
    final viewCost =
        ref
            .watch(ownerInventoryCapabilitiesProvider)
            .asData
            ?.value['canViewCosts'] ==
        true;
    return AlertDialog(
      title: Text(widget.product == null ? 'Novo produto' : 'Editar produto'),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Informações básicas',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: name,
                  enabled: !busy,
                  decoration: const InputDecoration(
                    labelText: 'Nome do produto',
                  ),
                  maxLength: 120,
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Informe o nome' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: barcode,
                  enabled: !busy,
                  decoration: const InputDecoration(
                    labelText: 'Código de barras',
                  ),
                  maxLength: 60,
                ),
                const SizedBox(height: 12),
                InventoryResource(
                  resource: '/categories?page=1&pageSize=100',
                  builder: (data) => DropdownButtonFormField<String>(
                    initialValue: category ?? '',
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Categoria'),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Sem categoria'),
                      ),
                      if (category != null &&
                          !inventoryRows(
                            data['items'],
                          ).any((c) => c['id'] == category))
                        DropdownMenuItem(
                          value: category,
                          child: const Text('Categoria atual'),
                        ),
                      for (final c in inventoryRows(data['items']))
                        DropdownMenuItem(
                          value: inventoryText(c['id']),
                          child: Text(
                            inventoryText(c['name']),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: busy
                        ? null
                        : (v) => category = v == '' ? null : v,
                  ),
                ),
                const SizedBox(height: 20),
                Text('Preços', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                TextFormField(
                  controller: price,
                  enabled: !busy,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Preço de venda (R\$)',
                  ),
                  validator: (v) => inventoryScaled(v ?? '', scale: 100) == null
                      ? 'Informe um preço válido'
                      : null,
                ),
                if (viewCost) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: cost,
                    enabled:
                        !busy &&
                        widget.product?['costSource'] != 'recipe_snapshot',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Custo manual (R\$)',
                    ),
                    validator: (v) =>
                        inventoryScaled(v ?? '', scale: 100) == null
                        ? 'Informe um custo válido'
                        : null,
                  ),
                ],
                const SizedBox(height: 16),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Variações e configurações'),
                  children: [
                    TextFormField(
                      controller: unit,
                      enabled: !busy,
                      decoration: const InputDecoration(
                        labelText: 'Unidade de medida',
                      ),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Informe a unidade'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: description,
                      enabled: !busy,
                      maxLines: 3,
                      maxLength: 500,
                      decoration: const InputDecoration(labelText: 'Descrição'),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: active,
                      title: const Text('Produto ativo'),
                      onChanged: busy
                          ? null
                          : (v) => setState(() => active = v ?? true),
                    ),
                    for (final v in variants)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextFormField(
                              initialValue: inventoryText(v['sku'], ''),
                              enabled: !busy,
                              decoration: const InputDecoration(
                                labelText: 'SKU da variação',
                              ),
                              validator: (s) => s == null || s.trim().isEmpty
                                  ? 'Informe o SKU'
                                  : null,
                              onChanged: (s) => v['sku'] = s.trim(),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              initialValue: inventoryText(v['colorLabel'], ''),
                              enabled: !busy,
                              decoration: const InputDecoration(
                                labelText: 'Cor',
                              ),
                              validator: (s) => s == null || s.trim().isEmpty
                                  ? 'Informe a cor'
                                  : null,
                              onChanged: (s) => v['colorLabel'] = s.trim(),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              initialValue: inventoryText(v['sizeLabel'], ''),
                              enabled: !busy,
                              decoration: const InputDecoration(
                                labelText: 'Tamanho',
                              ),
                              validator: (s) => s == null || s.trim().isEmpty
                                  ? 'Informe o tamanho'
                                  : null,
                              onChanged: (s) => v['sizeLabel'] = s.trim(),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              initialValue:
                                  (inventoryInt(v['priceAdditionalCents']) /
                                          100)
                                      .toStringAsFixed(2)
                                      .replaceAll('.', ','),
                              enabled: !busy,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Adicional no preço (R\$)',
                              ),
                              validator: (s) =>
                                  inventoryScaled(s ?? '', scale: 100) == null
                                  ? 'Informe um valor válido'
                                  : null,
                              onChanged: (s) => v['priceAdditionalCents'] =
                                  inventoryScaled(s, scale: 100),
                            ),
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              value: v['isActive'] != false,
                              title: const Text('Variação ativa'),
                              onChanged: busy
                                  ? null
                                  : (s) => setState(
                                      () => v['isActive'] = s ?? true,
                                    ),
                            ),
                          ],
                        ),
                      ),
                    OutlinedButton.icon(
                      onPressed: busy
                          ? null
                          : () => setState(
                              () => variants.add({
                                'sku': '',
                                'colorLabel': '',
                                'sizeLabel': '',
                                'isActive': true,
                              }),
                            ),
                      icon: const Icon(Icons.add),
                      label: const Text('Adicionar variação'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'O cadastro não altera quantidades. Registre o saldo inicial ou ajustes na área Estoque.',
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
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: busy ? null : save,
          child: Text(busy ? 'Salvando…' : 'Salvar produto'),
        ),
      ],
    );
  }
}
