import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/owner_providers.dart';
import '../../../core/widgets/owner_async_view.dart';
import '../../../core/widgets/owner_formatters.dart';

class OwnerDevicesPage extends ConsumerWidget {
  const OwnerDevicesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(ownerDevicesProvider);
    return OwnerAsyncView(
      value: devices,
      onRetry: () => ref.invalidate(ownerDevicesProvider),
      builder: (page) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Dispositivos',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text('${page.count}/${page.maxDevices} dispositivos no plano.'),
                const SizedBox(height: 16),
                if (page.items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('Nenhum dispositivo encontrado.'),
                  )
                else
                  for (final device in page.items)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.devices_rounded),
                      title: Text(device.deviceLabel ?? 'Dispositivo'),
                      subtitle: Text(
                        [
                          if (device.platform != null) device.platform,
                          if (device.appVersion != null) device.appVersion,
                          device.maskedClientInstanceId,
                        ].whereType<String>().join(' • '),
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(OwnerFormatters.status(device.status)),
                          Text(
                            OwnerFormatters.date(device.lastSeenAt),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
        );
      },
    );
  }
}
