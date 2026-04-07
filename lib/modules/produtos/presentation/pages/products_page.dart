import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/providers/app_data_refresh_provider.dart';
import '../../../../app/core/widgets/app_input.dart';
import '../../../../app/core/widgets/app_main_drawer.dart';
import '../../../../app/core/widgets/app_page_header.dart';
import '../../../../app/core/widgets/app_status_badge.dart';
import '../../../../app/routes/route_names.dart';
import '../../domain/entities/product.dart';
import '../providers/product_providers.dart';

class ProductsPage extends ConsumerWidget {
  const ProductsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(productListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Produtos')),
      drawer: const AppMainDrawer(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await context.pushNamed(AppRouteNames.productForm);
          if (created == true) {
            ref.invalidate(productListProvider);
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('Novo produto'),
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: AppPageHeader(
              title: 'Produtos',
              subtitle:
                  'Gerencie o catálogo com nome comercial, variações simples, preço, estoque e código de barras.',
              badgeLabel: 'Catálogo',
              badgeIcon: Icons.inventory_2_rounded,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: AppInput(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Buscar por nome, modelo, variação ou código',
              onChanged: (value) {
                ref.read(productSearchQueryProvider.notifier).state = value;
              },
            ),
          ),
          Expanded(
            child: productsAsync.when(
              data: (products) {
                if (products.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Nenhum produto cadastrado ainda.'),
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(productListProvider);
                    await ref.read(productListProvider.future);
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                    itemCount: products.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final product = products[index];
                      final showModelHeader = _shouldShowModelHeader(
                        products: products,
                        index: index,
                      );

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (showModelHeader) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                              child: Text(
                                product.modelName!,
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ),
                          ],
                          _ProductTile(product: product),
                        ],
                      );
                    },
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Falha ao carregar produtos: $error'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _shouldShowModelHeader({
    required List<Product> products,
    required int index,
  }) {
    final current = products[index];
    if (!current.isVariantCatalog ||
        current.modelName == null ||
        current.modelName!.trim().isEmpty) {
      return false;
    }

    if (index == 0) {
      return true;
    }

    final previous = products[index - 1];
    final currentGroup = current.modelName!.trim().toLowerCase();
    final previousGroup = previous.modelName?.trim().toLowerCase();
    return currentGroup != previousGroup;
  }
}

class _ProductTile extends ConsumerWidget {
  const _ProductTile({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final subtitleParts = <String>[
      if (product.catalogSubtitle != null) product.catalogSubtitle!,
      if (product.categoryName?.trim().isNotEmpty ?? false)
        product.categoryName!,
      if (product.barcode?.trim().isNotEmpty ?? false)
        'Cód. ${product.barcode}',
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.displayName,
                        style: theme.textTheme.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (subtitleParts.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          subtitleParts.join(' • '),
                          style: theme.textTheme.bodySmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Wrap(
                  spacing: 4,
                  children: [
                    IconButton(
                      tooltip: 'Editar',
                      onPressed: () async {
                        final updated = await context.pushNamed(
                          AppRouteNames.productForm,
                          extra: product,
                        );
                        if (updated == true) {
                          ref.invalidate(productListProvider);
                        }
                      },
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      tooltip: 'Excluir',
                      onPressed: () => _delete(context, ref),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _ProductMetric(
                  label: 'Preço de venda',
                  value: AppFormatters.currencyFromCents(
                    product.salePriceCents,
                  ),
                ),
                _ProductMetric(
                  label: 'Estoque atual',
                  value:
                      '${AppFormatters.quantityFromMil(product.stockMil)} ${product.unitMeasure}',
                ),
                AppStatusBadge(
                  label: product.isVariantCatalog ? 'Com variação' : 'Simples',
                  tone: product.isVariantCatalog
                      ? AppStatusTone.info
                      : AppStatusTone.neutral,
                ),
                AppStatusBadge(
                  label: product.isActive ? 'Ativo' : 'Inativo',
                  tone: product.isActive
                      ? AppStatusTone.success
                      : AppStatusTone.neutral,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Excluir produto'),
          content: Text('Deseja excluir "${product.displayName}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Excluir'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await ref.read(productRepositoryProvider).delete(product.id);
      ref.read(appDataRefreshProvider.notifier).state++;
      ref.invalidate(productListProvider);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Produto "${product.displayName}" excluído.')),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível excluir o produto: $error')),
      );
    }
  }
}

class _ProductMetric extends StatelessWidget {
  const _ProductMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.titleSmall),
        ],
      ),
    );
  }
}
