import 'package:flutter/material.dart';

import '../../../../app/core/widgets/app_section_card.dart';
import '../providers/system_providers.dart';
import 'system_support_widgets.dart';

class SystemHybridGovernanceSection extends StatelessWidget {
  const SystemHybridGovernanceSection({required this.snapshot, super.key});

  final HybridOperationalTruthSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      title: 'Governanca hibrida local-first',
      subtitle:
          'Resumo operacional local para deixar explicito que catalogo, estoque e clientes continuam vendendo offline, enquanto o cloud fica como governanca e espelho.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SystemInfoRow(
            label: 'Catalogo local',
            value:
                '${snapshot.activeProducts} produto(s) ativo(s), ${snapshot.activeCategories} categoria(s) e ${snapshot.productsWithLocalPhoto} foto(s) locais conhecidas.',
          ),
          SystemInfoRow(
            label: 'Catalogo cloud',
            value: snapshot.localOnlyProducts == 0
                ? 'Todos os produtos ja possuem identidade remota quando a sync alcança.'
                : '${snapshot.localOnlyProducts} produto(s) ainda so existem localmente e seguem operando mesmo sem cloud.',
          ),
          SystemInfoRow(
            label: 'Estoque local',
            value:
                '${snapshot.inventoryTrackedItems} item(ns) de estoque acompanhados na base local do dispositivo.',
          ),
          SystemInfoRow(
            label: 'Clientes',
            value:
                '${snapshot.activeCustomers} cliente(s) ativos; ${snapshot.localOnlyCustomers} ainda dependem apenas do snapshot operacional local.',
          ),
          SystemInfoRow(
            label: 'Comportamento',
            value: snapshot.hasPendingCloudAttention
                ? 'Existem pendencias ou atencoes de cloud, mas a venda local continua habilitada.'
                : 'Sem atencoes de cloud neste momento; mesmo assim a venda local nao depende do backend.',
          ),
        ],
      ),
    );
  }
}
