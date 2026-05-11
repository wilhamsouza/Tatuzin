import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/owner_providers.dart';
import '../../../core/models/owner_models.dart';
import '../../../core/widgets/owner_async_view.dart';
import '../../../core/widgets/owner_formatters.dart';
import '../../../core/widgets/owner_management_widgets.dart';

class OwnerSalesPage extends ConsumerWidget {
  const OwnerSalesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sales = ref.watch(ownerSalesSummaryProvider);
    final groupBy = ref.watch(ownerSalesGroupByProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OwnerPageIntro(
          title: 'Vendas',
          subtitle:
              'Acompanhe faturamento, vendas recentes, formas de pagamento e evolução diária.',
          icon: Icons.point_of_sale_rounded,
          trailing: SizedBox(
            width: 190,
            child: DropdownButtonFormField<String>(
              initialValue: groupBy,
              decoration: const InputDecoration(labelText: 'Agrupar por'),
              items: const [
                DropdownMenuItem(value: 'day', child: Text('Dia')),
                DropdownMenuItem(value: 'week', child: Text('Semana')),
                DropdownMenuItem(value: 'month', child: Text('Mês')),
              ],
              onChanged: (value) {
                if (value != null) {
                  ref.read(ownerSalesGroupByProvider.notifier).state = value;
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 18),
        OwnerAsyncView(
          value: sales,
          onRetry: () => ref.invalidate(ownerSalesSummaryProvider),
          builder: (data) => _SalesContent(data: data),
        ),
      ],
    );
  }
}

class _SalesContent extends StatelessWidget {
  const _SalesContent({required this.data});

  final OwnerSalesSummary data;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            OwnerMetricCard(
              title: 'Vendas no período',
              value: '${data.totalCount}',
              detail: _periodText(data.period),
              icon: Icons.shopping_bag_outlined,
              isAvailable: true,
            ),
            OwnerMetricCard(
              title: 'Faturamento',
              value: OwnerFormatters.moneyFromCents(data.totalAmountCents),
              detail: 'Total vendido no período selecionado.',
              icon: Icons.payments_outlined,
              isAvailable: true,
            ),
            OwnerMetricCard(
              title: 'Ticket médio',
              value: OwnerFormatters.moneyFromCents(data.averageTicketCents),
              detail: 'Valor médio por venda.',
              icon: Icons.trending_up_rounded,
              isAvailable: true,
            ),
            OwnerMetricCard(
              title: 'Formas de pagamento',
              value: '${data.byPaymentMethod.length}',
              detail: 'Métodos usados nas vendas do período.',
              icon: Icons.credit_card_rounded,
              isAvailable: true,
            ),
          ],
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SizedBox(
              width: 480,
              child: OwnerSectionCard(
                title: 'Vendas recentes',
                subtitle: 'Últimas vendas registradas pela empresa.',
                child: _RecentSalesList(page: data.recentSales),
              ),
            ),
            SizedBox(
              width: 420,
              child: OwnerSectionCard(
                title: 'Formas de pagamento',
                subtitle: 'Distribuição por método amigável.',
                child: _PaymentMethodList(items: data.byPaymentMethod),
              ),
            ),
            SizedBox(
              width: 420,
              child: OwnerSectionCard(
                title: 'Vendas por período',
                subtitle: 'Evolução de faturamento conforme o agrupamento.',
                child: _SalesSeriesList(items: data.series),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RecentSalesList extends StatelessWidget {
  const _RecentSalesList({required this.page});

  final OwnerRecentSalesPage page;

  @override
  Widget build(BuildContext context) {
    if (page.items.isEmpty) {
      return const OwnerEmptyState(
        title: 'Nenhuma venda encontrada no período',
        message: 'As vendas recentes aparecerão aqui quando houver registros.',
      );
    }
    return Column(
      children: [
        for (final sale in page.items)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(_saleTitle(sale)),
            subtitle: Text(
              '${sale.paymentMethod} - ${OwnerFormatters.date(sale.soldAt)}',
            ),
            trailing: Text(
              OwnerFormatters.moneyFromCents(sale.totalAmountCents),
            ),
          ),
      ],
    );
  }
}

class _PaymentMethodList extends StatelessWidget {
  const _PaymentMethodList({required this.items});

  final List<OwnerPaymentMethodSummary> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const OwnerEmptyState(
        title: 'Sem formas de pagamento no período',
        message: 'A distribuição aparecerá quando houver vendas.',
        icon: Icons.credit_card_rounded,
      );
    }
    return Column(
      children: [
        for (final item in items)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.payments_outlined),
            title: Text(item.label),
            subtitle: Text('${item.count} vendas'),
            trailing: Text(
              OwnerFormatters.moneyFromCents(item.totalAmountCents),
            ),
          ),
      ],
    );
  }
}

class _SalesSeriesList extends StatelessWidget {
  const _SalesSeriesList({required this.items});

  final List<OwnerSalesSeriesPoint> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const OwnerEmptyState(
        title: 'Sem evolução para exibir',
        message: 'A série será preenchida quando houver vendas no período.',
        icon: Icons.show_chart_rounded,
      );
    }
    return Column(
      children: [
        for (final item in items)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(item.date),
            subtitle: Text('${item.totalCount} vendas'),
            trailing: Text(
              OwnerFormatters.moneyFromCents(item.totalAmountCents),
            ),
          ),
      ],
    );
  }
}

String _saleTitle(OwnerRecentSale sale) {
  final receipt = sale.receiptNumber;
  if (receipt == null || receipt.trim().isEmpty || receipt.trim().length > 20) {
    return sale.title;
  }
  return '${sale.title} #$receipt';
}

String _periodText(OwnerReportPeriod period) {
  if (period.startDate == null || period.endDate == null) {
    return 'Período selecionado.';
  }
  return '${period.startDate} a ${period.endDate}.';
}
