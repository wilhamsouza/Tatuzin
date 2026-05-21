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
import 'employees_page.dart';

class EmployeeCommissionsPage extends ConsumerWidget {
  const EmployeeCommissionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = context.appLayout;
    final canView = ref.watch(canViewEmployeeCommissionsProvider);
    final summaryAsync = ref.watch(employeeCommissionsSummaryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Comissões')),
      drawer: const AppMainDrawer(),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.read(appDataRefreshProvider.notifier).state++;
          if (canView) {
            await ref.read(employeeCommissionsSummaryProvider.future);
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
              title: 'Comissões',
              subtitle: 'Controle estimado sobre vendas atribuídas à equipe.',
              badgeLabel: 'Relatório',
              badgeIcon: Icons.payments_outlined,
            ),
            SizedBox(height: layout.space4),
            const _CommissionPeriodChips(),
            SizedBox(height: layout.space4),
            if (!canView)
              const AppStateCard(
                title: 'Sem permissão',
                message: 'Você não tem permissão para ver comissões.',
                icon: Icons.lock_outline_rounded,
                tone: AppStateTone.warning,
                compact: true,
              )
            else
              summaryAsync.when(
                data: (summary) => _CommissionSummaryContent(summary: summary),
                loading: () => const AppStateCard(
                  title: 'Carregando comissões',
                  message: 'Buscando vendas atribuídas no período.',
                  tone: AppStateTone.loading,
                  compact: true,
                ),
                error: (error, _) => AppStateCard(
                  title: 'Não foi possível carregar comissões',
                  message: '$error',
                  tone: AppStateTone.error,
                  actionLabel: 'Tentar novamente',
                  onAction: () =>
                      ref.invalidate(employeeCommissionsSummaryProvider),
                  compact: true,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class EmployeeCommissionDetailPage extends ConsumerWidget {
  const EmployeeCommissionDetailPage({required this.employeeId, super.key});

  final String employeeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = context.appLayout;
    final detailAsync = ref.watch(employeeCommissionDetailProvider(employeeId));

    return Scaffold(
      appBar: AppBar(title: const Text('Comissão do funcionário')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.read(appDataRefreshProvider.notifier).state++;
          await ref.read(employeeCommissionDetailProvider(employeeId).future);
        },
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            layout.pagePadding,
            layout.space4,
            layout.pagePadding,
            layout.pagePadding,
          ),
          children: [
            const _CommissionPeriodChips(),
            SizedBox(height: layout.space4),
            detailAsync.when(
              data: (detail) => _CommissionDetailContent(detail: detail),
              loading: () => const AppStateCard(
                title: 'Carregando comissão',
                message: 'Buscando vendas deste funcionário.',
                tone: AppStateTone.loading,
                compact: true,
              ),
              error: (error, _) => AppStateCard(
                title: 'Não foi possível carregar comissão',
                message: '$error',
                tone: AppStateTone.error,
                actionLabel: 'Tentar novamente',
                onAction: () => ref.invalidate(
                  employeeCommissionDetailProvider(employeeId),
                ),
                compact: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommissionSummaryContent extends StatelessWidget {
  const _CommissionSummaryContent({required this.summary});

  final EmployeeCommissionsSummary summary;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _KpiGrid(
          items: [
            _KpiItem(
              'Comissão total',
              AppFormatters.currencyFromCents(
                summary.totals.totalCommissionCents,
              ),
            ),
            _KpiItem(
              'Vendas elegíveis',
              '${summary.rows.fold<int>(0, (sum, row) => sum + row.eligibleSalesCount)}',
            ),
            _KpiItem(
              'Com comissão',
              '${summary.totals.employeesWithCommission}',
            ),
            _KpiItem(
              'Sem custo',
              '${summary.totals.salesWithoutReliableCostCount}',
            ),
          ],
        ),
        if (summary.totals.salesWithoutReliableCostCount > 0) ...[
          SizedBox(height: layout.space4),
          const AppStateCard(
            title: 'Custo ausente em algumas vendas',
            message:
                'Algumas vendas não entraram integralmente no cálculo por lucro porque produtos não tinham custo cadastrado.',
            icon: Icons.info_outline_rounded,
            compact: true,
          ),
        ],
        SizedBox(height: layout.space4),
        if (summary.rows.isEmpty)
          const AppStateCard(
            title: 'Nenhuma comissão encontrada',
            message: 'Não há vendas elegíveis no período selecionado.',
            icon: Icons.event_busy_outlined,
            compact: true,
          )
        else
          Column(
            children: [
              for (final row in summary.rows) ...[
                _CommissionRowCard(row: row),
                SizedBox(height: layout.space3),
              ],
            ],
          ),
      ],
    );
  }
}

class _CommissionDetailContent extends ConsumerWidget {
  const _CommissionDetailContent({required this.detail});

  final EmployeeCommissionDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = context.appLayout;
    final summary = detail.summary;
    final canManage = ref.watch(canManageEmployeesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppPageHeader(
          title: detail.employee.name,
          subtitle:
              '${detail.employee.role.label} • ${detail.employee.status.label}',
          badgeLabel: 'Comissão',
          badgeIcon: Icons.payments_outlined,
        ),
        SizedBox(height: layout.space4),
        _KpiGrid(
          items: [
            _KpiItem(
              'Comissão estimada',
              AppFormatters.currencyFromCents(summary.commissionAmountCents),
            ),
            _KpiItem('Vendas elegíveis', '${summary.eligibleSalesCount}'),
            _KpiItem(
              'Base de cálculo',
              AppFormatters.currencyFromCents(summary.eligibleBaseAmountCents),
            ),
            _KpiItem('Regra', _settingsLabel(detail.settings)),
          ],
        ),
        if (canManage) ...[
          SizedBox(height: layout.space4),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: () => _openSettingsSheet(context, detail),
              icon: const Icon(Icons.tune_rounded),
              label: Text(
                detail.settings.commissionEnabled
                    ? 'Configurar comissão'
                    : 'Ativar comissão',
              ),
            ),
          ),
        ],
        if (summary.salesWithoutReliableCostCount > 0) ...[
          SizedBox(height: layout.space4),
          const AppStateCard(
            title: 'Custo ausente',
            message:
                'Vendas sem custo cadastrado podem ficar fora do cálculo por lucro.',
            icon: Icons.info_outline_rounded,
            compact: true,
          ),
        ],
        SizedBox(height: layout.space4),
        Text(
          'Vendas',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
        SizedBox(height: layout.space3),
        if (detail.sales.isEmpty)
          const AppStateCard(
            title: 'Sem vendas elegíveis',
            message: 'Nenhuma venda atribuída no período.',
            icon: Icons.event_busy_outlined,
            compact: true,
          )
        else
          Column(
            children: [
              for (final sale in detail.sales) ...[
                _CommissionSaleCard(sale: sale),
                SizedBox(height: layout.space3),
              ],
            ],
          ),
      ],
    );
  }

  Future<void> _openSettingsSheet(
    BuildContext context,
    EmployeeCommissionDetail detail,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => EmployeeCommissionSettingsSheet.forSettings(
        employeeId: detail.employee.id,
        employeeName: detail.employee.name,
        initialSettings: detail.settings,
      ),
    );
  }
}

class _CommissionPeriodChips extends ConsumerWidget {
  const _CommissionPeriodChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(employeeActivityPeriodProvider);
    final presets = <EmployeeActivityPeriod>[
      EmployeeActivityPeriod.today(),
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

class _CommissionRowCard extends ConsumerWidget {
  const _CommissionRowCard({required this.row});

  final EmployeeCommissionRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = context.appLayout;
    final theme = Theme.of(context);
    final canManage = ref.watch(canManageEmployeesProvider);

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
                      row.employeeName,
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
                          label: _settingsLabel(row.settings),
                          icon: Icons.percent_rounded,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => context.pushNamed(
                      AppRouteNames.employeeCommissionDetail,
                      pathParameters: {'employeeId': row.employeeId},
                    ),
                    icon: const Icon(Icons.chevron_right_rounded),
                    label: const Text('Detalhes'),
                  ),
                  if (canManage && !row.settings.commissionEnabled)
                    TextButton.icon(
                      onPressed: () => _openSettingsSheet(context, row),
                      icon: const Icon(Icons.tune_rounded),
                      label: const Text('Ativar comissão'),
                    )
                  else if (canManage)
                    TextButton.icon(
                      onPressed: () => _openSettingsSheet(context, row),
                      icon: const Icon(Icons.tune_rounded),
                      label: const Text('Configurar comissão'),
                    ),
                ],
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
              _InlineMetric(
                label: 'Comissão',
                value: AppFormatters.currencyFromCents(
                  row.commissionAmountCents,
                ),
              ),
              _InlineMetric(
                label: 'Elegíveis',
                value: '${row.eligibleSalesCount}',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openSettingsSheet(
    BuildContext context,
    EmployeeCommissionRow row,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => EmployeeCommissionSettingsSheet.forSettings(
        employeeId: row.employeeId,
        employeeName: row.employeeName,
        initialSettings: row.settings,
      ),
    );
  }
}

class _CommissionSaleCard extends StatelessWidget {
  const _CommissionSaleCard({required this.sale});

  final EmployeeCommissionSale sale;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final theme = Theme.of(context);

    return AppCard(
      padding: EdgeInsets.all(layout.compactCardPadding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.receipt_long_outlined, color: theme.colorScheme.primary),
          SizedBox(width: layout.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sale.description,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sale.occurredAt == null
                      ? 'Horário não informado'
                      : AppFormatters.shortDateTime(sale.occurredAt!),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    _InlineMetric(
                      label: 'Base',
                      value: AppFormatters.currencyFromCents(
                        sale.baseAmountCents,
                      ),
                    ),
                    _InlineMetric(
                      label: 'Comissão',
                      value: AppFormatters.currencyFromCents(
                        sale.commissionAmountCents,
                      ),
                    ),
                  ],
                ),
              ],
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
        final columns = constraints.maxWidth >= 720 ? 4 : 2;
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

String _settingsLabel(EmployeeCommissionSettings settings) {
  if (!settings.commissionEnabled ||
      settings.commissionType == EmployeeCommissionType.none) {
    return 'Desativada';
  }
  if (settings.commissionType == EmployeeCommissionType.fixedPerSale) {
    return '${AppFormatters.currencyFromCents(settings.commissionFixedCents ?? 0)} por venda';
  }
  final bps = settings.commissionRateBps ?? 0;
  return '${_percentageLabel(bps)}% sobre ${settings.commissionBase.label.toLowerCase()}';
}

String _percentageLabel(int bps) {
  final whole = bps ~/ 100;
  final decimal = bps % 100;
  if (decimal == 0) {
    return '$whole';
  }
  return '$whole,${decimal.toString().padLeft(2, '0').replaceFirst(RegExp(r'0$'), '')}';
}
