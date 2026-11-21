import '../../../../app/core/widgets/product_stock_surface.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/session/session_provider.dart';
import '../../../../app/core/widgets/app_main_drawer.dart';
import '../../../../app/core/widgets/app_state_card.dart';
import '../../../../app/routes/route_names.dart';
import '../../../categorias/presentation/providers/category_providers.dart';
import '../../domain/entities/product.dart';
import '../providers/product_providers.dart';

/// Retained for callers compiled against the former combined product hub.
/// Inventory routes now open their own workspace.
enum ProductHubTab { catalog, inventory }

class ProductsPage extends ConsumerStatefulWidget {
  const ProductsPage({super.key, this.initialTab = ProductHubTab.catalog});
  final ProductHubTab initialTab;
  @override
  ConsumerState<ProductsPage> createState() => _ProductsState();
}

class _ProductsState extends ConsumerState<ProductsPage> {
  final search = TextEditingController();
  Timer? debounce;
  int? categoryId;
  String status = 'all';
  @override
  void initState() {
    super.initState();
    search.text = ref.read(productSearchQueryProvider);
  }

  @override
  void dispose() {
    search.dispose();
    debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(appSessionProvider);
    final canWrite = session.canAccessPermission('products.write');
    final canStock =
        session.canAccessPermission('stock.adjust') ||
        session.canAccessPermission('reports.advanced');
    final categories = ref.watch(categoryOptionsProvider).asData?.value ?? [];
    ref.listen(sessionRuntimeKeyProvider, (previous, next) {
      if (previous != null && previous != next) {
        search.clear();
        categoryId = null;
        status = 'all';
        ref.read(productSearchQueryProvider.notifier).state = '';
      }
    });
    return Scaffold(
      appBar: AppBar(
        title: const Text('Produtos'),
        actions: [
          if (canStock)
            IconButton(
              tooltip: 'Abrir estoque',
              onPressed: () => context.pushNamed(AppRouteNames.inventory),
              icon: const Icon(Icons.inventory_2_outlined),
            ),
        ],
      ),
      drawer: const AppMainDrawer(),
      floatingActionButton: canWrite
          ? FloatingActionButton.extended(
              onPressed: () => _edit(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('Novo produto'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              children: [
                TextField(
                  controller: search,
                  decoration: InputDecoration(
                    hintText: 'Buscar produto, SKU ou código',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: search.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Limpar busca',
                            onPressed: () {
                              search.clear();
                              ref
                                      .read(productSearchQueryProvider.notifier)
                                      .state =
                                  '';
                              setState(() {});
                            },
                            icon: const Icon(Icons.close),
                          ),
                  ),
                  onChanged: (value) {
                    setState(() {});
                    debounce?.cancel();
                    debounce = Timer(
                      const Duration(milliseconds: 300),
                      () =>
                          ref.read(productSearchQueryProvider.notifier).state =
                              value,
                    );
                  },
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry in const {
                      'all': 'Todos',
                      'active': 'Ativos',
                      'inactive': 'Inativos',
                    }.entries)
                      ChoiceChip(
                        label: Text(entry.value),
                        selected: status == entry.key,
                        onSelected: (_) => setState(() => status = entry.key),
                      ),
                  ],
                ),
                if (categories.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: DropdownButtonFormField<int>(
                      initialValue:
                          categories.any((row) => row.id == categoryId)
                          ? categoryId
                          : null,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Categoria'),
                      items: [
                        const DropdownMenuItem<int>(
                          value: null,
                          child: Text('Todas as categorias'),
                        ),
                        for (final row in categories)
                          DropdownMenuItem(
                            value: row.id,
                            child: Text(
                              row.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) => setState(() => categoryId = value),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ref
                .watch(productListProvider)
                .when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => Padding(
                    padding: const EdgeInsets.all(16),
                    child: AppStateCard(
                      title: 'Não foi possível carregar o catálogo',
                      message: '$error',
                      tone: AppStateTone.error,
                      actionLabel: 'Tentar novamente',
                      onAction: () => ref.invalidate(productListProvider),
                    ),
                  ),
                  data: (products) {
                    final visible = products
                        .where(
                          (product) =>
                              (categoryId == null ||
                                  product.categoryId == categoryId) &&
                              (status == 'all' ||
                                  product.isActive == (status == 'active')),
                        )
                        .toList();
                    return RefreshIndicator(
                      onRefresh: () async {
                        ref.invalidate(productListProvider);
                        await ref.read(productListProvider.future);
                      },
                      child: ListView.separated(
                        key: const PageStorageKey('product-catalog'),
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                        itemCount: visible.isEmpty ? 1 : visible.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          if (visible.isEmpty) {
                            return AppStateCard(
                              title: products.isEmpty
                                  ? 'Nenhum produto cadastrado'
                                  : 'Nenhum produto neste filtro',
                              message: products.isEmpty
                                  ? 'Cadastre os itens que sua empresa vende.'
                                  : 'Ajuste a busca, a categoria ou a situação.',
                              actionLabel: canWrite && products.isEmpty
                                  ? 'Novo produto'
                                  : null,
                              onAction: canWrite
                                  ? () => _edit(context, ref)
                                  : null,
                            );
                          }
                          return _ProductCard(product: visible[index]);
                        },
                      ),
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }
}

Future<void> _edit(
  BuildContext context,
  WidgetRef ref, [
  Product? product,
]) async {
  final result = await context.pushNamed(
    AppRouteNames.productForm,
    extra: product,
  );
  if (result == true) ref.invalidate(productListProvider);
}

class _ProductCard extends ConsumerWidget {
  const _ProductCard({required this.product});
  final Product product;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(appSessionProvider);
    final variants = product.variants;
    final heading = ListTile(
      contentPadding: const EdgeInsets.all(12),
      leading: _ProductImage(product: product),
      title: Text(
        product.name,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        [
          if (product.barcode != null) 'Código ${product.barcode}',
          if (product.categoryName != null) product.categoryName!,
          product.isActive ? 'Ativo' : 'Inativo',
          AppFormatters.currencyFromCents(product.salePriceCents),
        ].join('\n'),
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              ProductStockSurface(child: ProductDetailPage(product: product)),
        ),
      ),
    );
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          heading,
          if (variants.isNotEmpty)
            ExpansionTile(
              title: Text('${variants.length} variações'),
              children: [
                for (final variant in variants)
                  ListTile(
                    title: Text(
                      [
                        variant.colorLabel,
                        variant.sizeLabel,
                      ].where((part) => part.trim().isNotEmpty).join(' / '),
                    ),
                    subtitle: Text(
                      'SKU ${variant.sku} · ${variant.isActive ? 'Ativa' : 'Inativa'}',
                    ),
                    trailing: Text(
                      AppFormatters.currencyFromCents(
                        product.salePriceCents + variant.priceAdditionalCents,
                      ),
                    ),
                  ),
              ],
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Wrap(
              spacing: 4,
              children: [
                TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ProductStockSurface(
                        child: ProductDetailPage(product: product),
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.info_outline),
                  label: const Text('Detalhes'),
                ),
                if (session.canAccessPermission('products.write'))
                  TextButton.icon(
                    onPressed: () => _edit(context, ref, product),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Editar'),
                  ),
                if (session.canAccessPermission('stock.adjust') ||
                    session.canAccessPermission('reports.advanced'))
                  TextButton.icon(
                    onPressed: () => context.push(
                      '${AppRoutePaths.inventory}?productId=${product.remoteId ?? product.uuid}',
                    ),
                    icon: const Icon(Icons.inventory_2_outlined),
                    label: const Text('Ver no estoque'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductImage extends StatelessWidget {
  const _ProductImage({required this.product});
  final Product product;
  @override
  Widget build(BuildContext context) {
    final path = product.primaryPhotoPath;
    final fallback = Container(
      key: ValueKey('product-list-thumbnail-fallback-${product.id}'),
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        Icons.sell_outlined,
        color: Theme.of(context).colorScheme.onPrimaryContainer,
      ),
    );
    if (path == null || path.trim().isEmpty) return fallback;
    final Widget image = path.startsWith('https://')
        ? Image.network(
            path,
            width: 52,
            height: 52,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => fallback,
          )
        : Image.file(
            File(path),
            width: 52,
            height: 52,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => fallback,
          );
    return ClipRRect(
      key: ValueKey('product-list-thumbnail-${product.id}'),
      borderRadius: BorderRadius.circular(12),
      child: image,
    );
  }
}

class ProductDetailPage extends ConsumerWidget {
  const ProductDetailPage({super.key, required this.product});
  final Product product;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(appSessionProvider);
    final sensitive =
        session.canAccessPermission('products.write') ||
        session.canAccessPermission('stock.adjust') ||
        session.canAccessPermission('reports.advanced');
    return Scaffold(
      appBar: AppBar(title: const Text('Detalhes do produto')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(product.name, style: Theme.of(context).textTheme.headlineSmall),
          if (product.description?.trim().isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(product.description!),
            ),
          Text('Código: ${product.barcode ?? 'Não informado'}'),
          Text('Categoria: ${product.categoryName ?? 'Sem categoria'}'),
          Text('Situação: ${product.isActive ? 'Ativo' : 'Inativo'}'),
          const SizedBox(height: 20),
          Text('Preço de venda', style: Theme.of(context).textTheme.titleSmall),
          Text(
            AppFormatters.currencyFromCents(product.salePriceCents),
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          if (sensitive)
            Text(
              'Custo: ${AppFormatters.currencyFromCents(product.costCents)}',
            ),
          if (product.variants.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Variações', style: Theme.of(context).textTheme.titleLarge),
            for (final variant in product.variants)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${variant.colorLabel} / ${variant.sizeLabel}'),
                subtitle: Text(
                  'SKU ${variant.sku} · ${variant.isActive ? 'Ativa' : 'Inativa'}',
                ),
              ),
          ],
          const SizedBox(height: 16),
          if (session.canAccessPermission('products.write'))
            FilledButton.icon(
              onPressed: () => _edit(context, ref, product),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Editar produto'),
            ),
          if (session.canAccessPermission('stock.adjust') ||
              session.canAccessPermission('reports.advanced'))
            OutlinedButton.icon(
              onPressed: () => context.push(
                '${AppRoutePaths.inventory}?productId=${product.remoteId ?? product.uuid}',
              ),
              icon: const Icon(Icons.inventory_2_outlined),
              label: const Text('Ver no estoque'),
            ),
          if (session.canAccessPermission('products.write'))
            TextButton(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (dialog) => AlertDialog(
                    title: const Text('Inativar produto?'),
                    content: const Text(
                      'O histórico será preservado. O produto deixará de estar disponível para novas vendas.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(dialog).pop(false),
                        child: const Text('Cancelar'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(dialog).pop(true),
                        child: const Text('Inativar'),
                      ),
                    ],
                  ),
                );
                if (ok == true) {
                  try {
                    await ref
                        .read(productRepositoryProvider)
                        .delete(product.id);
                    ref.invalidate(productListProvider);
                    if (context.mounted) Navigator.of(context).pop();
                  } catch (error) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text('$error')));
                    }
                  }
                }
              },
              child: const Text('Inativar produto'),
            ),
        ],
      ),
    );
  }
}
