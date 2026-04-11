import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/providers/app_data_refresh_provider.dart';
import '../../../../app/core/widgets/app_feedback.dart';
import '../../../../app/core/widgets/app_input.dart';
import '../../../../app/core/widgets/app_main_drawer.dart';
import '../../../../app/core/widgets/app_page_header.dart';
import '../../../../app/core/widgets/app_state_card.dart';
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
            padding: EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: AppPageHeader(
              title: 'Catálogo de produtos',
              subtitle:
                  'Consulte preço, estoque e variações com leitura mais rápida.',
              badgeLabel: 'Operação',
              badgeIcon: Icons.inventory_2_rounded,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: AppInput(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Buscar produto, variação ou código',
              onChanged: (value) {
                ref.read(productSearchQueryProvider.notifier).state = value;
              },
            ),
          ),
          Expanded(
            child: productsAsync.when(
              data: (products) {
                if (products.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 92),
                    child: AppStateCard(
                      title: 'Nenhum produto cadastrado',
                      message:
                          'Cadastre o primeiro item para montar o catálogo da operação.',
                      actionLabel: 'Novo produto',
                      onAction: () =>
                          context.pushNamed(AppRouteNames.productForm),
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(productListProvider);
                    await ref.read(productListProvider.future);
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 92),
                    itemCount: products.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final product = products[index];
                      final showGroupHeader = _shouldShowGroupHeader(
                        products: products,
                        index: index,
                      );

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (showGroupHeader) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(2, 2, 2, 6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  product.baseProductName ?? product.modelName!,
                                  style: Theme.of(context).textTheme.labelLarge
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
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
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: AppStateCard(
                  title: 'Carregando catálogo',
                  message: 'Buscando produtos e variações.',
                  tone: AppStateTone.loading,
                  compact: true,
                ),
              ),
              error: (error, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: AppStateCard(
                    title: 'Falha ao carregar produtos',
                    message: 'Tente novamente para atualizar o catálogo.',
                    tone: AppStateTone.error,
                    compact: true,
                    actionLabel: 'Tentar novamente',
                    onAction: () => ref.invalidate(productListProvider),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _shouldShowGroupHeader({
    required List<Product> products,
    required int index,
  }) {
    final current = products[index];
    final currentGroup = (current.baseProductName ?? current.modelName)?.trim();
    if (!current.isVariantCatalog ||
        currentGroup == null ||
        currentGroup.isEmpty) {
      return false;
    }

    if (index == 0) {
      return true;
    }

    final previous = products[index - 1];
    final previousGroup = (previous.baseProductName ?? previous.modelName)
        ?.trim()
        .toLowerCase();
    return currentGroup.toLowerCase() != previousGroup;
  }
}

class _ProductTile extends ConsumerWidget {
  const _ProductTile({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final subtitleParts = <String>[
      if (product.catalogSubtitle != null) product.catalogSubtitle!,
      if (product.categoryName?.trim().isNotEmpty ?? false)
        product.categoryName!,
      if (product.barcode?.trim().isNotEmpty ?? false)
        'Código ${product.barcode}',
    ];
    final detailLine = <String>[
      if (subtitleParts.isNotEmpty) subtitleParts.join(' • '),
      '${AppFormatters.quantityFromMil(product.stockMil)} ${product.unitMeasure} em estoque',
    ];
    final stockLow = product.stockMil < 1000;
    final hasModifiers = product.modifierGroupCount > 0;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openEditor(context, ref),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: stockLow
                      ? colorScheme.secondaryContainer.withValues(alpha: 0.82)
                      : colorScheme.primaryContainer.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  stockLow ? Icons.inventory_2_outlined : Icons.sell_outlined,
                  size: 20,
                  color: stockLow
                      ? colorScheme.onSecondaryContainer
                      : colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.displayName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      detailLine.join(' • '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (!product.isActive)
                          const AppStatusBadge(
                            label: 'Inativo',
                            tone: AppStatusTone.neutral,
                          ),
                        if (product.isVariantCatalog)
                          const AppStatusBadge(
                            label: 'Variação',
                            tone: AppStatusTone.info,
                          ),
                        if (hasModifiers)
                          AppStatusBadge(
                            label:
                                '+${product.modifierGroupCount} complemento${product.modifierGroupCount == 1 ? '' : 's'}',
                            tone: AppStatusTone.info,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    AppFormatters.currencyFromCents(product.salePriceCents),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    stockLow
                        ? 'Estoque baixo'
                        : product.isActive
                        ? 'Ativo'
                        : 'Inativo',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: stockLow
                          ? colorScheme.error
                          : colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              PopupMenuButton<_ProductAction>(
                tooltip: 'Ações do produto',
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: _ProductAction.edit,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Editar'),
                    ),
                  ),
                  PopupMenuItem(
                    value: _ProductAction.delete,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.delete_outline),
                      title: Text('Excluir'),
                    ),
                  ),
                ],
                onSelected: (value) async {
                  switch (value) {
                    case _ProductAction.edit:
                      await _openEditor(context, ref);
                      break;
                    case _ProductAction.delete:
                      await _delete(context, ref);
                      break;
                  }
                },
                icon: Icon(
                  Icons.more_vert_rounded,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openEditor(BuildContext context, WidgetRef ref) async {
    final updated = await context.pushNamed(
      AppRouteNames.productForm,
      extra: product,
    );
    if (updated == true) {
      ref.invalidate(productListProvider);
    }
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
      AppFeedback.success(
        context,
        'Produto "${product.displayName}" excluído.',
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      AppFeedback.error(context, 'Não foi possível excluir o produto: $error');
    }
  }
}

enum _ProductAction { edit, delete }
