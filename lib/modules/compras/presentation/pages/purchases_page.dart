import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/widgets/app_input.dart';
import '../../../../app/core/widgets/app_main_drawer.dart';
import '../../../../app/core/widgets/app_page_header.dart';
import '../../../../app/routes/route_names.dart';
import '../../domain/entities/purchase_status.dart';
import '../providers/purchase_providers.dart';
import '../widgets/purchase_card.dart';

class PurchasesPage extends ConsumerWidget {
  const PurchasesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final purchasesAsync = ref.watch(purchaseListProvider);
    final selectedStatus = ref.watch(purchaseStatusFilterProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Compras')),
      drawer: const AppMainDrawer(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await context.pushNamed(AppRouteNames.purchaseForm);
          if (created == true) {
            ref.invalidate(purchaseListProvider);
          }
        },
        icon: const Icon(Icons.add_shopping_cart_rounded),
        label: const Text('Nova compra'),
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: AppPageHeader(
              title: 'Compras',
              subtitle:
                  'Controle entradas, pagamentos e pend\u00eancias com uma leitura mais clara do abastecimento.',
              badgeLabel: 'Suprimentos',
              badgeIcon: Icons.shopping_bag_outlined,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: AppInput(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Buscar por fornecedor, documento ou refer\u00eancia',
              onChanged: (value) {
                ref.read(purchaseSearchQueryProvider.notifier).state = value;
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: DropdownButtonFormField<PurchaseStatus?>(
              initialValue: selectedStatus,
              decoration: const InputDecoration(labelText: 'Status'),
              items: [
                const DropdownMenuItem<PurchaseStatus?>(
                  value: null,
                  child: Text('Todos'),
                ),
                for (final status in PurchaseStatus.values)
                  DropdownMenuItem<PurchaseStatus?>(
                    value: status,
                    child: Text(status.label),
                  ),
              ],
              onChanged: (value) {
                ref.read(purchaseStatusFilterProvider.notifier).state = value;
              },
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: purchasesAsync.when(
              data: (purchases) {
                if (purchases.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Nenhuma compra encontrada para os filtros.'),
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(purchaseListProvider);
                    await ref.read(purchaseListProvider.future);
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                    itemCount: purchases.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final purchase = purchases[index];
                      return PurchaseCard(
                        purchase: purchase,
                        onTap: () => context.pushNamed(
                          AppRouteNames.purchaseDetail,
                          pathParameters: {'purchaseId': '${purchase.id}'},
                        ),
                      );
                    },
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Falha ao carregar compras: $error'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
