import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/owner_providers.dart';
import '../../../core/models/owner_models.dart';
import '../../../core/widgets/owner_async_view.dart';
import '../../../core/widgets/owner_formatters.dart';
import '../../../core/widgets/owner_management_widgets.dart';
import 'owner_cash_workspace_section.dart';

class OwnerCashReportPage extends ConsumerStatefulWidget {
  const OwnerCashReportPage({super.key, this.query = const {}});

  final Map<String, String> query;

  @override
  ConsumerState<OwnerCashReportPage> createState() =>
      _OwnerCashReportPageState();
}

class _OwnerCashReportPageState extends ConsumerState<OwnerCashReportPage> {
  final _detailAnchor = GlobalKey();
  String? _requestedWorkspaceDetail;
  @override
  void initState() {
    super.initState();
    if (widget.query.isNotEmpty) _scheduleRestore();
  }

  @override
  void didUpdateWidget(OwnerCashReportPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (Uri(queryParameters: oldWidget.query).query !=
        Uri(queryParameters: widget.query).query) {
      _scheduleRestore();
    }
  }

  void _scheduleRestore() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final q = widget.query;
      ref.read(ownerReportStartDateProvider.notifier).state = q['startDate'];
      ref.read(ownerReportEndDateProvider.notifier).state = q['endDate'];
      ref.read(ownerCashSessionsStatusProvider.notifier).state =
          const [
            'all',
            'open',
            'closed',
            'with_difference',
          ].contains(q['status'])
          ? q['status']!
          : 'all';
      ref.read(ownerCashSessionsSearchProvider.notifier).state =
          q['search'] ?? '';
      ref.read(ownerCashSessionsPageProvider.notifier).state = max(
        1,
        int.tryParse(q['page'] ?? '') ?? 1,
      );
      ref.read(ownerSelectedCashSessionIdProvider.notifier).state =
          q['session'];
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedId = ref.watch(ownerSelectedCashSessionIdProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const OwnerPageIntro(
          title: 'Caixa',
          subtitle:
              'Acompanhe o caixa geral por funcionário, as pendências de sincronização e o histórico de conferência.',
          icon: Icons.account_balance_wallet_outlined,
        ),
        const SizedBox(height: 18),
        OwnerAsyncView(
          value: ref.watch(ownerCashWorkspaceProvider),
          onRetry: () => ref.invalidate(ownerCashWorkspaceProvider),
          builder: (workspace) => OwnerCashWorkspaceSection(
            workspace: workspace,
            onRefresh: () => ref.invalidate(ownerCashWorkspaceProvider),
            onSessionSelected: (id) {
              _requestedWorkspaceDetail = id;
              ref.read(ownerSelectedCashSessionIdProvider.notifier).state = id;
              _saveCashLocation(context, ref);
            },
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Histórico de sessões',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        const _CashFilters(),
        const SizedBox(height: 18),
        OwnerAsyncView(
          value: ref.watch(ownerCashSessionsProvider),
          onRetry: () => ref.invalidate(ownerCashSessionsProvider),
          builder: (data) => _CashReportContent(report: data),
        ),
        if (selectedId != null) ...[
          const SizedBox(height: 18),
          OwnerAsyncView(
            value: ref.watch(ownerCashSessionDetailProvider(selectedId)),
            onRetry: () =>
                ref.invalidate(ownerCashSessionDetailProvider(selectedId)),
            builder: (detail) {
              if (_requestedWorkspaceDetail == selectedId) {
                _requestedWorkspaceDetail = null;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  final target = _detailAnchor.currentContext;
                  if (mounted && target != null) {
                    Scrollable.ensureVisible(target);
                  }
                });
              }
              final workspace = ref
                  .watch(ownerCashWorkspaceProvider)
                  .valueOrNull;
              final pending =
                  workspace?.employees.any(
                    (employee) =>
                        employee.isPending &&
                        (employee.sessionIds.contains(selectedId) ||
                            employee.activeSessionId == selectedId),
                  ) ??
                  false;
              return _CashDetail(
                key: _detailAnchor,
                detail: detail,
                pendingClosure: pending,
              );
            },
          ),
        ],
      ],
    );
  }
}

void _saveCashLocation(BuildContext context, WidgetRef ref) {
  final router = GoRouter.maybeOf(context);
  if (router == null) return;
  final start = ref.read(ownerReportStartDateProvider);
  final end = ref.read(ownerReportEndDateProvider);
  final search = ref.read(ownerCashSessionsSearchProvider);
  final selected = ref.read(ownerSelectedCashSessionIdProvider);
  router.go(
    Uri(
      path: '/reports/cash',
      queryParameters: {
        if (start != null && start.isNotEmpty) 'startDate': start,
        if (end != null && end.isNotEmpty) 'endDate': end,
        'status': ref.read(ownerCashSessionsStatusProvider),
        if (search.isNotEmpty) 'search': search,
        'page': '${ref.read(ownerCashSessionsPageProvider)}',
        if (selected != null) 'session': selected,
      },
    ).toString(),
  );
}

class _CashFilters extends ConsumerStatefulWidget {
  const _CashFilters();

  @override
  ConsumerState<_CashFilters> createState() => _CashFiltersState();
}

class _CashFiltersState extends ConsumerState<_CashFilters> {
  final _form = GlobalKey<FormState>();
  String? _start;
  String? _end;
  String _search = '';
  String? _status;

  String? _dateError(String? value) {
    if (value == null || value.isEmpty) return null;
    final date = DateTime.tryParse(value);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) ||
        date == null ||
        date.toIso8601String().substring(0, 10) != value) {
      return 'Use AAAA-MM-DD';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final start = ref.watch(ownerReportStartDateProvider);
    final end = ref.watch(ownerReportEndDateProvider);
    final search = ref.watch(ownerCashSessionsSearchProvider);
    final status = ref.watch(ownerCashSessionsStatusProvider);
    return OwnerSectionCard(
      title: 'Período e filtros',
      subtitle:
          'Datas de abertura • Totais calculados para todo o período filtrado.',
      child: Form(
        key: _form,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final fieldWidth = constraints.maxWidth < 480
                ? constraints.maxWidth
                : 210.0;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.start,
              children: [
                SizedBox(
                  width: fieldWidth,
                  child: TextFormField(
                    key: ValueKey('cash-start-$start'),
                    initialValue: start,
                    decoration: const InputDecoration(
                      labelText: 'Data inicial',
                      hintText: 'AAAA-MM-DD',
                    ),
                    validator: _dateError,
                    onSaved: (v) => _start = v?.trim(),
                  ),
                ),
                SizedBox(
                  width: fieldWidth,
                  child: TextFormField(
                    key: ValueKey('cash-end-$end'),
                    initialValue: end,
                    decoration: const InputDecoration(
                      labelText: 'Data final',
                      hintText: 'AAAA-MM-DD',
                    ),
                    validator: _dateError,
                    onSaved: (v) => _end = v?.trim(),
                  ),
                ),
                SizedBox(
                  width: fieldWidth,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('cash-status-$status'),
                    initialValue: status,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('Todos')),
                      DropdownMenuItem(value: 'open', child: Text('Aberto')),
                      DropdownMenuItem(value: 'closed', child: Text('Fechado')),
                      DropdownMenuItem(
                        value: 'with_difference',
                        child: Text('Com diferença'),
                      ),
                    ],
                    onChanged: (v) => _status = v,
                  ),
                ),
                SizedBox(
                  width: constraints.maxWidth < 480
                      ? constraints.maxWidth
                      : 300,
                  child: TextFormField(
                    key: ValueKey('cash-search-$search'),
                    initialValue: search,
                    decoration: const InputDecoration(
                      labelText: 'Buscar caixa ou responsável',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onSaved: (v) => _search = v?.trim() ?? '',
                    onFieldSubmitted: (_) => _apply(),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _apply,
                  icon: const Icon(Icons.filter_alt_outlined),
                  label: const Text('Aplicar filtros'),
                ),
                OutlinedButton.icon(
                  onPressed: () => ref.invalidate(ownerCashSessionsProvider),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Atualizar'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _apply() {
    if (!_form.currentState!.validate()) return;
    _form.currentState!.save();
    if ((_start ?? '').isNotEmpty &&
        (_end ?? '').isNotEmpty &&
        _start!.compareTo(_end!) > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A data final deve ser igual ou posterior à inicial.'),
        ),
      );
      return;
    }
    ref.read(ownerReportStartDateProvider.notifier).state =
        (_start ?? '').isEmpty ? null : _start;
    ref.read(ownerReportEndDateProvider.notifier).state = (_end ?? '').isEmpty
        ? null
        : _end;
    ref.read(ownerCashSessionsSearchProvider.notifier).state = _search;
    ref.read(ownerCashSessionsStatusProvider.notifier).state =
        _status ?? ref.read(ownerCashSessionsStatusProvider);
    ref.read(ownerCashSessionsPageProvider.notifier).state = 1;
    ref.read(ownerSelectedCashSessionIdProvider.notifier).state = null;
    _saveCashLocation(context, ref);
  }
}

class _CashReportContent extends ConsumerWidget {
  const _CashReportContent({required this.report});
  final OwnerCashSessionsReport report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = report.summary;
    void open(OwnerCashSessionItem item) {
      ref.read(ownerSelectedCashSessionIdProvider.notifier).state = item.id;
      _saveCashLocation(context, ref);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            OwnerMetricCard(
              title: 'Caixas abertos',
              value: summary.openSessions?.toString() ?? '—',
              detail: 'No período filtrado',
              icon: Icons.lock_open_outlined,
              isAvailable: summary.openSessions != null,
            ),
            OwnerMetricCard(
              title: 'Caixas fechados',
              value: summary.closedSessions?.toString() ?? '—',
              detail: '${summary.totalSessions} sessões no período',
              icon: Icons.lock_outline,
              isAvailable: summary.closedSessions != null,
            ),
            OwnerMetricCard(
              title: 'Com diferença',
              value: '${summary.sessionsWithDifference}',
              detail: summary.totalDifferenceCents == null
                  ? 'Total de diferença indisponível'
                  : 'Saldo: ${OwnerFormatters.moneyFromCents(summary.totalDifferenceCents!)}',
              icon: Icons.balance_outlined,
              isAvailable: true,
            ),
            OwnerMetricCard(
              title: 'Total vendido',
              value: OwnerFormatters.moneyFromCents(summary.totalSoldCents),
              detail: '${summary.salesCount} vendas',
              icon: Icons.point_of_sale_rounded,
              isAvailable: true,
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (summary.receiptBreakdownAvailable == false)
          const Padding(
            padding: EdgeInsets.only(bottom: 18),
            child: Text(
              'Recebimentos por forma indisponíveis: sincronização ou conciliação pendente.',
            ),
          ),
        if (summary.receiptBreakdownAvailable == true &&
            summary.byPaymentMethod.isNotEmpty) ...[
          OwnerSectionCard(
            title: 'Recebimentos por forma',
            subtitle:
                'Valores recebidos no caixa, incluindo recebimentos de fiado e ajustes conciliados.',
            child: Wrap(
              spacing: 24,
              runSpacing: 12,
              children: [
                for (final method in summary.byPaymentMethod)
                  _CashFact(
                    label: method.label,
                    value: OwnerFormatters.moneyFromCents(
                      method.totalAmountCents,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
        ],
        OwnerSectionCard(
          title: 'Sessões de caixa',
          subtitle:
              'Abertura e operação são feitas no aplicativo. Aqui você acompanha e confere.',
          child: report.items.items.isEmpty
              ? const OwnerEmptyState(
                  title: 'Nenhum caixa encontrado',
                  message: 'Ajuste os filtros ou escolha outro período.',
                  icon: Icons.search_off_rounded,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final largeText =
                            MediaQuery.textScalerOf(context).scale(14) > 21;
                        if (constraints.maxWidth < 900 || largeText) {
                          return Column(
                            children: [
                              for (final item in report.items.items)
                                _CashSessionTile(
                                  item: item,
                                  onOpen: () => open(item),
                                ),
                            ],
                          );
                        }
                        return SizedBox(
                          width: double.infinity,
                          child: DataTable(
                            columnSpacing: 20,
                            horizontalMargin: 12,
                            columns: const [
                              DataColumn(label: Text('Caixa / responsável')),
                              DataColumn(label: Text('Abertura')),
                              DataColumn(label: Text('Status')),
                              DataColumn(label: Text('Vendas'), numeric: true),
                              DataColumn(
                                label: Text('Diferença'),
                                numeric: true,
                              ),
                              DataColumn(label: Text('Consulta')),
                            ],
                            rows: [
                              for (final item in report.items.items)
                                DataRow(
                                  cells: [
                                    DataCell(
                                      Text(
                                        '${item.shortId}\n${item.employee.name}',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    DataCell(
                                      Text(OwnerFormatters.date(item.openedAt)),
                                    ),
                                    DataCell(Text(item.statusLabel)),
                                    DataCell(
                                      Text(
                                        OwnerFormatters.moneyFromCents(
                                          item.totalSoldCents,
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        item.status == 'closed'
                                            ? OwnerFormatters.moneyFromCents(
                                                item.differenceCents,
                                              )
                                            : '—',
                                      ),
                                    ),
                                    DataCell(
                                      TextButton(
                                        onPressed: () => open(item),
                                        child: const Text('Ver detalhes'),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '${report.items.items.length} de ${report.items.total} sessões • Página ${report.items.page}',
                        ),
                        OutlinedButton(
                          onPressed: report.items.page <= 1
                              ? null
                              : () {
                                  ref
                                          .read(
                                            ownerCashSessionsPageProvider
                                                .notifier,
                                          )
                                          .state =
                                      report.items.page - 1;
                                  _saveCashLocation(context, ref);
                                },
                          child: const Text('Anterior'),
                        ),
                        OutlinedButton(
                          onPressed:
                              report.items.page * report.items.pageSize >=
                                  report.items.total
                              ? null
                              : () {
                                  ref
                                          .read(
                                            ownerCashSessionsPageProvider
                                                .notifier,
                                          )
                                          .state =
                                      report.items.page + 1;
                                  _saveCashLocation(context, ref);
                                },
                          child: const Text('Próxima'),
                        ),
                      ],
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _CashSessionTile extends StatelessWidget {
  const _CashSessionTile({required this.item, required this.onOpen});
  final OwnerCashSessionItem item;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${item.shortId} • ${item.employee.name}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text('${item.statusLabel} • ${OwnerFormatters.date(item.openedAt)}'),
          Text(
            'Vendas: ${OwnerFormatters.moneyFromCents(item.totalSoldCents)} • ${item.salesCount} vendas',
          ),
          if (item.status == 'closed')
            Text(
              'Diferença: ${OwnerFormatters.moneyFromCents(item.differenceCents)}',
            ),
          const SizedBox(height: 8),
          if (item.receiptBreakdownAvailable == false)
            const Text('Recebimentos por forma pendentes de conciliação.'),
          TextButton.icon(
            onPressed: onOpen,
            icon: const Icon(Icons.visibility_outlined),
            label: const Text('Ver detalhes'),
          ),
        ],
      ),
    ),
  );
}

class _CashDetail extends ConsumerWidget {
  const _CashDetail({
    super.key,
    required this.detail,
    this.pendingClosure = false,
  });
  final OwnerCashSessionDetail detail;
  final bool pendingClosure;

  @override
  Widget build(BuildContext context, WidgetRef ref) => OwnerSectionCard(
    title: 'Detalhe do caixa ${detail.session.shortId}',
    subtitle:
        'A conferência gerencial preserva os valores registrados no fechamento.',
    trailing: IconButton(
      tooltip: 'Fechar detalhe',
      icon: const Icon(Icons.close_rounded),
      onPressed: () {
        ref.read(ownerSelectedCashSessionIdProvider.notifier).state = null;
        _saveCashLocation(context, ref);
      },
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 20,
          runSpacing: 12,
          children: [
            _CashFact(label: 'Responsável', value: detail.employee.name),
            _CashFact(
              label: 'Dispositivo',
              value: detail.deviceName ?? 'Não informado',
            ),
            _CashFact(
              label: 'Abertura',
              value: OwnerFormatters.date(detail.session.openedAt),
            ),
            _CashFact(
              label: 'Fechamento',
              value: detail.session.closedAt == null
                  ? 'Em aberto'
                  : OwnerFormatters.date(detail.session.closedAt),
            ),
            _CashFact(
              label: 'Fundo de abertura',
              value: OwnerFormatters.moneyFromCents(
                detail.values.openingBalanceCents,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (pendingClosure)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              'Conferência pendente. Esta sessão ainda aguarda sincronização ou revisão pelo responsável no aplicativo. O fechamento não está confirmado.',
            ),
          ),
        _ClosureDetails(detail: detail, pendingClosure: pendingClosure),
        const SizedBox(height: 18),
        if (!pendingClosure) _DivergenceReview(detail: detail),
        const SizedBox(height: 18),
        _SalesList(sessionId: detail.session.id, sales: detail.sales.items),
        if (detail.sales.total > detail.sales.items.length)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Exibindo ${detail.sales.items.length} de ${detail.sales.total} vendas. Esta lista é parcial.',
            ),
          ),
        const SizedBox(height: 18),
        _MovementsList(movements: detail.movements),
      ],
    ),
  );
}

class _CashFact extends StatelessWidget {
  const _CashFact({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 220,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        Text(value),
      ],
    ),
  );
}

class _CashSubsection extends StatelessWidget {
  const _CashSubsection({
    required this.title,
    required this.child,
    this.subtitle,
  });
  final String title;
  final String? subtitle;
  final Widget child;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
      if (subtitle != null) ...[
        const SizedBox(height: 6),
        Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium),
      ],
      const SizedBox(height: 12),
      child,
    ],
  );
}

String _cashMoney(Object? value) => value is num
    ? OwnerFormatters.moneyFromCents(value.toInt())
    : 'Não informado';

class _ClosureDetails extends StatelessWidget {
  const _ClosureDetails({required this.detail, this.pendingClosure = false});
  final OwnerCashSessionDetail detail;
  final bool pendingClosure;
  @override
  Widget build(BuildContext context) {
    final closure = detail.closingDetails;
    final detailed = closure['version'] == 2;
    return _CashSubsection(
      title: pendingClosure
          ? 'Contagem enviada, ainda pendente'
          : detail.session.closedAt == null
          ? 'Caixa em aberto'
          : 'Fechamento original',
      subtitle: pendingClosure
          ? 'Proposta de contagem sujeita à sincronização e à revisão do responsável no aplicativo.'
          : detailed
          ? 'Contagem registrada pelo operador no aplicativo.'
          : 'Detalhamento de contagem não disponível para esta sessão.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 20,
            runSpacing: 12,
            children: [
              _CashFact(
                label: 'Esperado no fechamento',
                value: _cashMoney(
                  detailed
                      ? closure['expectedBalanceCents']
                      : detail.values.expectedBalanceCents,
                ),
              ),
              _CashFact(
                label: 'Declarado pelo operador',
                value: _cashMoney(
                  detailed
                      ? closure['countedBalanceCents']
                      : detail.values.closingBalanceCents,
                ),
              ),
              _CashFact(
                label: pendingClosure
                    ? 'Diferença declarada, não confirmada'
                    : 'Diferença original',
                value: detail.session.closedAt == null
                    ? '—'
                    : _cashMoney(
                        detailed
                            ? closure['differenceCents']
                            : detail.values.differenceCents,
                      ),
              ),
            ],
          ),
          if (detailed) ...[
            const SizedBox(height: 12),
            Text(
              'Conferência cega: ${closure['blindClosureEnabled'] == true ? 'ativada' : 'desativada'} • Política ${closure['policyRevision'] ?? 'não informada'}',
            ),
            if (closure['reason'] is String &&
                (closure['reason'] as String).isNotEmpty)
              Text('Motivo do operador: ${closure['reason']}'),
            if (closure['notes'] is String &&
                (closure['notes'] as String).isNotEmpty)
              Text('Observações do operador: ${closure['notes']}'),
            if (closure['denominations'] is List) ...[
              const SizedBox(height: 12),
              Text(
                'Contagem por cédula',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              for (final row in closure['denominations'] as List)
                if (row is Map)
                  Text('${_cashMoney(row['valueCents'])} × ${row['quantity']}'),
            ],
            if (closure['coinsCents'] is num)
              Text('Moedas: ${_cashMoney(closure['coinsCents'])}'),
            if (closure['denominations'] == null &&
                closure['coinsCents'] == null)
              const Text('Composição por cédulas e moedas não registrada.'),
          ],
          if (detail.openingDetails['version'] == 2) ...[
            const SizedBox(height: 12),
            Text(
              detail.openingAwaitingConfirmation == true
                  ? 'Abertura aguardando conferência do troco inicial.'
                  : 'Contagem na abertura: ${_cashMoney(detail.openingDetails['countedAmountCents'])} • Política ${detail.openingDetails['policyRevision'] ?? 'não informada'}',
            ),
          ],
          if (detail.hasLateMovements) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: const Text(
                'Há movimentos posteriores ao fechamento. Consulte o histórico; os valores originais acima foram preservados.',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DivergenceReview extends ConsumerWidget {
  const _DivergenceReview({required this.detail});
  final OwnerCashSessionDetail detail;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final review = detail.divergenceReview;
    if (detail.closingDetails['version'] != 2) {
      return const _CashSubsection(
        title: 'Conferência da divergência',
        child: Text(
          'Conferência gerencial não disponível para esta sessão legada. O fechamento original permanece disponível para consulta.',
        ),
      );
    }
    if (detail.values.differenceCents == 0) {
      return const _CashSubsection(
        title: 'Conferência da divergência',
        child: Text('Sem divergência registrada no fechamento.'),
      );
    }
    return _CashSubsection(
      title: 'Conferência da divergência',
      subtitle: 'Registro gerencial separado da contagem original.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            review['status'] == 'REVIEWED'
                ? 'Conferida'
                : 'Pendente de conferência',
          ),
          if (review['justification'] is String)
            Text('Justificativa: ${review['justification']}'),
          if (detail.canReview &&
              detail.session.closedAt != null &&
              detail.values.differenceCents != 0) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (_) => _ReviewDialog(detail: detail),
              ),
              icon: const Icon(Icons.fact_check_outlined),
              label: Text(
                review['status'] == 'REVIEWED'
                    ? 'Reabrir conferência'
                    : 'Conferir divergência',
              ),
            ),
          ],
          if (!detail.canReview)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Seu acesso permite consultar este registro.'),
            ),
          if (detail.divergenceReviewHistory.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Histórico de conferência',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            for (final entry in detail.divergenceReviewHistory)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${OwnerFormatters.date(entry['createdAt'] as String?)} • ${entry['authorName'] ?? 'Responsável não informado'} • ${entry['status'] == 'REVIEWED' ? 'Conferida' : 'Pendente'}\n${entry['justification'] ?? ''}',
                ),
              ),
          ],
        ],
      ),
    );
  }
}

String _cashRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final h = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

class _ReviewDialog extends ConsumerStatefulWidget {
  const _ReviewDialog({required this.detail});
  final OwnerCashSessionDetail detail;
  @override
  ConsumerState<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends ConsumerState<_ReviewDialog> {
  final _reason = TextEditingController();
  final _requestId = _cashRequestId();
  bool _busy = false;
  bool _conflict = false;
  bool _attempted = false;
  String? _error;
  Map<String, dynamic>? _request;
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pending = widget.detail.divergenceReview['status'] == 'REVIEWED';
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(pending ? 'Reabrir conferência' : 'Conferir divergência'),
        scrollable: true,
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                pending
                    ? 'A conferência ficará pendente. O caixa permanece fechado e a contagem original será preservada.'
                    : 'Confirme a análise e registre uma justificativa. O fechamento original será preservado.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _reason,
                autofocus: true,
                readOnly: _attempted,
                maxLines: 4,
                maxLength: 2000,
                decoration: const InputDecoration(
                  labelText: 'Justificativa obrigatória',
                ),
              ),
              if (_error != null)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Voltar'),
          ),
          if (_conflict)
            FilledButton(
              onPressed: () {
                ref.invalidate(
                  ownerCashSessionDetailProvider(widget.detail.session.id),
                );
                Navigator.of(context).pop();
              },
              child: const Text('Recarregar conferência'),
            )
          else
            FilledButton(
              onPressed: _busy ? null : () => _submit(pending),
              child: Text(
                _busy
                    ? 'Registrando…'
                    : _attempted
                    ? 'Tentar novamente'
                    : 'Confirmar registro',
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _submit(bool pending) async {
    if (_reason.text.trim().length < 3) {
      setState(
        () => _error = 'Informe uma justificativa com pelo menos 3 caracteres.',
      );
      return;
    }
    _request ??= {
      'requestId': _requestId,
      'expectedRevision': widget.detail.divergenceReview['revision'] ?? 0,
      'status': pending ? 'PENDING' : 'REVIEWED',
      'justification': _reason.text.trim(),
    };
    setState(() {
      _busy = true;
      _attempted = true;
      _error = null;
    });
    try {
      await ref
          .read(ownerApiServiceProvider)
          .reviewCashDivergence(
            cashSessionId: widget.detail.session.id,
            body: _request!,
          );
      ref.invalidate(ownerCashSessionDetailProvider(widget.detail.session.id));
      ref.invalidate(ownerCashSessionsProvider);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } on OwnerApiException catch (error) {
      if (mounted) {
        setState(() {
          _conflict = error.statusCode == 409;
          _error = _conflict
              ? 'Outra pessoa atualizou a conferência. Recarregue e revise o histórico antes de registrar novamente.'
              : error.message;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _SalesList extends StatelessWidget {
  const _SalesList({required this.sessionId, required this.sales});

  final String sessionId;
  final List<OwnerCashSessionSale> sales;

  @override
  Widget build(BuildContext context) {
    if (sales.isEmpty) {
      return const OwnerEmptyState(
        title: 'Nenhuma venda neste caixa',
        message:
            'Quando houver vendas vinculadas ao caixa, elas aparecerao aqui.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Vendas do caixa',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        for (final sale in sales) _SaleTile(sessionId: sessionId, sale: sale),
      ],
    );
  }
}

class _SaleTile extends ConsumerWidget {
  const _SaleTile({required this.sessionId, required this.sale});

  final String sessionId;
  final OwnerCashSessionSale sale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        key: PageStorageKey('cash-sale-$sessionId-${sale.id}'),
        title: Text('Venda ${sale.receiptNumber ?? sale.shortId}'),
        subtitle: Text(
          '${OwnerFormatters.date(sale.soldAt)} • ${sale.paymentMethod} • ${sale.statusLabel}\n${OwnerFormatters.moneyFromCents(sale.totalAmountCents)}',
        ),

        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Cliente: ${sale.customerName ?? 'Nao informado'}'),
          ),
          const SizedBox(height: 8),
          for (final item in sale.items)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${item.productName} - ${OwnerFormatters.quantityFromMil(item.quantityMil)} x ${OwnerFormatters.moneyFromCents(item.unitPriceCents)}',
              ),
            ),
          if (sale.requiresOperatorApp)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text('Faça a operação no app com funcionário autorizado.'),
            ),
          if (sale.actions.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final action in sale.actions)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${action.title}: ${OwnerFormatters.moneyFromCents(action.amountCents)}',
                ),
              ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _showReceiptDialog(context, sale),
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('Ver comprovante'),
              ),
              if (sale.canReturn && !sale.requiresOperatorApp)
                FilledButton.icon(
                  onPressed: () =>
                      _showReturnDialog(context, ref, sessionId, sale),
                  icon: const Icon(Icons.assignment_return_outlined),
                  label: const Text('Registrar troca/devolucao'),
                ),
              if (sale.canCancel && !sale.requiresOperatorApp)
                OutlinedButton.icon(
                  onPressed: () =>
                      _confirmCancel(context, ref, sessionId, sale),
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Cancelar venda'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MovementsList extends StatelessWidget {
  const _MovementsList({required this.movements});

  final List<OwnerCashMovement> movements;

  @override
  Widget build(BuildContext context) {
    return _CashSubsection(
      title: 'Movimentos e historico',
      subtitle:
          'Inclui movimentos do caixa e acoes administrativas posteriores.',
      child: movements.isEmpty
          ? const OwnerEmptyState(
              title: 'Sem movimentos',
              message: 'Nenhum movimento foi encontrado para este caixa.',
            )
          : Column(
              children: [
                for (final movement in movements)
                  ListTile(
                    leading: const Icon(Icons.history_rounded),
                    title: Text(movement.title),
                    subtitle: Text(
                      '${OwnerFormatters.date(movement.createdAt)} • ${movement.paymentMethod}\n${movement.notes ?? 'Sem observação'}\n${OwnerFormatters.moneyFromCents(movement.amountCents)}',
                    ),
                  ),
              ],
            ),
    );
  }
}

void _showReceiptDialog(BuildContext context, OwnerCashSessionSale sale) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Comprovante ${sale.receiptNumber ?? sale.shortId}'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Data: ${OwnerFormatters.date(sale.soldAt)}'),
            Text('Cliente: ${sale.customerName ?? 'Nao informado'}'),
            Text('Forma: ${sale.paymentMethod}'),
            const SizedBox(height: 12),
            for (final item in sale.items)
              Text(
                '${item.productName}: ${OwnerFormatters.moneyFromCents(item.totalPriceCents)}',
              ),
            const Divider(),
            Text(
              'Total: ${OwnerFormatters.moneyFromCents(sale.totalAmountCents)}',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fechar'),
        ),
      ],
    ),
  );
}

Future<void> _showReturnDialog(
  BuildContext context,
  WidgetRef ref,
  String sessionId,
  OwnerCashSessionSale sale,
) async {
  final reasonController = TextEditingController();
  final quantities = <String, int>{
    for (final item in sale.items) item.id: item.quantityMil,
  };
  var returnToStock = true;
  var submitting = false;
  final messenger = ScaffoldMessenger.of(context);
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
        title: const Text('Registrar troca/devolucao'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Essa acao sera registrada no historico da venda e nao altera o fechamento original do caixa.',
              ),
              const SizedBox(height: 12),
              for (final item in sale.items)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: (quantities[item.id] ?? 0) > 0,
                  title: Text(item.productName),
                  subtitle: Text(
                    'Quantidade: ${OwnerFormatters.quantityFromMil(item.quantityMil)}',
                  ),
                  onChanged: submitting
                      ? null
                      : (checked) {
                          setState(() {
                            quantities[item.id] = checked == true
                                ? item.quantityMil
                                : 0;
                          });
                        },
                ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: returnToStock,
                title: const Text('Voltar item ao estoque'),
                onChanged: submitting
                    ? null
                    : (value) => setState(() => returnToStock = value == true),
              ),
              TextField(
                controller: reasonController,
                decoration: const InputDecoration(labelText: 'Motivo'),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: submitting
                ? null
                : () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: submitting
                ? null
                : () async {
                    final reason = reasonController.text.trim();
                    if (reason.length < 3) {
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Informe o motivo.')),
                      );
                      return;
                    }
                    final selectedItems = quantities.entries
                        .where((entry) => entry.value > 0)
                        .map(
                          (entry) => {
                            'saleItemId': entry.key,
                            'quantityMil': entry.value,
                          },
                        )
                        .toList(growable: false);
                    if (selectedItems.isEmpty) {
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text('Selecione pelo menos um item.'),
                        ),
                      );
                      return;
                    }
                    final navigator = Navigator.of(dialogContext);
                    var keepDialogOpen = true;
                    setState(() => submitting = true);
                    try {
                      await ref
                          .read(ownerApiServiceProvider)
                          .registerSaleReturn(
                            cashSessionId: sessionId,
                            saleId: sale.id,
                            body: {
                              'reason': reason,
                              'returnToStock': returnToStock,
                              'items': selectedItems,
                            },
                          );
                      ref.invalidate(ownerCashSessionsProvider);
                      ref.invalidate(ownerCashSessionDetailProvider(sessionId));
                      keepDialogOpen = false;
                      if (navigator.mounted) {
                        navigator.pop();
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text('Troca/devolucao registrada.'),
                          ),
                        );
                      }
                    } on OwnerApiException catch (error) {
                      messenger.showSnackBar(
                        SnackBar(content: Text(error.message)),
                      );
                    } finally {
                      if (keepDialogOpen) {
                        setState(() => submitting = false);
                      }
                    }
                  },
            child: submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Confirmar troca/devolucao'),
          ),
        ],
      ),
    ),
  );
}

Future<void> _confirmCancel(
  BuildContext context,
  WidgetRef ref,
  String sessionId,
  OwnerCashSessionSale sale,
) async {
  final reasonController = TextEditingController();
  final messenger = ScaffoldMessenger.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Cancelar venda'),
      content: TextField(
        controller: reasonController,
        decoration: const InputDecoration(labelText: 'Motivo obrigatório'),
        maxLines: 2,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Voltar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Confirmar cancelamento'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  final reason = reasonController.text.trim();
  if (reason.length < 3) {
    messenger.showSnackBar(const SnackBar(content: Text('Informe o motivo.')));
    return;
  }
  try {
    await ref
        .read(ownerApiServiceProvider)
        .cancelCashSessionSale(
          cashSessionId: sessionId,
          saleId: sale.id,
          reason: reason,
        );
    ref.invalidate(ownerCashSessionsProvider);
    ref.invalidate(ownerCashSessionDetailProvider(sessionId));
    messenger.showSnackBar(const SnackBar(content: Text('Venda cancelada.')));
  } on OwnerApiException catch (error) {
    messenger.showSnackBar(SnackBar(content: Text(error.message)));
  }
}
