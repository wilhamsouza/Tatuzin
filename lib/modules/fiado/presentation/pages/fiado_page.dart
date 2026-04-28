import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/widgets/app_main_drawer.dart';
import '../../../../app/core/widgets/app_state_card.dart';
import '../../../../app/core/widgets/app_status_badge.dart';
import '../../../../app/routes/route_names.dart';
import '../../domain/entities/fiado_account.dart';
import '../providers/fiado_providers.dart';

class FiadoPage extends ConsumerWidget {
  const FiadoPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fiadoAsync = ref.watch(fiadoListProvider);
    final selectedStatus = ref.watch(fiadoStatusFilterProvider);
    final overdueOnly = ref.watch(fiadoOverdueOnlyProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Fiado e contas a prazo')),
      drawer: const AppMainDrawer(),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Buscar por cliente ou cupom',
              ),
              onChanged: (value) {
                ref.read(fiadoSearchQueryProvider.notifier).state = value;
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    initialValue: selectedStatus,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: const [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Todos'),
                      ),
                      DropdownMenuItem<String?>(
                        value: 'pendente',
                        child: Text('Pendente'),
                      ),
                      DropdownMenuItem<String?>(
                        value: 'parcial',
                        child: Text('Parcial'),
                      ),
                      DropdownMenuItem<String?>(
                        value: 'quitado',
                        child: Text('Quitado'),
                      ),
                      DropdownMenuItem<String?>(
                        value: 'cancelado',
                        child: Text('Cancelado'),
                      ),
                    ],
                    onChanged: (value) {
                      ref.read(fiadoStatusFilterProvider.notifier).state =
                          value;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Só vencidos'),
                    value: overdueOnly,
                    onChanged: (value) {
                      ref.read(fiadoOverdueOnlyProvider.notifier).state = value;
                    },
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: fiadoAsync.when(
              data: (accounts) {
                if (accounts.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Nenhuma nota encontrada para os filtros.'),
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(fiadoListProvider);
                    await ref.read(fiadoListProvider.future);
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    itemCount: accounts.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      return _FiadoTile(account: accounts[index]);
                    },
                  ),
                );
              },
              loading: () => const Center(
                child: AppStateCard(
                  title: 'Carregando fiado',
                  message: 'Buscando notas locais do PDV.',
                  tone: AppStateTone.loading,
                  compact: true,
                ),
              ),
              error: (error, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: AppStateCard(
                    title: 'Falha ao carregar notas',
                    message: '$error',
                    tone: AppStateTone.error,
                    compact: true,
                    actionLabel: 'Tentar novamente',
                    onAction: () => ref.invalidate(fiadoListProvider),
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

class _FiadoTile extends StatelessWidget {
  const _FiadoTile({required this.account});

  final FiadoAccount account;

  @override
  Widget build(BuildContext context) {
    final isOverdue =
        !account.isCancelled &&
        !account.isSettled &&
        account.dueDate.isBefore(DateTime.now());

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.pushNamed(
          AppRouteNames.fiadoDetail,
          pathParameters: {'fiadoId': '${account.id}'},
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      account.clientName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Text(
                    AppFormatters.currencyFromCents(account.openCents),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  AppStatusBadge(
                    label: 'Cupom ${account.receiptNumber}',
                    tone: AppStatusTone.neutral,
                  ),
                  AppStatusBadge(
                    label: _statusLabel(account),
                    tone: _toneForStatus(account),
                  ),
                  AppStatusBadge(
                    label:
                        'Vence em ${AppFormatters.shortDate(account.dueDate)}',
                    tone: isOverdue ? AppStatusTone.danger : AppStatusTone.info,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Saldo em aberto: ${AppFormatters.currencyFromCents(account.openCents)}',
              ),
              const SizedBox(height: 4),
              Text(
                'Valor original: ${AppFormatters.currencyFromCents(account.originalCents)}',
              ),
            ],
          ),
        ),
      ),
    );
  }

  AppStatusTone _toneForStatus(FiadoAccount account) {
    if (account.isCancelled) {
      return AppStatusTone.danger;
    }
    if (account.isSettled) {
      return AppStatusTone.success;
    }
    final isOverdue =
        account.dueDate.isBefore(DateTime.now()) && !account.isCancelled;
    if (isOverdue) {
      return AppStatusTone.warning;
    }
    return account.status == 'parcial'
        ? AppStatusTone.info
        : AppStatusTone.neutral;
  }

  String _statusLabel(FiadoAccount account) {
    switch (account.status) {
      case 'pendente':
        return 'Pendente';
      case 'parcial':
        return 'Parcial';
      case 'quitado':
        return 'Quitado';
      case 'cancelado':
        return 'Cancelado';
      default:
        return account.status;
    }
  }
}
