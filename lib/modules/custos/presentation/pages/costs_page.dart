import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/providers/app_data_refresh_provider.dart';
import '../../../../app/core/utils/money_parser.dart';
import '../../../../app/core/widgets/app_button.dart';
import '../../../../app/core/widgets/app_card.dart';
import '../../../../app/core/widgets/app_input.dart';
import '../../../../app/core/widgets/app_main_drawer.dart';
import '../../../../app/core/widgets/app_status_badge.dart';
import '../../../vendas/domain/entities/sale_enums.dart';
import '../../domain/entities/cost_entry.dart';
import '../../domain/entities/cost_overview.dart';
import '../../domain/entities/cost_status.dart';
import '../../domain/entities/cost_type.dart';
import '../../domain/repositories/cost_repository.dart';
import '../providers/cost_providers.dart';

enum _CostViewFilter { open, paid, recurring }

enum _CostTypeFilter { all, fixed, variable }

extension _CostViewFilterX on _CostViewFilter {
  String get label {
    switch (this) {
      case _CostViewFilter.open:
        return 'Em aberto';
      case _CostViewFilter.paid:
        return 'Pagos';
      case _CostViewFilter.recurring:
        return 'Recorrentes';
    }
  }
}

extension _CostTypeFilterX on _CostTypeFilter {
  String get label {
    switch (this) {
      case _CostTypeFilter.all:
        return 'Todos';
      case _CostTypeFilter.fixed:
        return 'Fixos';
      case _CostTypeFilter.variable:
        return 'Variaveis';
    }
  }

  CostType? get costType {
    switch (this) {
      case _CostTypeFilter.fixed:
        return CostType.fixed;
      case _CostTypeFilter.variable:
        return CostType.variable;
      case _CostTypeFilter.all:
        return null;
    }
  }
}

class _CostBucketConfig {
  const _CostBucketConfig({
    required this.title,
    required this.viewFilter,
    required this.typeFilter,
    this.overdueOnly = false,
  });

  final String title;
  final _CostViewFilter viewFilter;
  final _CostTypeFilter typeFilter;
  final bool overdueOnly;
}

class CostsPage extends ConsumerStatefulWidget {
  const CostsPage({super.key});

  @override
  ConsumerState<CostsPage> createState() => _CostsPageState();
}

class _CostsPageState extends ConsumerState<CostsPage> {
  _CostViewFilter _viewFilter = _CostViewFilter.open;
  _CostTypeFilter _typeFilter = _CostTypeFilter.all;

  @override
  Widget build(BuildContext context) {
    ref.watch(appDataRefreshProvider);
    final overviewAsync = ref.watch(costOverviewProvider);
    final actionState = ref.watch(costActionControllerProvider);
    final listFuture = _queryCosts(
      ref,
      viewFilter: _viewFilter,
      typeFilter: _typeFilter,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Custos')),
      drawer: const AppMainDrawer(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: actionState.isLoading
            ? null
            : () => _startNewCostFlow(
                context,
                ref,
                suggestedType: _typeFilter.costType,
              ),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Novo custo'),
      ),
      body: RefreshIndicator(
        onRefresh: () => _refreshCosts(ref),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
          children: [
            _FilterSection(
              selectedView: _viewFilter,
              selectedType: _typeFilter,
              onViewChanged: (value) {
                setState(() {
                  _viewFilter = value;
                });
              },
              onTypeChanged: (value) {
                setState(() {
                  _typeFilter = value;
                });
              },
            ),
            const SizedBox(height: 12),
            overviewAsync.when(
              data: (overview) => _SummaryGrid(
                overview: overview,
                onOpenBucket: (config) => _openBucketPage(context, config),
              ),
              loading: () => const _StateCard(
                icon: Icons.query_stats_rounded,
                title: 'Carregando resumos',
                subtitle: 'Buscando os indicadores principais de custos.',
                compact: true,
                loading: true,
              ),
              error: (error, _) => _StateCard(
                icon: Icons.error_outline_rounded,
                title: 'Nao foi possivel carregar os resumos',
                subtitle: error.toString(),
                compact: true,
                action: AppButton.secondary(
                  label: 'Atualizar',
                  icon: Icons.refresh_rounded,
                  compact: true,
                  onPressed: () => _refreshCosts(ref),
                ),
              ),
            ),
            const SizedBox(height: 14),
            _SectionHeader(
              title: _mainSectionTitle(_viewFilter, _typeFilter),
              subtitle: _mainSectionSubtitle(_viewFilter, _typeFilter),
            ),
            const SizedBox(height: 10),
            FutureBuilder<List<CostEntry>>(
              future: listFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const _StateCard(
                    icon: Icons.hourglass_top_rounded,
                    title: 'Carregando custos',
                    subtitle: 'Montando a lista principal do modulo.',
                    compact: true,
                    loading: true,
                  );
                }

                if (snapshot.hasError) {
                  return _StateCard(
                    icon: Icons.error_outline_rounded,
                    title: 'Nao foi possivel listar os custos',
                    subtitle: snapshot.error.toString(),
                    compact: true,
                    action: AppButton.secondary(
                      label: 'Atualizar',
                      icon: Icons.refresh_rounded,
                      compact: true,
                      onPressed: () => _refreshCosts(ref),
                    ),
                  );
                }

                final items = snapshot.data ?? const <CostEntry>[];
                if (items.isEmpty) {
                  return _StateCard(
                    icon: Icons.inbox_outlined,
                    title: 'Nenhum custo nesta visao',
                    subtitle: _emptyMessageFor(_viewFilter, _typeFilter),
                    compact: true,
                  );
                }

                return Column(
                  children: [
                    for (final cost in items) ...[
                      _CostListItem(
                        cost: cost,
                        onOpenDetail: () =>
                            _showCostDetailSheet(context, ref, cost.id),
                        onMarkPaid: cost.isPending
                            ? () => _showMarkPaidSheet(context, ref, cost)
                            : null,
                        onEdit: cost.isPending
                            ? () => _showCostFormSheet(
                                context,
                                ref,
                                defaultType: cost.type,
                                initialCost: cost,
                              )
                            : null,
                        onCancel: cost.isPending
                            ? () => _showCancelCostSheet(context, ref, cost)
                            : null,
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openBucketPage(BuildContext context, _CostBucketConfig config) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => _CostBucketPage(config: config)),
    );
  }
}

class _FilterSection extends StatelessWidget {
  const _FilterSection({
    required this.selectedView,
    required this.selectedType,
    required this.onViewChanged,
    required this.onTypeChanged,
  });

  final _CostViewFilter selectedView;
  final _CostTypeFilter selectedType;
  final ValueChanged<_CostViewFilter> onViewChanged;
  final ValueChanged<_CostTypeFilter> onTypeChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final filter in _CostViewFilter.values)
              ChoiceChip(
                label: Text(filter.label),
                selected: selectedView == filter,
                onSelected: (_) => onViewChanged(filter),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final filter in _CostTypeFilter.values)
              ChoiceChip(
                label: Text(filter.label),
                selected: selectedType == filter,
                onSelected: (_) => onTypeChanged(filter),
              ),
          ],
        ),
      ],
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.overview, required this.onOpenBucket});

  final CostOverview overview;
  final ValueChanged<_CostBucketConfig> onOpenBucket;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _SummaryCardData(
        title: 'Fixos em aberto',
        value: AppFormatters.currencyFromCents(overview.pendingFixedCents),
        supporting: '${overview.openFixedCount} custo(s)',
        accentColor: Theme.of(context).colorScheme.primary,
        icon: Icons.event_repeat_rounded,
        onTap: () => onOpenBucket(
          const _CostBucketConfig(
            title: 'Fixos em aberto',
            viewFilter: _CostViewFilter.open,
            typeFilter: _CostTypeFilter.fixed,
          ),
        ),
      ),
      _SummaryCardData(
        title: 'Variaveis em aberto',
        value: AppFormatters.currencyFromCents(overview.pendingVariableCents),
        supporting: '${overview.openVariableCount} custo(s)',
        accentColor: const Color(0xFFF97316),
        icon: Icons.payments_outlined,
        onTap: () => onOpenBucket(
          const _CostBucketConfig(
            title: 'Variaveis em aberto',
            viewFilter: _CostViewFilter.open,
            typeFilter: _CostTypeFilter.variable,
          ),
        ),
      ),
      _SummaryCardData(
        title: 'Fixos vencidos',
        value: AppFormatters.currencyFromCents(overview.overdueFixedCents),
        supporting: 'Abrir lista filtrada',
        accentColor: Theme.of(context).colorScheme.error,
        icon: Icons.warning_amber_rounded,
        onTap: () => onOpenBucket(
          const _CostBucketConfig(
            title: 'Fixos vencidos',
            viewFilter: _CostViewFilter.open,
            typeFilter: _CostTypeFilter.fixed,
            overdueOnly: true,
          ),
        ),
      ),
      _SummaryCardData(
        title: 'Variaveis vencidos',
        value: AppFormatters.currencyFromCents(overview.overdueVariableCents),
        supporting: 'Abrir lista filtrada',
        accentColor: Theme.of(context).colorScheme.error,
        icon: Icons.warning_amber_rounded,
        onTap: () => onOpenBucket(
          const _CostBucketConfig(
            title: 'Variaveis vencidos',
            viewFilter: _CostViewFilter.open,
            typeFilter: _CostTypeFilter.variable,
            overdueOnly: true,
          ),
        ),
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.32,
      ),
      itemCount: cards.length,
      itemBuilder: (context, index) => _SummaryCard(data: cards[index]),
    );
  }
}

class _SummaryCardData {
  const _SummaryCardData({
    required this.title,
    required this.value,
    required this.supporting,
    required this.accentColor,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String value;
  final String supporting;
  final Color accentColor;
  final IconData icon;
  final VoidCallback onTap;
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.data});

  final _SummaryCardData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      onTap: data.onTap,
      borderRadius: 18,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: data.accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(data.icon, color: data.accentColor, size: 18),
            ),
          ),
          const Spacer(),
          Text(
            data.title,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            data.value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(data.supporting, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _CostListItem extends StatelessWidget {
  const _CostListItem({
    required this.cost,
    required this.onOpenDetail,
    this.onMarkPaid,
    this.onEdit,
    this.onCancel,
  });

  final CostEntry cost;
  final VoidCallback onOpenDetail;
  final VoidCallback? onMarkPaid;
  final VoidCallback? onEdit;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final badges = <Widget>[
      _statusBadge(cost),
      AppStatusBadge(
        label: cost.type.label,
        tone: AppStatusTone.info,
        icon: cost.type == CostType.fixed
            ? Icons.event_repeat_rounded
            : Icons.payments_outlined,
      ),
    ];
    if ((cost.category ?? '').isNotEmpty) {
      badges.add(
        AppStatusBadge(label: cost.category!, tone: AppStatusTone.neutral),
      );
    }
    if (cost.isRecurring) {
      badges.add(
        const AppStatusBadge(
          label: 'Recorrente',
          tone: AppStatusTone.success,
          icon: Icons.autorenew_rounded,
        ),
      );
    }

    return AppCard(
      onTap: onOpenDetail,
      borderRadius: 18,
      padding: const EdgeInsets.all(14),
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
                      cost.description,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _metaLine(cost),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Ref. ${AppFormatters.shortDate(cost.referenceDate)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                AppFormatters.currencyFromCents(cost.amountCents),
                textAlign: TextAlign.end,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: badges),
          const SizedBox(height: 10),
          Row(
            children: [
              if (onMarkPaid != null)
                TextButton.icon(
                  onPressed: onMarkPaid,
                  icon: const Icon(
                    Icons.check_circle_outline_rounded,
                    size: 18,
                  ),
                  label: const Text('Marcar pago'),
                )
              else
                TextButton.icon(
                  onPressed: onOpenDetail,
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('Ver detalhes'),
                ),
              const Spacer(),
              PopupMenuButton<_CostItemAction>(
                onSelected: (action) {
                  switch (action) {
                    case _CostItemAction.detail:
                      onOpenDetail();
                      break;
                    case _CostItemAction.pay:
                      onMarkPaid?.call();
                      break;
                    case _CostItemAction.edit:
                      onEdit?.call();
                      break;
                    case _CostItemAction.cancel:
                      onCancel?.call();
                      break;
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: _CostItemAction.detail,
                    child: Text('Ver detalhes'),
                  ),
                  if (onMarkPaid != null)
                    const PopupMenuItem(
                      value: _CostItemAction.pay,
                      child: Text('Marcar como pago'),
                    ),
                  if (onEdit != null)
                    const PopupMenuItem(
                      value: _CostItemAction.edit,
                      child: Text('Editar'),
                    ),
                  if (onCancel != null)
                    const PopupMenuItem(
                      value: _CostItemAction.cancel,
                      child: Text('Cancelar'),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _CostItemAction { detail, pay, edit, cancel }

class _CostBucketPage extends ConsumerWidget {
  const _CostBucketPage({required this.config});

  final _CostBucketConfig config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(appDataRefreshProvider);
    final future = _queryCosts(
      ref,
      viewFilter: config.viewFilter,
      typeFilter: config.typeFilter,
      overdueOnly: config.overdueOnly,
    );

    return Scaffold(
      appBar: AppBar(title: Text(config.title)),
      body: RefreshIndicator(
        onRefresh: () => _refreshCosts(ref),
        child: FutureBuilder<List<CostEntry>>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: const [
                  _StateCard(
                    icon: Icons.hourglass_top_rounded,
                    title: 'Carregando lista filtrada',
                    subtitle: 'Buscando os custos dessa visao.',
                    loading: true,
                  ),
                ],
              );
            }

            if (snapshot.hasError) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _StateCard(
                    icon: Icons.error_outline_rounded,
                    title: 'Nao foi possivel abrir esta visao',
                    subtitle: snapshot.error.toString(),
                    action: AppButton.secondary(
                      label: 'Atualizar',
                      icon: Icons.refresh_rounded,
                      compact: true,
                      onPressed: () => _refreshCosts(ref),
                    ),
                  ),
                ],
              );
            }

            final items = snapshot.data ?? const <CostEntry>[];
            final total = items.fold<int>(
              0,
              (sum, item) => sum + item.amountCents,
            );

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                AppCard(
                  borderRadius: 18,
                  padding: const EdgeInsets.all(16),
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  child: Row(
                    children: [
                      Expanded(
                        child: _CompactMetric(
                          label: 'Total',
                          value: AppFormatters.currencyFromCents(total),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _CompactMetric(
                          label: 'Quantidade',
                          value: '${items.length}',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (items.isEmpty)
                  const _StateCard(
                    icon: Icons.inbox_outlined,
                    title: 'Nenhum custo nesta visao',
                    subtitle: 'Nao ha itens para este resumo no momento.',
                    compact: true,
                  )
                else ...[
                  for (final cost in items) ...[
                    _CostListItem(
                      cost: cost,
                      onOpenDetail: () =>
                          _showCostDetailSheet(context, ref, cost.id),
                      onMarkPaid: cost.isPending
                          ? () => _showMarkPaidSheet(context, ref, cost)
                          : null,
                      onEdit: cost.isPending
                          ? () => _showCostFormSheet(
                              context,
                              ref,
                              defaultType: cost.type,
                              initialCost: cost,
                            )
                          : null,
                      onCancel: cost.isPending
                          ? () => _showCancelCostSheet(context, ref, cost)
                          : null,
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CompactMetric extends StatelessWidget {
  const _CompactMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
      ],
    );
  }
}

class _CostDetailSheet extends ConsumerWidget {
  const _CostDetailSheet({required this.costId});

  final int costId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(costDetailProvider(costId));

    return detailAsync.when(
      data: (cost) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Text(
            cost.description,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _statusBadge(cost),
              AppStatusBadge(
                label: cost.type.label,
                tone: AppStatusTone.info,
                icon: cost.type == CostType.fixed
                    ? Icons.event_repeat_rounded
                    : Icons.payments_outlined,
              ),
              if (cost.isRecurring)
                const AppStatusBadge(
                  label: 'Recorrente',
                  tone: AppStatusTone.success,
                  icon: Icons.autorenew_rounded,
                ),
            ],
          ),
          const SizedBox(height: 12),
          AppCard(
            borderRadius: 18,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Valor do custo',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  AppFormatters.currencyFromCents(cost.amountCents),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Referencia em ${AppFormatters.shortDate(cost.referenceDate)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _DetailDataGrid(cost: cost),
          if ((cost.notes ?? '').isNotEmpty) ...[
            const SizedBox(height: 12),
            AppCard(
              borderRadius: 18,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Observacoes',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(cost.notes!),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (cost.isPending) ...[
            AppButton.primary(
              label: 'Marcar como pago',
              icon: Icons.check_circle_rounded,
              expand: true,
              onPressed: () {
                Navigator.of(context).pop();
                _showMarkPaidSheet(context, ref, cost);
              },
            ),
            const SizedBox(height: 10),
            AppButton.secondary(
              label: 'Editar custo',
              icon: Icons.edit_rounded,
              expand: true,
              onPressed: () {
                Navigator.of(context).pop();
                _showCostFormSheet(
                  context,
                  ref,
                  defaultType: cost.type,
                  initialCost: cost,
                );
              },
            ),
            const SizedBox(height: 10),
            AppButton.secondary(
              label: 'Cancelar custo',
              icon: Icons.cancel_outlined,
              expand: true,
              onPressed: () {
                Navigator.of(context).pop();
                _showCancelCostSheet(context, ref, cost);
              },
            ),
          ],
        ],
      ),
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: _StateCard(
          icon: Icons.receipt_long_rounded,
          title: 'Abrindo detalhes do custo',
          subtitle: 'Carregando o registro selecionado.',
          compact: true,
          loading: true,
        ),
      ),
      error: (error, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: _StateCard(
          icon: Icons.error_outline_rounded,
          title: 'Nao foi possivel abrir este custo',
          subtitle: error.toString(),
          compact: true,
          action: AppButton.secondary(
            label: 'Tentar novamente',
            icon: Icons.refresh_rounded,
            onPressed: () => ref.invalidate(costDetailProvider(costId)),
          ),
        ),
      ),
    );
  }
}

class _DetailDataGrid extends StatelessWidget {
  const _DetailDataGrid({required this.cost});

  final CostEntry cost;

  @override
  Widget build(BuildContext context) {
    final items = <_DetailDataItem>[
      _DetailDataItem(
        label: 'Tipo',
        value: cost.type == CostType.fixed ? 'Fixo' : 'Variavel',
      ),
      _DetailDataItem(
        label: 'Categoria',
        value: cost.category ?? 'Nao informada',
      ),
      _DetailDataItem(
        label: 'Referencia',
        value: AppFormatters.shortDate(cost.referenceDate),
      ),
      _DetailDataItem(
        label: 'Pagamento',
        value: cost.paymentMethod?.label ?? 'Ainda nao pago',
      ),
      _DetailDataItem(
        label: 'Criado em',
        value: AppFormatters.shortDateTime(cost.createdAt),
      ),
      _DetailDataItem(
        label: 'Atualizado em',
        value: AppFormatters.shortDateTime(cost.updatedAt),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth > 460
            ? (constraints.maxWidth - 10) / 2
            : constraints.maxWidth;

        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final item in items)
              SizedBox(
                width: cardWidth,
                child: AppCard(
                  borderRadius: 16,
                  padding: const EdgeInsets.all(12),
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.label,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.value,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _DetailDataItem {
  const _DetailDataItem({required this.label, required this.value});

  final String label;
  final String value;
}

class _CostFormSheet extends ConsumerStatefulWidget {
  const _CostFormSheet({required this.defaultType, this.initialCost});

  final CostType defaultType;
  final CostEntry? initialCost;

  @override
  ConsumerState<_CostFormSheet> createState() => _CostFormSheetState();
}

class _CostFormSheetState extends ConsumerState<_CostFormSheet> {
  late final TextEditingController _descriptionController;
  late final TextEditingController _categoryController;
  late final TextEditingController _amountController;
  late final TextEditingController _notesController;
  late CostType _selectedType;
  late DateTime _referenceDate;
  late bool _isRecurring;

  bool get _isEditing => widget.initialCost != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialCost;
    _descriptionController = TextEditingController(
      text: initial?.description ?? '',
    );
    _categoryController = TextEditingController(text: initial?.category ?? '');
    _amountController = TextEditingController(
      text: initial == null
          ? ''
          : AppFormatters.currencyInputFromCents(initial.amountCents),
    );
    _notesController = TextEditingController(text: initial?.notes ?? '');
    _selectedType = initial?.type ?? widget.defaultType;
    _referenceDate = initial?.referenceDate ?? DateTime.now();
    _isRecurring = initial?.isRecurring ?? false;
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _categoryController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final actionState = ref.watch(costActionControllerProvider);

    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      children: [
        Text(
          _isEditing ? 'Editar custo' : 'Novo custo',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Fixo'),
              selected: _selectedType == CostType.fixed,
              onSelected: (_) => setState(() => _selectedType = CostType.fixed),
            ),
            ChoiceChip(
              label: const Text('Variavel'),
              selected: _selectedType == CostType.variable,
              onSelected: (_) =>
                  setState(() => _selectedType = CostType.variable),
            ),
          ],
        ),
        const SizedBox(height: 12),
        AppInput(
          controller: _descriptionController,
          labelText: 'Descricao',
          prefixIcon: const Icon(Icons.description_outlined),
        ),
        const SizedBox(height: 10),
        AppInput(
          controller: _categoryController,
          labelText: 'Categoria',
          prefixIcon: const Icon(Icons.label_outline_rounded),
        ),
        const SizedBox(height: 10),
        AppInput(
          controller: _amountController,
          labelText: 'Valor',
          hintText: '0,00',
          prefixIcon: const Icon(Icons.attach_money_rounded),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: 10),
        _DateSelectorField(
          label: 'Data de referencia',
          value: _referenceDate,
          onTap: () async {
            final picked = await _pickDate(
              context,
              initialDate: _referenceDate,
            );
            if (picked != null) {
              setState(() => _referenceDate = picked);
            }
          },
        ),
        const SizedBox(height: 10),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Recorrente'),
          value: _isRecurring,
          onChanged: (value) => setState(() => _isRecurring = value),
        ),
        const SizedBox(height: 4),
        AppInput(
          controller: _notesController,
          labelText: 'Observacoes',
          prefixIcon: const Icon(Icons.notes_rounded),
          minLines: 3,
          maxLines: 4,
        ),
        const SizedBox(height: 16),
        AppButton.primary(
          label: 'Salvar custo',
          icon: Icons.check_rounded,
          expand: true,
          onPressed: actionState.isLoading ? null : _submit,
        ),
      ],
    );
  }

  Future<void> _submit() async {
    try {
      final amountCents = MoneyParser.parseToCents(_amountController.text);
      final controller = ref.read(costActionControllerProvider.notifier);
      final id = _isEditing
          ? (await controller.updateCost(
              costId: widget.initialCost!.id,
              input: UpdateCostInput(
                description: _descriptionController.text,
                type: _selectedType,
                category: _categoryController.text,
                amountCents: amountCents,
                referenceDate: _referenceDate,
                notes: _notesController.text,
                isRecurring: _isRecurring,
              ),
            )).id
          : await controller.createCost(
              CreateCostInput(
                description: _descriptionController.text,
                type: _selectedType,
                category: _categoryController.text,
                amountCents: amountCents,
                referenceDate: _referenceDate,
                notes: _notesController.text,
                isRecurring: _isRecurring,
              ),
            );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(id);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showError(context, error);
    }
  }
}

class _MarkCostPaidSheet extends ConsumerStatefulWidget {
  const _MarkCostPaidSheet({required this.cost});

  final CostEntry cost;

  @override
  ConsumerState<_MarkCostPaidSheet> createState() => _MarkCostPaidSheetState();
}

class _MarkCostPaidSheetState extends ConsumerState<_MarkCostPaidSheet> {
  late final TextEditingController _notesController;
  late DateTime _paidAt;
  PaymentMethod _paymentMethod = PaymentMethod.cash;
  bool _registerInCash = false;

  @override
  void initState() {
    super.initState();
    _notesController = TextEditingController();
    _paidAt = DateTime.now();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final actionState = ref.watch(costActionControllerProvider);

    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      children: [
        Text(
          'Marcar como pago',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 12),
        AppCard(
          borderRadius: 16,
          padding: const EdgeInsets.all(14),
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.cost.description),
              const SizedBox(height: 6),
              Text(
                AppFormatters.currencyFromCents(widget.cost.amountCents),
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _DateSelectorField(
          label: 'Pago em',
          value: _paidAt,
          onTap: () async {
            final picked = await _pickDate(context, initialDate: _paidAt);
            if (picked != null) {
              setState(() => _paidAt = picked);
            }
          },
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<PaymentMethod>(
          initialValue: _paymentMethod,
          decoration: const InputDecoration(
            labelText: 'Forma de pagamento',
            isDense: true,
          ),
          items: _manualPaymentMethods
              .map(
                (method) =>
                    DropdownMenuItem(value: method, child: Text(method.label)),
              )
              .toList(growable: false),
          onChanged: (value) {
            if (value != null) {
              setState(() => _paymentMethod = value);
            }
          },
        ),
        const SizedBox(height: 8),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Registrar tambem no caixa'),
          value: _registerInCash,
          onChanged: (value) => setState(() => _registerInCash = value),
        ),
        AppInput(
          controller: _notesController,
          labelText: 'Observacao do pagamento',
          prefixIcon: const Icon(Icons.notes_rounded),
          minLines: 3,
          maxLines: 4,
        ),
        const SizedBox(height: 16),
        AppButton.primary(
          label: 'Confirmar pagamento',
          icon: Icons.check_circle_rounded,
          expand: true,
          onPressed: actionState.isLoading ? null : _submit,
        ),
      ],
    );
  }

  Future<void> _submit() async {
    try {
      await ref
          .read(costActionControllerProvider.notifier)
          .markPaid(
            MarkCostPaidInput(
              costId: widget.cost.id,
              paidAt: _paidAt,
              paymentMethod: _paymentMethod,
              registerInCash: _registerInCash,
              notes: _notesController.text,
            ),
          );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showError(context, error);
    }
  }
}

class _CancelCostSheet extends ConsumerStatefulWidget {
  const _CancelCostSheet({required this.cost});

  final CostEntry cost;

  @override
  ConsumerState<_CancelCostSheet> createState() => _CancelCostSheetState();
}

class _CancelCostSheetState extends ConsumerState<_CancelCostSheet> {
  late final TextEditingController _notesController;

  @override
  void initState() {
    super.initState();
    _notesController = TextEditingController();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final actionState = ref.watch(costActionControllerProvider);

    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      children: [
        Text(
          'Cancelar custo',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 12),
        AppInput(
          controller: _notesController,
          labelText: 'Motivo do cancelamento',
          prefixIcon: const Icon(Icons.notes_rounded),
          minLines: 3,
          maxLines: 4,
        ),
        const SizedBox(height: 16),
        AppButton.secondary(
          label: 'Confirmar cancelamento',
          icon: Icons.cancel_outlined,
          expand: true,
          onPressed: actionState.isLoading ? null : _submit,
        ),
      ],
    );
  }

  Future<void> _submit() async {
    try {
      await ref
          .read(costActionControllerProvider.notifier)
          .cancelCost(costId: widget.cost.id, notes: _notesController.text);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showError(context, error);
    }
  }
}

class _DateSelectorField extends StatelessWidget {
  const _DateSelectorField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final DateTime value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        prefixIcon: const Icon(Icons.calendar_today_rounded),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(AppFormatters.shortDate(value)),
        ),
      ),
    );
  }
}

class _StateCard extends StatelessWidget {
  const _StateCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
    this.loading = false,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;
  final bool loading;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AppCard(
      borderRadius: compact ? 18 : 20,
      padding: EdgeInsets.all(compact ? 14 : 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: loading
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: colorScheme.primary,
                          ),
                        )
                      : Icon(icon, color: colorScheme.onPrimaryContainer),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (action != null) ...[const SizedBox(height: 12), action!],
        ],
      ),
    );
  }
}

Future<void> _refreshCosts(WidgetRef ref) async {
  ref.read(appDataRefreshProvider.notifier).state++;
  await ref.read(costOverviewProvider.future);
}

Future<List<CostEntry>> _queryCosts(
  WidgetRef ref, {
  required _CostViewFilter viewFilter,
  required _CostTypeFilter typeFilter,
  bool overdueOnly = false,
}) async {
  final repository = ref.read(costRepositoryProvider);
  final now = DateTime.now();
  final types = typeFilter.costType == null
      ? const [CostType.fixed, CostType.variable]
      : [typeFilter.costType!];
  final status = switch (viewFilter) {
    _CostViewFilter.open => CostStatus.pending,
    _CostViewFilter.paid => CostStatus.paid,
    _CostViewFilter.recurring => null,
  };

  final results = await Future.wait(
    types.map(
      (type) => repository.searchCosts(
        type: type,
        status: status,
        overdueOnly: overdueOnly,
      ),
    ),
  );

  var items = results.expand((group) => group).toList(growable: false);

  if (viewFilter == _CostViewFilter.recurring) {
    items = items
        .where((item) => item.isRecurring && !item.isCanceled)
        .toList();
  } else if (viewFilter == _CostViewFilter.open) {
    items = items.where((item) => item.isPending).toList();
  } else if (viewFilter == _CostViewFilter.paid) {
    items = items.where((item) => item.isPaid).toList();
  }

  if (overdueOnly) {
    items = items.where((item) => item.isOverdueAt(now)).toList();
  }

  items.sort((left, right) => _compareCosts(left, right, now));
  return items;
}

int _compareCosts(CostEntry left, CostEntry right, DateTime now) {
  final leftRank = _costRank(left, now);
  final rightRank = _costRank(right, now);
  if (leftRank != rightRank) {
    return leftRank.compareTo(rightRank);
  }

  if (left.isPending && right.isPending) {
    final byReference = left.referenceDate.compareTo(right.referenceDate);
    if (byReference != 0) {
      return byReference;
    }
  }

  if (left.isPaid && right.isPaid) {
    final byPaidAt = (right.paidAt ?? right.updatedAt).compareTo(
      left.paidAt ?? left.updatedAt,
    );
    if (byPaidAt != 0) {
      return byPaidAt;
    }
  }

  return right.updatedAt.compareTo(left.updatedAt);
}

int _costRank(CostEntry cost, DateTime now) {
  if (cost.isPending && cost.isOverdueAt(now)) {
    return 0;
  }
  if (cost.isPending) {
    return 1;
  }
  if (cost.isPaid) {
    return 2;
  }
  return 3;
}

Future<void> _startNewCostFlow(
  BuildContext context,
  WidgetRef ref, {
  CostType? suggestedType,
}) async {
  final selectedType = await showModalBottomSheet<CostType>(
    context: context,
    useSafeArea: true,
    builder: (_) => _CostTypePickerSheet(suggestedType: suggestedType),
  );

  if (selectedType == null || !context.mounted) {
    return;
  }

  await _showCostFormSheet(context, ref, defaultType: selectedType);
}

Future<void> _showCostFormSheet(
  BuildContext context,
  WidgetRef ref, {
  required CostType defaultType,
  CostEntry? initialCost,
}) async {
  final result = await showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.9,
      child: _CostFormSheet(defaultType: defaultType, initialCost: initialCost),
    ),
  );

  if (result != null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          initialCost == null
              ? 'Custo salvo com sucesso.'
              : 'Custo atualizado com sucesso.',
        ),
      ),
    );
  }
}

Future<void> _showCostDetailSheet(
  BuildContext context,
  WidgetRef ref,
  int costId,
) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.88,
      child: _CostDetailSheet(costId: costId),
    ),
  );
}

Future<void> _showMarkPaidSheet(
  BuildContext context,
  WidgetRef ref,
  CostEntry cost,
) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.78,
      child: _MarkCostPaidSheet(cost: cost),
    ),
  );

  if (result == true && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Custo marcado como pago.')));
  }
}

Future<void> _showCancelCostSheet(
  BuildContext context,
  WidgetRef ref,
  CostEntry cost,
) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.52,
      child: _CancelCostSheet(cost: cost),
    ),
  );

  if (result == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Custo cancelado com sucesso.')),
    );
  }
}

class _CostTypePickerSheet extends StatelessWidget {
  const _CostTypePickerSheet({this.suggestedType});

  final CostType? suggestedType;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Novo custo',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          _TypeChoiceTile(
            title: 'Custo fixo',
            subtitle: 'Aluguel, energia, internet, salarios...',
            selected: suggestedType == CostType.fixed,
            onTap: () => Navigator.of(context).pop(CostType.fixed),
          ),
          const SizedBox(height: 10),
          _TypeChoiceTile(
            title: 'Custo variavel',
            subtitle: 'Combustivel, embalagem, taxas, manutencoes...',
            selected: suggestedType == CostType.variable,
            onTap: () => Navigator.of(context).pop(CostType.variable),
          ),
        ],
      ),
    );
  }
}

class _TypeChoiceTile extends StatelessWidget {
  const _TypeChoiceTile({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      borderRadius: 16,
      padding: const EdgeInsets.all(14),
      color: selected
          ? Theme.of(context).colorScheme.primaryContainer
          : Theme.of(context).colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

String _mainSectionTitle(_CostViewFilter view, _CostTypeFilter type) {
  switch (view) {
    case _CostViewFilter.open:
      return type == _CostTypeFilter.all
          ? 'Custos em aberto'
          : 'Custos ${type.label.toLowerCase()} em aberto';
    case _CostViewFilter.paid:
      return type == _CostTypeFilter.all
          ? 'Custos pagos'
          : 'Custos ${type.label.toLowerCase()} pagos';
    case _CostViewFilter.recurring:
      return type == _CostTypeFilter.all
          ? 'Custos recorrentes'
          : 'Custos ${type.label.toLowerCase()} recorrentes';
  }
}

String _mainSectionSubtitle(_CostViewFilter view, _CostTypeFilter type) {
  switch (view) {
    case _CostViewFilter.open:
      return 'Acompanhe o que ainda precisa ser pago no periodo.';
    case _CostViewFilter.paid:
      return 'Veja rapidamente o que ja foi concluido.';
    case _CostViewFilter.recurring:
      return type == _CostTypeFilter.all
          ? 'Use esta visao para revisar custos que se repetem.'
          : 'Revise somente os custos ${type.label.toLowerCase()} recorrentes.';
  }
}

String _emptyMessageFor(_CostViewFilter view, _CostTypeFilter type) {
  switch (view) {
    case _CostViewFilter.open:
      return type == _CostTypeFilter.all
          ? 'Nao ha custos em aberto nesta visao.'
          : 'Nao ha custos ${type.label.toLowerCase()} em aberto.';
    case _CostViewFilter.paid:
      return type == _CostTypeFilter.all
          ? 'Nenhum custo pago encontrado.'
          : 'Nenhum custo ${type.label.toLowerCase()} pago encontrado.';
    case _CostViewFilter.recurring:
      return type == _CostTypeFilter.all
          ? 'Nenhum custo recorrente encontrado.'
          : 'Nenhum custo ${type.label.toLowerCase()} recorrente encontrado.';
  }
}

String _metaLine(CostEntry cost) {
  final parts = <String>[cost.type.label];
  if ((cost.category ?? '').isNotEmpty) {
    parts.add(cost.category!);
  }
  if (cost.isRecurring) {
    parts.add('Recorrente');
  }
  return parts.join(' • ');
}

void _showError(BuildContext context, Object error) {
  if (!context.mounted) {
    return;
  }
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(error.toString())));
}

AppStatusBadge _statusBadge(CostEntry cost) {
  if (cost.isCanceled) {
    return const AppStatusBadge(
      label: 'Cancelado',
      tone: AppStatusTone.neutral,
      icon: Icons.block_rounded,
    );
  }
  if (cost.isPaid) {
    return const AppStatusBadge(
      label: 'Pago',
      tone: AppStatusTone.success,
      icon: Icons.check_circle_rounded,
    );
  }
  if (cost.isOverdueAt(DateTime.now())) {
    return const AppStatusBadge(
      label: 'Vencido',
      tone: AppStatusTone.danger,
      icon: Icons.warning_amber_rounded,
    );
  }
  return const AppStatusBadge(
    label: 'Pendente',
    tone: AppStatusTone.warning,
    icon: Icons.schedule_rounded,
  );
}

Future<DateTime?> _pickDate(
  BuildContext context, {
  required DateTime initialDate,
}) async {
  final now = DateTime.now();
  return showDatePicker(
    context: context,
    initialDate: initialDate,
    firstDate: DateTime(now.year - 5),
    lastDate: DateTime(now.year + 10),
  );
}

const List<PaymentMethod> _manualPaymentMethods = <PaymentMethod>[
  PaymentMethod.cash,
  PaymentMethod.pix,
  PaymentMethod.card,
];
