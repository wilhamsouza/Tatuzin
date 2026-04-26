import 'package:flutter/material.dart';

import '../../../../app/core/config/app_data_mode.dart';
import '../../../../app/core/config/app_environment.dart';
import '../../../../app/core/network/endpoint_config.dart';
import '../../../../app/core/session/session_provider.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import '../../../../app/core/widgets/app_status_badge.dart';
import 'system_support_widgets.dart';

class SystemEnvironmentSection extends StatelessWidget {
  const SystemEnvironmentSection({
    required this.environment,
    required this.guard,
    required this.canEditEndpoint,
    required this.onDataModeChanged,
    this.endpointController,
    this.endpointFocusNode,
    this.onSaveEndpoint,
    this.onUseDefaultEndpoint,
    super.key,
  });

  final AppEnvironment environment;
  final SessionGuardSnapshot guard;
  final bool canEditEndpoint;
  final ValueChanged<AppDataMode> onDataModeChanged;
  final TextEditingController? endpointController;
  final FocusNode? endpointFocusNode;
  final VoidCallback? onSaveEndpoint;
  final VoidCallback? onUseDefaultEndpoint;

  bool get _showsTechnicalEndpointEditor =>
      canEditEndpoint &&
      endpointController != null &&
      endpointFocusNode != null &&
      onSaveEndpoint != null &&
      onUseDefaultEndpoint != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final defaultEndpointBaseUrl = EndpointConfig.remoteDefault().baseUrl!;
    final currentEndpointLabel = environment.isLocalOnly
        ? 'Modo local ativo'
        : environment.endpointConfig.summaryLabel;

    return AppSectionCard(
      title: 'Modo de dados e endpoint',
      subtitle: _showsTechnicalEndpointEditor
          ? 'Controle central do ambiente com override tecnico apenas em debug.'
          : 'Ambiente do app com endpoint oficial nativo; o operador final nao configura API manualmente.',
      trailing: AppStatusBadge(
        label: environment.isLocalOnly ? 'SQLite local' : 'API oficial nativa',
        tone: AppStatusTone.success,
        icon: environment.isLocalOnly
            ? Icons.storage_rounded
            : Icons.verified_outlined,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<AppDataMode>(
            segments: AppDataMode.values
                .map(
                  (mode) => ButtonSegment<AppDataMode>(
                    value: mode,
                    label: Text(mode.label),
                  ),
                )
                .toList(),
            selected: <AppDataMode>{environment.dataMode},
            showSelectedIcon: false,
            onSelectionChanged: (selection) =>
                onDataModeChanged(selection.first),
          ),
          const SizedBox(height: 16),
          if (_showsTechnicalEndpointEditor) ...[
            Text(
              'Override tecnico de endpoint (debug)',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Use apenas em desenvolvimento interno. Builds normais de producao ignoram override salvo e usam a API oficial.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: endpointController,
              focusNode: endpointFocusNode,
              decoration: InputDecoration(
                labelText: 'Base URL tecnica do backend',
                hintText: defaultEndpointBaseUrl,
                prefixIcon: const Icon(Icons.link_rounded),
              ),
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: onSaveEndpoint,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Salvar endpoint tecnico'),
                ),
                OutlinedButton.icon(
                  onPressed: onUseDefaultEndpoint,
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: const Text('Usar endpoint tecnico padrao'),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ] else ...[
            SystemStateTile(
              icon: environment.isLocalOnly
                  ? Icons.offline_pin_rounded
                  : Icons.cloud_done_outlined,
              title: environment.isLocalOnly
                  ? 'Modo local preservado'
                  : 'Endpoint oficial travado no build',
              subtitle: environment.isLocalOnly
                  ? 'O SQLite continua como base operacional. Quando recursos remotos forem usados, o app volta para a API oficial do Tatuzin sem depender de configuracao manual.'
                  : 'Este build usa nativamente ${environment.endpointConfig.summaryLabel}. Overrides legados e digitados pelo operador ficam bloqueados.',
            ),
            const SizedBox(height: 16),
          ],
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              const SystemModeChip(
                label: 'SQLite local ativo',
                icon: Icons.dns_rounded,
              ),
              SystemModeChip(
                label: currentEndpointLabel,
                icon: Icons.cloud_queue_rounded,
              ),
              SystemModeChip(
                label: guard.allowRemoteRoutes
                    ? 'Remoto liberado'
                    : 'Remoto em espera',
                icon: Icons.sync_alt_rounded,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            environment.dataMode.description,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 14),
          SystemInfoRow(label: 'Ambiente', value: environment.name),
          const SystemInfoRow(
            label: 'API oficial',
            value: EndpointConfig.productionApiUrl,
          ),
          SystemInfoRow(label: 'Endpoint em uso', value: currentEndpointLabel),
          SystemInfoRow(
            label: 'Auth remota',
            value: environment.authEnabled
                ? 'Disponivel com a API oficial do Tatuzin'
                : 'Desativada no modo local',
          ),
          SystemInfoRow(
            label: 'Sync remota',
            value: environment.remoteSyncEnabled
                ? 'Preparado para fase futura'
                : 'Ainda isolado do operacional',
          ),
        ],
      ),
    );
  }
}
