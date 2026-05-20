import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/providers/app_data_refresh_provider.dart';
import '../../../../app/core/theme/app_design_tokens.dart';
import '../../../../app/core/widgets/app_card.dart';
import '../../../../app/core/widgets/app_main_drawer.dart';
import '../../../../app/core/widgets/app_page_header.dart';
import '../../../../app/core/widgets/app_state_card.dart';
import '../../../../app/core/widgets/app_status_badge.dart';
import '../../../../app/routes/route_names.dart';
import '../../domain/employee_models.dart';
import '../providers/employees_providers.dart';

class EmployeeActivityPage extends ConsumerWidget {
  const EmployeeActivityPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = context.appLayout;
    final canView = ref.watch(canViewEmployeeActivityProvider);
    final summaryAsync = ref.watch(employeeActivitySummaryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Atividade dos funcionários')),
      drawer: const AppMainDrawer(),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.read(appDataRefreshProvider.notifier).state++;
          if (canView) {
            await ref.read(employeeActivitySummaryProvider.future);
          }
        },
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            layout.pagePadding,
            layout.space4,
            layout.pagePadding,
            layout.pagePadding,
          ),
          children: [
            const AppPageHeader(
              title: 'Atividade dos funcionários',
              subtitle: 'Acompanhe vendas, ajustes e ações da equipe.',
              badgeLabel: 'Equipe',
              badgeIcon: Icons.groups_2_outlined,
            ),
            SizedBox(height: layout.space4),
            const _ActivityPeriodChips(),
            SizedBox(height: layout.space4),
            if (!canView)
              const AppStateCard(
                title: 'Sem permissão',
                message:
                    'Você não tem permissão para ver atividade de funcionários.',
                icon: Icons.lock_outline_rounded,
                tone: AppStateTone.warning,
                compact: true,
              )
            else
              summaryAsync.when(
                data: (summary) => _ActivitySummaryContent(summary: summary),
                loading: () => const AppStateCard(
                  title: 'Carregando atividade',
                  message: 'Buscando ações registradas no período.',
                  tone: AppStateTone.loading,
                  compact: true,
                ),
                error: (error, _) => AppStateCard(
                  title: 'Não foi possível carregar a atividade',
                  message: '$error',
                  tone: AppStateTone.error,
                  actionLabel: 'Tentar novamente',
                  onAction: () =>
                      ref.invalidate(employeeActivitySummaryProvider),
                  compact: true,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class EmployeeActivityDetailPage extends ConsumerWidget {
  const EmployeeActivityDetailPage({required this.employeeId, super.key});

  final String employeeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = context.appLayout;
    final detailAsync = ref.watch(employeeActivityDetailProvider(employeeId));

    return Scaffold(
      appBar: AppBar(title: const Text('Atividade do funcionário')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.read(appDataRefreshProvider.notifier).state++;
          await ref.read(employeeActivityDetailProvider(employeeId).future);
        },
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            layout.pagePadding,
            layout.space4,
            layout.pagePadding,
            layout.pagePadding,
          ),
          children: [
            const _ActivityPeriodChips(),
            SizedBox(height: layout.space4),
            detailAsync.when(
              data: (detail) => _ActivityDetailContent(detail: detail),
              loading: () => const AppStateCard(
                title: 'Carregando atividade',
                message: 'Buscando ações deste funcionário.',
                tone: AppStateTone.loading,
                compact: true,
              ),
              error: (error, _) => AppStateCard(
                title: 'Não foi possível carregar a atividade',
                message: '$error',
                tone: AppStateTone.error,
                actionLabel: 'Tentar novamente',
                onAction: () =>
                    ref.invalidate(employeeActivityDetailProvider(employeeId)),
                compact: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivitySummaryContent extends StatelessWidget {
  const _ActivitySummaryContent({required this.summary});

  final EmployeeActivitySummary summary;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final visibleRows = summary.rows;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _KpiGrid(
          items: [
            _KpiItem('Funcionários ativos', '${summary.activeEmployees}'),
            _KpiItem('Com atividade', '${summary.employeesWithActivity}'),
            _KpiItem('Vendas', '${summary.totalSalesCount}'),
            _KpiItem(
              'Total vendido',
              AppFormatters.currencyFromCents(summary.totalSalesAmountCents),
            ),
            _KpiItem('Ajustes de estoque', '${summary.totalStockAdjustments}'),
            _KpiItem('Cancelamentos', '${summary.totalCanceledCount}'),
          ],
        ),
        if (summary.tracking.partial) ...[
          SizedBox(height: layout.space4),
          const _PartialTrackingBanner(),
        ],
        SizedBox(height: layout.space4),
        if (visibleRows.isEmpty)
          const AppStateCard(
            title: 'Nenhuma atividade encontrada',
            message: 'Nenhuma atividade encontrada neste período.',
            icon: Icons.event_busy_outlined,
            compact: true,
          )
        else
          Column(
            children: [
              for (final row in visibleRows) ...[
                _EmployeeActivityRowCard(row: row),
                SizedBox(height: layout.space3),
              ],
            ],
          ),
      ],
    );
  }
}

class _ActivityDetailContent extends StatelessWidget {
  const _ActivityDetailContent({required this.detail});

  final EmployeeActivityDetail detail;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final summary = detail.summary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppPageHeader(
          title: detail.employee.name,
          subtitle:
              '${detail.employee.role.label} • ${detail.employee.status.label}',
          badgeLabel: 'Atividade',
          badgeIcon: Icons.manage_search_rounded,
        ),
        SizedBox(height: layout.space4),
        _KpiGrid(
          items: [
            _KpiItem('Vendas', '${summary.salesCount}'),
            _KpiItem(
              'Total vendido',
              AppFormatters.currencyFromCents(summary.salesAmountCents),
            ),
            _KpiItem(
              'Descontos',
              AppFormatters.currencyFromCents(summary.discountAmountCents),
            ),
            _KpiItem('Cancelamentos', '${summary.canceledSalesCount}'),
            _KpiItem('Ajustes de estoque', '${summary.stockAdjustmentsCount}'),
            _KpiItem('Caixa', '${summary.cashActionsCount}'),
          ],
        ),
        if (detail.tracking.partial) ...[
          SizedBox(height: layout.space4),
          const _PartialTrackingBanner(),
        ],
        SizedBox(height: layout.space4),
        Text(
          'Linha do tempo',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
        SizedBox(height: layout.space3),
        if (detail.timeline.isEmpty)
          const AppStateCard(
            title: 'Sem atividade',
            message: 'Nenhuma atividade encontrada neste período.',
            icon: Icons.event_busy_outlined,
            compact: true,
          )
        else
          Column(
            children: [
              for (final item in detail.timeline) ...[
                _TimelineItemCard(item: item),
                SizedBox(height: layout.space3),
              ],
            ],
          ),
      ],
    );
  }
}

class _ActivityPeriodChips extends ConsumerWidget {
  const _ActivityPeriodChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(employeeActivityPeriodProvider);
    final presets = <EmployeeActivityPeriod>[
      EmployeeActivityPeriod.today(),
      EmployeeActivityPeriod.yesterday(),
      EmployeeActivityPeriod.last7Days(),
      EmployeeActivityPeriod.thisMonth(),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final period in presets) ...[
            ChoiceChip(
              label: Text(period.label),
              selected:
                  selected.fromQuery == period.fromQuery &&
                  selected.toQuery == period.toQuery,
              onSelected: (_) {
                ref.read(employeeActivityPeriodProvider.notifier).state =
                    period;
              },
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _EmployeeActivityRowCard extends StatelessWidget {
  const _EmployeeActivityRowCard({required this.row});

  final EmployeeActivityRow row;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final theme = Theme.of(context);

    return AppCard(
      padding: EdgeInsets.all(layout.compactCardPadding),
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
                      row.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        AppStatusBadge(
                          label: row.role.label,
                          icon: Icons.badge_outlined,
                        ),
                        AppStatusBadge(
                          label: row.status.label,
                          icon: Icons.circle_outlined,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: () => context.pushNamed(
                  AppRouteNames.employeeActivityDetail,
                  pathParameters: {'employeeId': row.employeeId},
                ),
                icon: const Icon(Icons.chevron_right_rounded),
                label: const Text('Detalhes'),
              ),
            ],
          ),
          SizedBox(height: layout.space3),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _InlineMetric(
                label: 'Vendido',
                value: AppFormatters.currencyFromCents(row.salesAmountCents),
              ),
              _InlineMetric(label: 'Vendas', value: '${row.salesCount}'),
              _InlineMetric(
                label: 'Última atividade',
                value: row.lastActivityAt == null
                    ? 'Sem atividade'
                    : AppFormatters.shortDateTime(row.lastActivityAt!),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TimelineItemCard extends StatelessWidget {
  const _TimelineItemCard({required this.item});

  final EmployeeActivityTimelineItem item;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final theme = Theme.of(context);

    return AppCard(
      padding: EdgeInsets.all(layout.compactCardPadding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_iconForType(item.type), color: theme.colorScheme.primary),
          SizedBox(width: layout.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  item.occurredAt == null
                      ? 'Horário não informado'
                      : AppFormatters.shortDateTime(item.occurredAt!),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (item.amountCents != null)
            Text(
              AppFormatters.currencyFromCents(item.amountCents!),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
        ],
      ),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.items});

  final List<_KpiItem> items;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 720 ? 3 : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: layout.space3,
            crossAxisSpacing: layout.space3,
            mainAxisExtent: 96,
          ),
          itemBuilder: (context, index) {
            final item = items[index];
            return AppCard(
              padding: EdgeInsets.all(layout.compactCardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    item.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _KpiItem {
  const _KpiItem(this.label, this.value);

  final String label;
  final String value;
}

class _InlineMetric extends StatelessWidget {
  const _InlineMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _PartialTrackingBanner extends StatelessWidget {
  const _PartialTrackingBanner();

  @override
  Widget build(BuildContext context) {
    return const AppStateCard(
      title: 'Dados parcialmente rastreados',
      message: 'Algumas ações antigas podem aparecer sem responsável.',
      icon: Icons.info_outline_rounded,
      tone: AppStateTone.neutral,
      compact: true,
    );
  }
}

IconData _iconForType(String type) {
  switch (type) {
    case 'SALE':
      return Icons.point_of_sale_rounded;
    case 'DISCOUNT':
      return Icons.percent_rounded;
    case 'CANCELLATION':
      return Icons.cancel_outlined;
    case 'CASH_OPEN':
    case 'CASH_CLOSE':
    case 'CASH_MOVEMENT':
      return Icons.account_balance_wallet_outlined;
    case 'STOCK_ADJUSTMENT':
      return Icons.inventory_2_outlined;
    default:
      return Icons.history_rounded;
  }
}
