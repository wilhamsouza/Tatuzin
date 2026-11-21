import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/auth/owner_providers.dart';
import '../../../core/widgets/owner_async_view.dart';
import '../../../core/widgets/owner_formatters.dart';
import '../data/owner_inventory_api.dart';

class InventoryResource extends ConsumerWidget {
  const InventoryResource({
    super.key,
    required this.resource,
    required this.builder,
  });
  final String resource;
  final Widget Function(InventoryMap data) builder;
  @override
  Widget build(BuildContext context, WidgetRef ref) => OwnerAsyncView(
    value: ref.watch(ownerInventoryResourceProvider(resource)),
    onRetry: () => ref.invalidate(ownerInventoryResourceProvider(resource)),
    builder: builder,
  );
}

class InventorySection extends StatelessWidget {
  const InventorySection({super.key, required this.child, this.title});
  final Widget child;
  final String? title;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Text(
              title!,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
          ],
          child,
        ],
      ),
    ),
  );
}

class InventoryEmpty extends StatelessWidget {
  const InventoryEmpty(this.message, {super.key, this.action});
  final String message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 20),
    child: Column(
      children: [
        Icon(
          Icons.inventory_2_outlined,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        if (action != null) ...[const SizedBox(height: 12), action!],
      ],
    ),
  );
}

class InventoryPager extends StatelessWidget {
  const InventoryPager({
    super.key,
    required this.data,
    required this.page,
    required this.onPage,
  });
  final InventoryMap data;
  final int page;
  final ValueChanged<int> onPage;
  @override
  Widget build(BuildContext context) {
    final p = inventoryMap(data['pagination']);
    final total = inventoryInt(p['total'] ?? data['total']);
    final pageSize = inventoryInt(p['pageSize']) == 0
        ? 20
        : inventoryInt(p['pageSize']);
    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      children: [
        Text('$total registros'),
        IconButton(
          tooltip: 'Página anterior',
          onPressed: page > 1 ? () => onPage(page - 1) : null,
          icon: const Icon(Icons.chevron_left),
        ),
        Text('Página $page'),
        IconButton(
          tooltip: 'Próxima página',
          onPressed: page * pageSize < total ? () => onPage(page + 1) : null,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}

String inventoryStatus(Object? value) =>
    const {
      'OPEN': 'Aberta',
      'COUNTING': 'Em contagem',
      'REVIEWED': 'Revisada',
      'APPLIED': 'Aplicada',
      'CANCELED': 'Cancelada',
      'active': 'Disponível',
      'belowMinimum': 'Abaixo do mínimo',
      'zeroed': 'Sem estoque',
      'inactive': 'Inativo',
    }[value] ??
    inventoryText(value);
String inventoryQuantity(Object? value, String unit) =>
    '${OwnerFormatters.quantityFromMil(inventoryInt(value))} $unit';
Uri inventoryUri(BuildContext context) => GoRouterState.of(context).uri;
void inventoryNavigateFilter(
  BuildContext context,
  Map<String, String?> changes,
) {
  final uri = inventoryUri(context);
  final q = Map<String, String>.from(uri.queryParameters);
  for (final entry in changes.entries) {
    if (entry.value == null || entry.value!.isEmpty) {
      q.remove(entry.key);
    } else {
      q[entry.key] = entry.value!;
    }
  }
  context.go(uri.replace(queryParameters: q.isEmpty ? null : q).toString());
}

Future<bool> confirmInventory(
  BuildContext context, {
  required String title,
  required String message,
  String confirm = 'Confirmar',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(message)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: Text(confirm),
          ),
        ],
      ),
    ) ??
    false;
void inventoryRefresh(WidgetRef ref) {
  ref.invalidate(ownerInventoryResourceProvider);
  ref.read(ownerRefreshTickProvider.notifier).state++;
}
