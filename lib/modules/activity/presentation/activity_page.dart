import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/core/formatters/app_formatters.dart';
import '../../../app/core/session/session_provider.dart';
import '../../../app/core/widgets/app_main_drawer.dart';
import '../../../app/core/widgets/app_list_tile_card.dart';
import '../../../app/core/widgets/app_section_card.dart';
import '../../../app/routes/route_names.dart';
import '../../vendas/domain/entities/sale_enums.dart';
import 'activity_providers.dart';

class ActivityPage extends ConsumerWidget {
  const ActivityPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(appSessionProvider);
    final snapshot = ref.watch(dailySaleActivityProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Atividade')),
      drawer: const AppMainDrawer(),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppListTileCard(
            title: 'Histórico de vendas',
            subtitle: 'Consulte vendas, trocas e comprovantes.',
            leading: const Icon(Icons.history),
            onTap: () => context.pushNamed(AppRouteNames.salesHistory),
          ),
          if (session.canAccessPermission('sales.create')) ...[
            const SizedBox(height: 12),
            AppListTileCard(
              title: 'Pedidos',
              subtitle: 'Acompanhe os pedidos da loja.',
              leading: const Icon(Icons.receipt_long_outlined),
              onTap: () => context.pushNamed(AppRouteNames.orders),
            ),
          ],
          const SizedBox(height: 16),
          AppSectionCard(
            title: 'Vendas de hoje',
            subtitle:
                'Neste dispositivo. Toque para consultar a venda e o cliente.',
            child: snapshot.when(
              data: (data) => data.isEmpty
                  ? const Text(
                      'Nenhuma venda registrada hoje neste dispositivo.',
                    )
                  : Column(
                      children: [
                        for (final sale in data)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text('Venda ${sale.receiptNumber}'),
                            subtitle: Text(
                              '${TimeOfDay.fromDateTime(sale.soldAt.toLocal()).format(context)} • ${sale.clientName ?? "Sem cliente"} • ${sale.status.label}',
                            ),
                            trailing: Text(
                              AppFormatters.currencyFromCents(sale.finalCents),
                            ),
                            onTap: () => context.pushNamed(
                              AppRouteNames.saleDetail,
                              pathParameters: {'saleId': '${sale.id}'},
                            ),
                          ),
                      ],
                    ),
              loading: () => const Text('Carregando vendas…'),
              error: (_, _) => TextButton(
                onPressed: () => ref.invalidate(dailySaleActivityProvider),
                child: const Text('Tentar carregar novamente'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
