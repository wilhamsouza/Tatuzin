import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/owner_providers.dart';
import '../../../core/models/owner_models.dart';
import '../../../core/widgets/owner_async_view.dart';
import '../../../core/widgets/owner_formatters.dart';
import '../../../core/widgets/owner_management_widgets.dart';

class OwnerClientsPage extends ConsumerWidget {
  const OwnerClientsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(ownerCrmSummaryProvider);
    final customers = ref.watch(ownerCrmCustomersProvider);
    final selectedStatus = ref.watch(ownerCrmStatusProvider);
    final search = ref.watch(ownerCrmSearchProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const OwnerPageIntro(
          title: 'Clientes / CRM',
          subtitle:
              'Veja relacionamento, recorrência e oportunidades de reativação da base de clientes.',
          icon: Icons.people_alt_rounded,
        ),
        const SizedBox(height: 18),
        OwnerAsyncView(
          value: summary,
          onRetry: () => ref.invalidate(ownerCrmSummaryProvider),
          builder: (data) => _CrmSummaryCards(data: data),
        ),
        const SizedBox(height: 18),
        OwnerSectionCard(
          title: 'Clientes',
          subtitle: 'Lista paginada com compras, status e fiado em aberto.',
          trailing: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 240,
                child: TextFormField(
                  initialValue: search,
                  decoration: const InputDecoration(
                    labelText: 'Buscar cliente',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                  onChanged: (value) {
                    ref.read(ownerCrmSearchProvider.notifier).state = value;
                    ref.read(ownerCrmPageProvider.notifier).state = 1;
                  },
                ),
              ),
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<String>(
                  initialValue: selectedStatus,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Filtro'),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('Todos')),
                    DropdownMenuItem(value: 'active', child: Text('Ativos')),
                    DropdownMenuItem(
                      value: 'inactive',
                      child: Text('Inativos'),
                    ),
                    DropdownMenuItem(
                      value: 'with_receivables',
                      child: Text('Com fiado'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    ref.read(ownerCrmStatusProvider.notifier).state = value;
                    ref.read(ownerCrmPageProvider.notifier).state = 1;
                  },
                ),
              ),
            ],
          ),
          child: OwnerAsyncView(
            value: customers,
            onRetry: () => ref.invalidate(ownerCrmCustomersProvider),
            builder: (page) => _CustomerList(page: page),
          ),
        ),
      ],
    );
  }
}

class _CrmSummaryCards extends StatelessWidget {
  const _CrmSummaryCards({required this.data});

  final OwnerCrmSummary data;

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
              title: 'Total de clientes',
              value: '${data.totalCustomers}',
              detail: 'Clientes cadastrados no CRM.',
              icon: Icons.groups_outlined,
              isAvailable: true,
            ),
            OwnerMetricCard(
              title: 'Clientes ativos',
              value: '${data.activeCustomers}',
              detail: 'Com compras nos últimos ${data.inactiveAfterDays} dias.',
              icon: Icons.person_pin_circle_outlined,
              isAvailable: true,
            ),
            OwnerMetricCard(
              title: 'Clientes inativos',
              value: '${data.inactiveCustomers}',
              detail: 'Base para campanhas de reativação.',
              icon: Icons.person_off_outlined,
              isAvailable: true,
            ),
            OwnerMetricCard(
              title: 'Novos no mês',
              value: '${data.newCustomersThisMonth}',
              detail: 'Clientes cadastrados neste mês.',
              icon: Icons.person_add_alt_rounded,
              isAvailable: true,
            ),
            OwnerMetricCard(
              title: 'Clientes com fiado',
              value: '${data.customersWithReceivables}',
              detail: 'Clientes com saldo em aberto.',
              icon: Icons.request_quote_outlined,
              isAvailable: true,
            ),
          ],
        ),
        const SizedBox(height: 18),
        OwnerSectionCard(
          title: 'Top clientes',
          subtitle: 'Clientes com maior valor comprado.',
          child: _CustomerRanking(items: data.topCustomers),
        ),
      ],
    );
  }
}

class _CustomerRanking extends StatelessWidget {
  const _CustomerRanking({required this.items});

  final List<OwnerCrmCustomer> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const OwnerEmptyState(
        title: 'Indicador em preparação',
        message:
            'Este indicador será liberado quando houver dados suficientes.',
      );
    }
    return Column(
      children: [
        for (final item in items)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(item.name),
            subtitle: Text('${item.purchasesCount} compras'),
            trailing: Text(
              OwnerFormatters.moneyFromCents(item.totalPurchasedCents),
            ),
          ),
      ],
    );
  }
}

class _CustomerList extends StatelessWidget {
  const _CustomerList({required this.page});

  final OwnerCrmCustomerPage page;

  @override
  Widget build(BuildContext context) {
    if (page.items.isEmpty) {
      return const OwnerEmptyState(
        title: 'Nenhum cliente encontrado.',
        message:
            'Ajuste a busca ou aguarde os dados de clientes sincronizarem.',
        icon: Icons.people_alt_outlined,
      );
    }
    return Column(
      children: [
        for (final item in page.items)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.person_outline_rounded),
            title: Text(item.name),
            subtitle: Text(
              '${item.statusLabel} - ${item.purchasesCount} compras - Última compra ${OwnerFormatters.date(item.lastPurchaseAt)}',
            ),
            trailing: Text(
              item.openReceivableAmountCents > 0
                  ? OwnerFormatters.moneyFromCents(
                      item.openReceivableAmountCents,
                    )
                  : 'Sem fiado',
            ),
          ),
      ],
    );
  }
}
