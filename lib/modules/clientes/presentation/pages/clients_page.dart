import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/providers/app_data_refresh_provider.dart';
import '../../../../app/core/widgets/app_feedback.dart';
import '../../../../app/core/widgets/app_input.dart';
import '../../../../app/core/widgets/app_main_drawer.dart';
import '../../../../app/core/widgets/app_page_header.dart';
import '../../../../app/core/widgets/app_state_card.dart';
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
            padding: EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: AppPageHeader(
              title: 'Consulta de clientes',
              subtitle:
                  'Busque rápido, confira pendências e entre em edição sem ruído.',
              badgeLabel: 'Operação',
              badgeIcon: Icons.people_alt_rounded,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: AppInput(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Buscar cliente por nome ou telefone',
              onChanged: (value) {
                ref.read(clientSearchQueryProvider.notifier).state = value;
              },
            ),
          ),
          Expanded(
            child: clientsAsync.when(
              data: (clients) {
                if (clients.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 92),
                    child: AppStateCard(
                      title: 'Nenhum cliente cadastrado',
                      message:
                          'Cadastre o primeiro cliente para consultar pendências e histórico.',
                      actionLabel: 'Novo cliente',
                      onAction: () async {
                        final created = await context.pushNamed(
                          AppRouteNames.clientForm,
                        );
                        if (created == true) {
                          ref.invalidate(clientListProvider);
                        }
                      },
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(clientListProvider);
                    await ref.read(clientListProvider.future);
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 92),
                    itemCount: clients.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      return _ClientTile(client: clients[index]);
                    },
                  ),
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: AppStateCard(
                  title: 'Carregando clientes',
                  message: 'Preparando a lista para consulta.',
                  tone: AppStateTone.loading,
                  compact: true,
                ),
              ),
              error: (error, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: AppStateCard(
                    title: 'Falha ao carregar clientes',
                    message: 'Verifique a conexão local e tente novamente.',
                    tone: AppStateTone.error,
                    compact: true,
                    actionLabel: 'Tentar novamente',
                    onAction: () => ref.invalidate(clientListProvider),
                  ),
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final parts = <String>[
      client.phone?.trim().isNotEmpty == true ? client.phone! : 'Sem telefone',
      if (!client.isActive) 'Inativo',
    ];
    final hasDebt = client.debtorBalanceCents > 0;
    final initials = client.name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part.substring(0, 1).toUpperCase())
        .join();

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openEditor(context, ref),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: hasDebt
                      ? colorScheme.secondaryContainer.withValues(alpha: 0.82)
                      : colorScheme.primaryContainer.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(
                  initials.isEmpty ? 'C' : initials,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: hasDebt
                        ? colorScheme.onSecondaryContainer
                        : colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      client.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      parts.join(' • '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    hasDebt ? 'Saldo devedor' : 'Sem pendência',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: hasDebt
                          ? colorScheme.error
                          : colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    AppFormatters.currencyFromCents(client.debtorBalanceCents),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: hasDebt
                          ? colorScheme.error
                          : colorScheme.onSurface,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              PopupMenuButton<_ClientAction>(
                tooltip: 'Ações do cliente',
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: _ClientAction.edit,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Editar'),
                    ),
                  ),
                  PopupMenuItem(
                    value: _ClientAction.delete,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.delete_outline),
                      title: Text('Excluir'),
                    ),
                  ),
                ],
                onSelected: (value) async {
                  switch (value) {
                    case _ClientAction.edit:
                      await _openEditor(context, ref);
                      break;
                    case _ClientAction.delete:
                      await _delete(context, ref);
                      break;
                  }
                },
                icon: Icon(
                  Icons.more_vert_rounded,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openEditor(BuildContext context, WidgetRef ref) async {
    final updated = await context.pushNamed(
      AppRouteNames.clientForm,
      extra: client,
    );
    if (updated == true) {
      ref.invalidate(clientListProvider);
    }
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
      AppFeedback.success(context, 'Cliente "${client.name}" excluído.');
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      AppFeedback.error(context, 'Não foi possível excluir o cliente: $error');
    }
  }
}

enum _ClientAction { edit, delete }
