import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/owner_providers.dart';
import '../../../core/models/owner_models.dart';
import '../../../core/widgets/owner_async_view.dart';
import '../../../core/widgets/owner_formatters.dart';
import '../../../core/widgets/owner_management_widgets.dart';

class OwnerProductsPage extends ConsumerWidget {
  const OwnerProductsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(ownerProductsReportProvider);
    final stock = ref.watch(ownerStockSummaryProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const OwnerPageIntro(
          title: 'Produtos e estoque',
          subtitle:
              'Monitore produtos mais vendidos, estoque baixo, itens zerados e categorias.',
          icon: Icons.inventory_2_outlined,
        ),
        const SizedBox(height: 18),
        OwnerAsyncView(
          value: products,
          onRetry: () => ref.invalidate(ownerProductsReportProvider),
          builder: (data) => _ProductsContent(report: data, stock: stock),
        ),
      ],
    );
  }
}

class _ProductsContent extends StatelessWidget {
  const _ProductsContent({required this.report, required this.stock});

  final OwnerProductsReport report;
  final AsyncValue<OwnerStockSummary> stock;

  @override
  Widget build(BuildContext context) {
    final summary = report.stockSummary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            OwnerMetricCard(
              title: 'Total de produtos',
              value: '${summary.totalProducts}',
              detail: 'Produtos ativos monitorados.',
              icon: Icons.inventory_2_outlined,
              isAvailable: true,
            ),
            OwnerMetricCard(
              title: 'Estoque baixo',
              value: '${summary.lowStockCount}',
              detail: 'Itens abaixo do mínimo operacional.',
              icon: Icons.inventory_outlined,
              isAvailable: true,
            ),
            OwnerMetricCard(
              title: 'Zerados',
              value: '${summary.outOfStockCount}',
              detail: 'Produtos sem saldo disponível.',
              icon: Icons.remove_shopping_cart_outlined,
              isAvailable: true,
            ),
            OwnerMetricCard(
              title: 'Custo estimado',
              value: summary.totalEstimatedCostCents == null
                  ? 'Sem dados'
                  : OwnerFormatters.moneyFromCents(
                      summary.totalEstimatedCostCents!,
                    ),
              detail: 'Valor estimado do estoque com dados seguros.',
              icon: Icons.account_balance_wallet_outlined,
              isAvailable: summary.totalEstimatedCostCents != null,
            ),
          ],
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SizedBox(
              width: 420,
              child: OwnerSectionCard(
                title: 'Produtos mais vendidos',
                subtitle: 'Ranking de vendas por produto.',
                child: _ProductSalesList(items: report.topSellingProducts),
              ),
            ),
            SizedBox(
              width: 420,
              child: OwnerSectionCard(
                title: 'Categorias',
                subtitle: 'Desempenho e composição do catálogo.',
                child: _CategoryList(items: report.byCategory),
              ),
            ),
            SizedBox(
              width: 420,
              child: OwnerSectionCard(
                title: 'Estoque baixo',
                subtitle: 'Itens que precisam de atenção.',
                child: stock.when(
                  data: (data) => _StockList(items: data.itemsLowStock),
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, _) => const OwnerEmptyState(
                    title: 'Não foi possível carregar o estoque',
                    message: 'Tente novamente em alguns instantes.',
                    icon: Icons.inventory_outlined,
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 420,
              child: OwnerSectionCard(
                title: 'Produtos zerados',
                subtitle: 'Itens sem saldo disponível.',
                child: stock.when(
                  data: (data) => _StockList(items: data.itemsOutOfStock),
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, _) => const OwnerEmptyState(
                    title: 'Não foi possível carregar o estoque',
                    message: 'Tente novamente em alguns instantes.',
                    icon: Icons.inventory_outlined,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ProductSalesList extends StatelessWidget {
  const _ProductSalesList({required this.items});

  final List<OwnerProductSalesItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const OwnerEmptyState(
        title: 'Sem vendas de produtos no período',
        message: 'O ranking aparecerá quando houver vendas de produtos.',
      );
    }
    return Column(
      children: [
        for (final item in items)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(item.productName),
            subtitle: Text(
              '${item.salesCount} vendas - ${OwnerFormatters.quantityFromMil(item.quantityMil)} un.',
            ),
            trailing: Text(OwnerFormatters.moneyFromCents(item.amountCents)),
          ),
      ],
    );
  }
}

class _CategoryList extends StatelessWidget {
  const _CategoryList({required this.items});

  final List<OwnerProductCategorySummary> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const OwnerEmptyState(
        title: 'Sem categorias para exibir',
        message: 'As categorias aparecerão quando houver vendas por produto.',
        icon: Icons.category_outlined,
      );
    }
    return Column(
      children: [
        for (final item in items)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(item.categoryName),
            subtitle: Text('${item.salesCount} vendas'),
            trailing: Text(OwnerFormatters.moneyFromCents(item.amountCents)),
          ),
      ],
    );
  }
}

class _StockList extends StatelessWidget {
  const _StockList({required this.items});

  final List<OwnerStockItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const OwnerEmptyState(
        title: 'Nenhum item encontrado',
        message: 'Não há produtos nesta condição agora.',
        icon: Icons.check_circle_outline_rounded,
      );
    }
    return Column(
      children: [
        for (final item in items)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              item.variantName == null
                  ? item.name
                  : '${item.name} - ${item.variantName}',
            ),
            subtitle: Text(
              'Saldo ${OwnerFormatters.quantityFromMil(item.currentStockMil)}',
            ),
            trailing: Text(OwnerFormatters.moneyFromCents(item.salePriceCents)),
          ),
      ],
    );
  }
}
