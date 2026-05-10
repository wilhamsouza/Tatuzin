import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/owner_providers.dart';
import '../../../core/models/owner_models.dart';
import '../../../core/widgets/owner_async_view.dart';
import '../../../core/widgets/owner_formatters.dart';
import '../../../core/widgets/owner_management_widgets.dart';

class OwnerDevicesPage extends ConsumerWidget {
  const OwnerDevicesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(ownerDevicesProvider);
    return OwnerAsyncView(
      value: devices,
      onRetry: () => ref.invalidate(ownerDevicesProvider),
      builder: (page) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const OwnerPageIntro(
              title: 'Dispositivos conectados',
              subtitle:
                  'Aparelhos e navegadores usados para acessar a empresa.',
              icon: Icons.devices_rounded,
            ),
            const SizedBox(height: 18),
            OwnerSectionCard(
              title: 'Acessos da empresa',
              subtitle:
                  '${page.count}/${page.maxDevices} dispositivos no plano.',
              child: page.items.isEmpty
                  ? const OwnerEmptyState(
                      title: 'Nenhum dispositivo encontrado',
                      message:
                          'Quando um aparelho acessar a empresa, ele aparecerá aqui com nome, tipo, último acesso e status.',
                    )
                  : Column(
                      children: [
                        for (final device in page.items)
                          _DeviceTile(device: device),
                      ],
                    ),
            ),
          ],
        );
      },
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
