import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/owner_providers.dart';
import '../../../core/models/owner_models.dart';
import '../../../core/widgets/owner_async_view.dart';
import '../../../core/widgets/owner_management_widgets.dart';

class OwnerReportsPage extends ConsumerWidget {
  const OwnerReportsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(ownerReportsCatalogProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const OwnerPageIntro(
          title: 'Relatórios',
          subtitle:
              'Central de relatórios gerenciais por tema para acompanhar a empresa.',
          icon: Icons.assessment_outlined,
        ),
        const SizedBox(height: 18),
        OwnerAsyncView(
          value: catalog,
          onRetry: () => ref.invalidate(ownerReportsCatalogProvider),
          builder: (data) {
            if (data.items.isEmpty) {
              return const OwnerEmptyState(
                title: 'Relatórios em preparação',
                message:
                    'Os temas de relatórios aparecerão aqui conforme forem liberados.',
                icon: Icons.insights_rounded,
              );
            }
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                for (final item in data.items)
                  OwnerReportThemeCard(
                    title: item.title,
                    description: item.description,
                    icon: _reportIcon(item.key),
                    available: item.available,
                    reason: _friendlyReason(item),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

IconData _reportIcon(String key) {
  switch (key) {
    case 'sales':
      return Icons.point_of_sale_rounded;
    case 'products':
      return Icons.inventory_2_outlined;
    case 'cash':
      return Icons.account_balance_wallet_outlined;
    case 'stock':
      return Icons.warehouse_outlined;
    case 'customers':
      return Icons.people_alt_outlined;
    case 'purchases':
      return Icons.local_shipping_outlined;
    case 'profitability':
      return Icons.trending_up_rounded;
    case 'employees':
      return Icons.badge_outlined;
    default:
      return Icons.assessment_outlined;
  }
}

String? _friendlyReason(OwnerReportCatalogItem item) {
  if (item.available) {
    return null;
  }
  switch (item.reason) {
    case 'NO_PRODUCTS_REGISTERED':
      return 'Será exibido quando houver produtos cadastrados.';
    case 'NO_CUSTOMER_DATA':
      return 'Será exibido quando houver clientes ou vendas.';
    case 'NO_SALES_DATA':
      return 'Será exibido quando houver vendas no período.';
    case 'EMPLOYEE_REPORTS_NOT_AVAILABLE':
      return 'Será exibido quando houver vendas vinculadas aos usuários.';
    case 'PURCHASE_REPORTS_NOT_AVAILABLE':
      return 'Este relatório será liberado em uma próxima atualização.';
    default:
      return 'Este relatório será liberado em uma próxima atualização.';
  }
}
