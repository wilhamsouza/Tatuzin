import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/core/formatters/app_formatters.dart';
import '../../../app/core/session/session_provider.dart';
import '../../../app/core/widgets/app_main_drawer.dart';
import '../../../app/core/widgets/app_list_tile_card.dart';
import '../../../app/core/widgets/app_section_card.dart';
import '../../../app/routes/route_names.dart';
import '../../dashboard/presentation/providers/dashboard_providers.dart';

class ActivityPage extends ConsumerWidget {
  const ActivityPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(appSessionProvider);
    final snapshot = ref.watch(operationalDashboardSnapshotProvider);
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
            title: 'Movimentações recentes',
            subtitle: 'Neste dispositivo.',
            child: snapshot.when(
              data: (data) => data.recentMovements.isEmpty
                  ? const Text('As próximas movimentações aparecerão aqui.')
                  : Column(
                      children: [
                        for (final movement in data.recentMovements)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(movement.label),
                            subtitle: Text(
                              AppFormatters.shortDate(movement.createdAt),
                            ),
                            trailing: Text(
                              AppFormatters.currencyFromCents(
                                movement.amountCents,
                              ),
                            ),
                          ),
                      ],
                    ),
              loading: () => const Text('Carregando movimentações…'),
              error: (_, _) => TextButton(
                onPressed: () =>
                    ref.invalidate(operationalDashboardSnapshotProvider),
                child: const Text('Tentar carregar novamente'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
