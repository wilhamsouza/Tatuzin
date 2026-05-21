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
    final sync = ref.watch(ownerSyncStatusProvider);
    final devices = ref.watch(ownerDevicesProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OwnerPageIntro(
          title: 'Nuvem e sincronizacao',
          subtitle: 'Acompanhe se os dados da empresa estao chegando na nuvem.',
          icon: Icons.cloud_sync_rounded,
          trailing: FilledButton.icon(
            onPressed: () {
              ref.invalidate(ownerSyncStatusProvider);
              ref.invalidate(ownerDevicesProvider);
              ref.read(ownerRefreshTickProvider.notifier).state++;
            },
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Atualizar status'),
          ),
        ),
        const SizedBox(height: 18),
        OwnerAsyncView(
          value: sync,
          onRetry: () => ref.invalidate(ownerSyncStatusProvider),
          builder: (status) => _SyncContent(status: status),
        ),
        const SizedBox(height: 18),
        OwnerSectionCard(
          title: 'Dispositivos e sessoes',
          subtitle: 'Aparelhos e navegadores usados na empresa.',
          child: OwnerAsyncView(
            value: devices,
            onRetry: () => ref.invalidate(ownerDevicesProvider),
            builder: (page) {
              if (page.items.isEmpty) {
                return const OwnerEmptyState(
                  title: 'Nenhum dispositivo encontrado',
                  message:
                      'Quando um aparelho acessar a empresa, ele aparecera aqui.',
                );
              }
              return Column(
                children: [
                  for (final device in page.items) _DeviceTile(device: device),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SyncContent extends StatelessWidget {
  const _SyncContent({required this.status});

  final OwnerSyncStatus status;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            OwnerMetricCard(
              title: 'Status da nuvem',
              value: status.message,
              detail: status.online ? 'Conectado agora.' : 'Sem sinal recente.',
              icon: _healthIcon(status.health),
              isAvailable: status.syncEnabled,
            ),
            OwnerMetricCard(
              title: 'Ultima sincronizacao',
              value: OwnerFormatters.date(status.lastSyncAt),
              detail: 'Ultimo dado processado pela nuvem.',
              icon: Icons.schedule_rounded,
              isAvailable: status.lastSyncAt != null,
            ),
            OwnerMetricCard(
              title: 'Pendencias',
              value: '${status.pendingEvents}',
              detail: status.pendingEvents == 0
                  ? 'Tudo enviado.'
                  : 'Existem dados aguardando envio.',
              icon: Icons.outbox_rounded,
              isAvailable: true,
            ),
            OwnerMetricCard(
              title: 'Falhas recentes',
              value: '${status.recentErrors.length + status.openConflicts}',
              detail: status.openConflicts == 0
                  ? 'Sem conflitos abertos.'
                  : '${status.openConflicts} conflitos para revisar.',
              icon: Icons.warning_amber_rounded,
              isAvailable: true,
            ),
          ],
        ),
        const SizedBox(height: 18),
        OwnerSectionCard(
          title: 'Erros recentes',
          subtitle: 'Linguagem resumida, sem payload tecnico.',
          child: status.recentErrors.isEmpty
              ? const OwnerEmptyState(
                  title: 'Nenhuma falha recente',
                  message: 'Tudo sincronizado ou aguardando envio normal.',
                  icon: Icons.check_circle_outline_rounded,
                )
              : Column(
                  children: [
                    for (final error in status.recentErrors)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.warning_amber_rounded),
                        title: Text(error.area),
                        subtitle: Text(error.message),
                        trailing: Text(OwnerFormatters.date(error.updatedAt)),
                      ),
                  ],
                ),
        ),
      ],
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
        '${_deviceType(device)} - Ultimo acesso ${OwnerFormatters.date(device.lastSeenAt)}',
      ),
      trailing: Chip(label: Text(OwnerFormatters.status(device.status))),
    );
  }
}

IconData _healthIcon(String health) {
  switch (health) {
    case 'attention':
      return Icons.warning_amber_rounded;
    case 'pending':
      return Icons.outbox_rounded;
    default:
      return Icons.cloud_done_outlined;
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
