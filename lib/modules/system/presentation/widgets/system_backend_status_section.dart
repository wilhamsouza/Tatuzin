import 'package:flutter/material.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import '../providers/system_providers.dart';
import 'system_support_widgets.dart';

class SystemBackendStatusSection extends StatelessWidget {
  const SystemBackendStatusSection({
    required this.status,
    required this.onTestConnection,
    super.key,
  });

  final BackendConnectionStatus status;
  final VoidCallback onTestConnection;

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      title: 'API oficial do Tatuzin',
      subtitle:
          'Saude do backend remoto oficial e validacao do tenant sem acoplar vendas, caixa ou relatorios a HTTP.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SystemStateTile(
            icon: status.isReachable
                ? Icons.cloud_done_outlined
                : Icons.cloud_off_outlined,
            title: status.isReachable
                ? 'API oficial alcancavel'
                : status.isConfigured
                ? 'API oficial configurada, mas indisponivel'
                : 'Uso local sem API remota ativa',
            subtitle: status.message,
          ),
          const SizedBox(height: 14),
          SystemInfoRow(label: 'Endpoint', value: status.endpointLabel),
          SystemInfoRow(
            label: 'Ultima verificacao',
            value: AppFormatters.shortDateTime(status.checkedAt),
          ),
          SystemInfoRow(
            label: 'Tenant remoto',
            value: status.remoteCompanyName ?? 'Nao validado',
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onTestConnection,
            icon: const Icon(Icons.wifi_tethering_rounded),
            label: const Text('Testar conexao'),
          ),
        ],
      ),
    );
  }
}
