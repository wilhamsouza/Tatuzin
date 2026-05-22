import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/owner_providers.dart';
import '../../../core/models/owner_models.dart';
import '../../../core/widgets/owner_async_view.dart';
import '../../../core/widgets/owner_formatters.dart';
import '../../../core/widgets/owner_management_widgets.dart';
import '../../../theme/owner_theme_controller.dart';

class OwnerSettingsPage extends ConsumerWidget {
  const OwnerSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final company = ref.watch(ownerCompanyProvider);
    final devices = ref.watch(ownerDevicesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const OwnerPageIntro(
          title: 'Configurações',
          subtitle:
              'Dados da empresa, plano e dispositivos conectados ao Tatuzin.',
          icon: Icons.settings_rounded,
        ),
        const SizedBox(height: 18),
        const _ThemeModeCard(),
        const SizedBox(height: 18),
        OwnerAsyncView(
          value: company,
          onRetry: () => ref.invalidate(ownerCompanyProvider),
          builder: (data) {
            return OwnerSectionCard(
              title: 'Empresa',
              subtitle: 'Informações principais da loja.',
              child: Wrap(
                spacing: 24,
                runSpacing: 14,
                children: [
                  _InfoItem(label: 'Nome', value: data.name),
                  _InfoItem(
                    label: 'Plano',
                    value: ownerPlanLabel(data.license.plan),
                  ),
                  _InfoItem(
                    label: 'Status',
                    value: OwnerFormatters.status(data.license.status),
                  ),
                  _InfoItem(
                    label: 'Próxima cobrança',
                    value: OwnerFormatters.date(data.license.nextPaymentDate),
                  ),
                  _InfoItem(
                    label: 'Funcionários no plano',
                    value: '${data.limits.maxEmployees}',
                  ),
                  _InfoItem(
                    label: 'Dispositivos no plano',
                    value: '${data.limits.maxDevices}',
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 18),
        OwnerAsyncView(
          value: devices,
          onRetry: () => ref.invalidate(ownerDevicesProvider),
          builder: (page) {
            return OwnerSectionCard(
              title: 'Dispositivos conectados',
              subtitle:
                  'Aparelhos e navegadores usados para acessar a empresa.',
              child: page.items.isEmpty
                  ? const OwnerEmptyState(
                      title: 'Nenhum dispositivo encontrado',
                      message:
                          'Quando um aparelho acessar a empresa, ele aparecerá aqui com nome, tipo, último acesso e status.',
                      icon: Icons.devices_rounded,
                    )
                  : Column(
                      children: [
                        for (final device in page.items)
                          _DeviceTile(device: device),
                      ],
                    ),
            );
          },
        ),
        const SizedBox(height: 18),
        const OwnerEmptyState(
          title: 'Painel em modo consulta',
          message:
              'As configurações estão disponíveis para acompanhamento. Alterações serão liberadas em uma próxima etapa.',
          icon: Icons.lock_outline_rounded,
        ),
      ],
    );
  }
}

class _InfoItem extends StatelessWidget {
  const _InfoItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _ThemeModeCard extends ConsumerWidget {
  const _ThemeModeCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(ownerMaterialThemeModeProvider);
    return OwnerSectionCard(
      title: 'Tema',
      subtitle: 'Escolha como o painel deve acompanhar seu ambiente.',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SegmentedButton<ThemeMode>(
          segments: const [
            ButtonSegment(
              value: ThemeMode.system,
              icon: Icon(Icons.brightness_auto_rounded),
              label: Text('Usar tema do sistema'),
            ),
            ButtonSegment(
              value: ThemeMode.light,
              icon: Icon(Icons.light_mode_rounded),
              label: Text('Claro'),
            ),
            ButtonSegment(
              value: ThemeMode.dark,
              icon: Icon(Icons.dark_mode_rounded),
              label: Text('Escuro'),
            ),
          ],
          selected: {mode},
          onSelectionChanged: (selection) {
            ref
                .read(ownerThemeModeControllerProvider.notifier)
                .setThemeMode(selection.single);
          },
        ),
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.device});

  final OwnerDevice device;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.devices_rounded),
      title: Text(_deviceName(device)),
      subtitle: Text(
        '${_deviceType(device)} • Último acesso ${OwnerFormatters.date(device.lastSeenAt)}',
      ),
      trailing: Chip(label: Text(OwnerFormatters.status(device.status))),
    );
  }
}

String _deviceName(OwnerDevice device) {
  final label = device.deviceLabel?.trim();
  final normalized = label?.toLowerCase() ?? '';
  if (normalized.contains('owner web')) {
    return 'Painel da empresa';
  }
  if (normalized.contains('admin web')) {
    return 'Painel administrativo';
  }
  if (label != null && label.isNotEmpty) {
    return label;
  }
  return _deviceType(device);
}

String _deviceType(OwnerDevice device) {
  final source = [
    device.deviceLabel,
    device.platform,
    device.appVersion,
  ].whereType<String>().join(' ').toLowerCase();
  if (source.contains('owner')) {
    return 'Painel da empresa';
  }
  if (source.contains('admin')) {
    return 'Painel administrativo';
  }
  if (source.contains('android')) {
    return 'Aplicativo Android';
  }
  if (source.contains('ios')) {
    return 'Aplicativo iOS';
  }
  if (source.contains('web')) {
    return 'Navegador web';
  }
  return 'Dispositivo conectado';
}
