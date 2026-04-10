import 'package:flutter/material.dart';

import '../../../../app/core/sync/sync_queue_feature_summary.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import 'sync_feature_card.dart';

class SystemSyncQueueSection extends StatelessWidget {
  const SystemSyncQueueSection({
    required this.canRunManualSync,
    required this.isLoading,
    required this.supplierSummary,
    required this.categorySummary,
    required this.productSummary,
    required this.customerSummary,
    required this.purchaseSummary,
    required this.salesSummary,
    required this.onSupplierSync,
    required this.onCategorySync,
    required this.onProductSync,
    required this.onClientSync,
    required this.onPurchaseSync,
    required this.onSalesSync,
    super.key,
  });

  final bool canRunManualSync;
  final bool isLoading;
  final SyncQueueFeatureSummary? supplierSummary;
  final SyncQueueFeatureSummary? categorySummary;
  final SyncQueueFeatureSummary? productSummary;
  final SyncQueueFeatureSummary? customerSummary;
  final SyncQueueFeatureSummary? purchaseSummary;
  final SyncQueueFeatureSummary? salesSummary;
  final VoidCallback onSupplierSync;
  final VoidCallback onCategorySync;
  final VoidCallback onProductSync;
  final VoidCallback onClientSync;
  final VoidCallback onPurchaseSync;
  final VoidCallback onSalesSync;

  @override
  Widget build(BuildContext context) {
    final features = <_SyncQueueFeatureConfig>[
      _SyncQueueFeatureConfig(
        featureKey: 'suppliers',
        title: 'Fornecedores',
        summary: supplierSummary,
        enabledDescription:
            'Primeira etapa das compras remotas. Garante vinculo consistente antes do envio das compras.',
        disabledDescription:
            'Entre com login remoto e ative o modo hibrido pronto para sincronizar os fornecedores.',
        buttonLabel: 'Sincronizar fornecedores',
        onPressed: onSupplierSync,
      ),
      _SyncQueueFeatureConfig(
        featureKey: 'categories',
        title: 'Categorias',
        summary: categorySummary,
        enabledDescription:
            'Primeira etapa da fila. Consolida dependencias de catalogo antes do push de produtos.',
        disabledDescription:
            'Entre com login remoto e ative o modo hibrido pronto para sincronizar as categorias.',
        buttonLabel: 'Sincronizar categorias',
        onPressed: onCategorySync,
      ),
      _SyncQueueFeatureConfig(
        featureKey: 'products',
        title: 'Produtos',
        summary: productSummary,
        enabledDescription:
            'Respeita dependencia de categoria remota, aplica retry controlado e detecta conflito basico por updatedAt.',
        disabledDescription:
            'Entre com login remoto e ative o modo hibrido pronto para sincronizar os produtos.',
        buttonLabel: 'Sincronizar produtos',
        onPressed: onProductSync,
      ),
      _SyncQueueFeatureConfig(
        featureKey: 'customers',
        title: 'Clientes',
        summary: customerSummary,
        enabledDescription:
            'Mantem o cadastro local offline, reprocessa falhas elegiveis e aplica soft delete remoto com seguranca.',
        disabledDescription:
            'Entre com login remoto e ative o modo hibrido pronto para sincronizar os clientes.',
        buttonLabel: 'Sincronizar clientes',
        onPressed: onClientSync,
      ),
      _SyncQueueFeatureConfig(
        featureKey: 'purchases',
        title: 'Compras',
        summary: purchaseSummary,
        enabledDescription:
            'Espelha compras locais com itens e pagamentos, sem reaplicar estoque ou caixa no retorno remoto.',
        disabledDescription:
            'Entre com login remoto e ative o modo hibrido pronto para sincronizar as compras.',
        buttonLabel: 'Sincronizar compras',
        onPressed: onPurchaseSync,
      ),
      _SyncQueueFeatureConfig(
        featureKey: 'sales',
        title: 'Vendas',
        summary: salesSummary,
        enabledDescription:
            'Espelha vendas locais ativas no backend com idempotencia por localUuid. Caixa, fiado, lucro e relatorios continuam 100% locais nesta fase.',
        disabledDescription:
            'Entre com login remoto e ative o modo hibrido pronto para espelhar as vendas locais.',
        buttonLabel: 'Sincronizar vendas',
        onPressed: onSalesSync,
      ),
    ];

    return AppSectionCard(
      title: 'Fila de sincronizacao por feature',
      subtitle:
          'Processamento ordenado de fornecedores, categorias, produtos, clientes, compras e vendas, sempre preservando o SQLite como base operacional local e o backend como espelho progressivo.',
      child: Column(
        children: [
          for (var index = 0; index < features.length; index++) ...[
            _buildFeatureCard(features[index]),
            if (index < features.length - 1) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Widget _buildFeatureCard(_SyncQueueFeatureConfig config) {
    return SyncFeatureCard(
      title: config.title,
      summary: config.summary,
      description: canRunManualSync
          ? config.enabledDescription
          : config.disabledDescription,
      buttonLabel: config.buttonLabel,
      isEnabled: canRunManualSync,
      isLoading: isLoading,
      onPressed: config.onPressed,
    );
  }
}

class _SyncQueueFeatureConfig {
  const _SyncQueueFeatureConfig({
    required this.featureKey,
    required this.title,
    required this.summary,
    required this.enabledDescription,
    required this.disabledDescription,
    required this.buttonLabel,
    required this.onPressed,
  });

  final String featureKey;
  final String title;
  final SyncQueueFeatureSummary? summary;
  final String enabledDescription;
  final String disabledDescription;
  final String buttonLabel;
  final VoidCallback onPressed;
}
