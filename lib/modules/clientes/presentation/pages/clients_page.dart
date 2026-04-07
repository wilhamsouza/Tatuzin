import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/providers/app_data_refresh_provider.dart';
import '../../../../app/core/widgets/app_input.dart';
import '../../../../app/core/widgets/app_main_drawer.dart';
import '../../../../app/core/widgets/app_page_header.dart';
import '../../../../app/core/widgets/app_status_badge.dart';
import '../../../../app/routes/route_names.dart';
import '../../domain/entities/client.dart';
import '../providers/client_providers.dart';

class ClientsPage extends ConsumerWidget {
  const ClientsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clientsAsync = ref.watch(clientListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Clientes')),
      drawer: const AppMainDrawer(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await context.pushNamed(AppRouteNames.clientForm);
          if (created == true) {
            ref.invalidate(clientListProvider);
          }
        },
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Novo cliente'),
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: AppPageHeader(
              title: 'Clientes',
              subtitle:
                  'Acompanhe relacionamento, dados de contato e saldo devedor com leitura mais clara.',
              badgeLabel: 'Cadastro',
              badgeIcon: Icons.people_alt_rounded,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: AppInput(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Buscar por nome',
              onChanged: (value) {
                ref.read(clientSearchQueryProvider.notifier).state = value;
              },
            ),
          ),
          Expanded(
            child: clientsAsync.when(
              data: (clients) {
                if (clients.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Nenhum cliente cadastrado ainda.'),
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(clientListProvider);
                    await ref.read(clientListProvider.future);
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                    itemCount: clients.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      return _ClientTile(client: clients[index]);
                    },
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Falha ao carregar clientes: $error'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClientTile extends ConsumerWidget {
  const _ClientTile({required this.client});

  final Client client;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parts = <String>[
      if (client.phone?.trim().isNotEmpty ?? false) client.phone!,
      client.isActive ? 'Ativo' : 'Inativo',
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        client.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (parts.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(parts.join(' • ')),
                      ],
                    ],
                  ),
                ),
                Wrap(
                  spacing: 4,
                  children: [
                    IconButton(
                      tooltip: 'Editar',
                      onPressed: () async {
                        final updated = await context.pushNamed(
                          AppRouteNames.clientForm,
                          extra: client,
                        );
                        if (updated == true) {
                          ref.invalidate(clientListProvider);
                        }
                      },
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      tooltip: 'Excluir',
                      onPressed: () => _delete(context, ref),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _ClientMetric(
                  label: 'Saldo devedor',
                  value: AppFormatters.currencyFromCents(
                    client.debtorBalanceCents,
                  ),
                ),
                _ClientMetric(
                  label: 'Telefone',
                  value: client.phone?.trim().isNotEmpty == true
                      ? client.phone!
                      : 'N\u00e3o informado',
                ),
                AppStatusBadge(
                  label: client.isActive ? 'Ativo' : 'Inativo',
                  tone: client.isActive
                      ? AppStatusTone.success
                      : AppStatusTone.neutral,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Excluir cliente'),
          content: Text('Deseja excluir "${client.name}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Excluir'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await ref.read(clientRepositoryProvider).delete(client.id);
      ref.read(appDataRefreshProvider.notifier).state++;
      ref.invalidate(clientListProvider);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cliente "${client.name}" exclu\u00eddo.')),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('N\u00e3o foi poss\u00edvel excluir o cliente: $error'),
        ),
      );
    }
  }
}

class _ClientMetric extends StatelessWidget {
  const _ClientMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.titleSmall),
        ],
      ),
    );
  }
}
