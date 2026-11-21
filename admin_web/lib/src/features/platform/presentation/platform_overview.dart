import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/platform_api.dart';
import 'platform_widgets.dart';

class PlatformOverviewPage extends ConsumerStatefulWidget {
  const PlatformOverviewPage({super.key});
  @override
  ConsumerState<PlatformOverviewPage> createState() =>
      _PlatformOverviewPageState();
}

class _PlatformOverviewPageState extends ConsumerState<PlatformOverviewPage>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _visible = true;
  String? _resource;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (_visible &&
          mounted &&
          ModalRoute.of(context)?.isCurrent != false &&
          _resource != null) {
        ref.invalidate(platformResourceProvider(_resource!));
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _visible = state == AppLifecycleState.resumed;
  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = platformLocation(context, '/dashboard').queryParameters;
    final period = platformPeriod(query);
    final resource = platformResource('/admin/overview', period);
    _resource = resource;
    final data = ref.watch(platformResourceProvider(resource));
    return PlatformPage(
      storageKey: 'overview-$resource',
      children: [
        PlatformHeader(
          title: 'Visão geral da plataforma',
          subtitle: 'Seu negócio, a operação e o que precisa de atenção.',
          actions: [
            OutlinedButton.icon(
              onPressed: () => selectPlatformPeriod(context, period),
              icon: const Icon(Icons.date_range_outlined),
              label: Text('${period['startDate']} a ${period['endDate']}'),
            ),
            IconButton(
              tooltip: 'Atualizar visão geral',
              onPressed: () =>
                  ref.invalidate(platformResourceProvider(resource)),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        data.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: LinearProgressIndicator(),
          ),
          error: (error, _) => PlatformState(
            error: true,
            message: platformError(error),
            onRetry: () => ref.invalidate(platformResourceProvider(resource)),
          ),
          data: (data) => _OverviewContent(
            data: data,
            period: period,
            onRefresh: () => ref.invalidate(platformResourceProvider(resource)),
          ),
        ),
      ],
    );
  }
}

Map<String, String> platformPeriod(Map<String, String> query) {
  final now = DateTime.now().toUtc();
  return {
    'startDate':
        query['startDate'] ??
        now
            .subtract(const Duration(days: 29))
            .toIso8601String()
            .substring(0, 10),
    'endDate': query['endDate'] ?? now.toIso8601String().substring(0, 10),
  };
}

Future<void> selectPlatformPeriod(
  BuildContext context,
  Map<String, String> period,
) async {
  final now = DateTime.now();
  final result = await showDateRangePicker(
    context: context,
    firstDate: DateTime(2020),
    lastDate: DateTime(now.year + 1, 12, 31),
    initialDateRange: DateTimeRange(
      start: DateTime.tryParse(period['startDate'] ?? '') ?? now,
      end: DateTime.tryParse(period['endDate'] ?? '') ?? now,
    ),
    helpText: 'Selecione até 90 dias',
  );
  if (!context.mounted || result == null) return;
  if (result.end.difference(result.start).inDays > 89) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Escolha um período de até 90 dias.')),
    );
    return;
  }
  final location = platformLocation(context, '/dashboard');
  platformNavigate(
    context,
    Uri(
      path: location.path,
      queryParameters: {
        ...location.queryParameters,
        'startDate': result.start.toIso8601String().substring(0, 10),
        'endDate': result.end.toIso8601String().substring(0, 10),
      },
    ).toString(),
  );
}

class _OverviewContent extends StatelessWidget {
  const _OverviewContent({
    required this.data,
    required this.period,
    required this.onRefresh,
  });
  final PlatformMap data;
  final Map<String, String> period;
  final VoidCallback onRefresh;
  @override
  Widget build(BuildContext context) {
    final companies = platformMap(data['companies']);
    final subscriptions = platformMap(data['subscriptions']);
    final billing = platformMap(data['billing']);
    final operations = platformMap(data['operations']);
    final support = platformMap(data['support']);
    final audit = platformMap(data['audit']);
    final issues = platformItems(operations['items']);
    Widget metric(
      String title,
      PlatformMap source,
      String key,
      IconData icon,
      String route,
      String detail, {
      bool money = false,
    }) => PlatformMetric(
      title: title,
      value: source['available'] == true
          ? (money ? platformMoney(source[key]) : '${platformInt(source[key])}')
          : '—',
      detail: source['available'] == true
          ? detail
          : platformUnavailable(source),
      icon: icon,
      onTap: source['available'] == true
          ? () => platformNavigate(context, route)
          : null,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Atualizado ${platformDate(data['generatedAt'])} · ${platformText(platformMap(data['period'])['timezone'], 'UTC')}\nAtualização automática a cada minuto enquanto esta tela estiver visível.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 18),
        PlatformGrid(
          children: [
            metric(
              'Empresas cadastradas',
              companies,
              'total',
              Icons.apartment_outlined,
              '/companies',
              'Total de empresas no seu escopo',
            ),
            metric(
              'Assinaturas pagas ativas',
              subscriptions,
              'activePaid',
              Icons.workspace_premium_outlined,
              '/commercial?hasProviderSubscription=true&status=ACTIVE',
              'Planos pagos com assinatura registrada',
            ),
            metric(
              'Cobranças pagas no período',
              billing,
              'paidAmountCents',
              Icons.payments_outlined,
              Uri(
                path: '/commercial',
                queryParameters: {
                  ...period,
                  'tab': 'invoices',
                  'status': 'paid',
                },
              ).toString(),
              'Pagamentos confirmados em BRL',
              money: true,
            ),
            metric(
              'Cobranças vencidas',
              billing,
              'overdueCount',
              Icons.receipt_long_outlined,
              '/commercial?tab=invoices&status=overdue',
              'Em aberto após o vencimento',
            ),
            metric(
              'Empresas com problemas',
              operations,
              'problemCompanies',
              Icons.monitor_heart_outlined,
              '/support',
              'Evidências operacionais que precisam de atenção',
            ),
            metric(
              'Chamados abertos',
              support,
              'openCount',
              Icons.support_agent_outlined,
              '/support/cases?status=active',
              'Abertos, em atendimento ou aguardando',
            ),
          ],
        ),
        const SizedBox(height: 24),
        PlatformPanel(
          title: 'Precisa da sua atenção',
          subtitle:
              'Priorize o impacto. Abra a empresa para investigar o contexto.',
          action: TextButton(
            onPressed: () => platformNavigate(context, '/support'),
            child: const Text('Ver todos os problemas'),
          ),
          child: operations['available'] != true
              ? PlatformState(
                  message: platformUnavailable(operations),
                  error: true,
                  onRetry: onRefresh,
                )
              : issues.isEmpty
              ? const PlatformState(
                  message:
                      'Nenhum problema ativo foi identificado nas fontes disponíveis.',
                )
              : Column(
                  children: [
                    for (final issue in issues)
                      PlatformRow(
                        title: platformText(issue['companyName']),
                        subtitle:
                            '${platformStatus(platformText(issue['severity']))} · ${platformText(issue['reason'])}\n${platformDate(issue['occurredAt'])}',
                        leading: const Icon(Icons.info_outline),
                        trailing: OutlinedButton(
                          onPressed: () => platformNavigate(
                            context,
                            platformText(
                              issue['href'],
                              '/companies/${issue['companyId']}/support',
                            ),
                          ),
                          child: const Text('Investigar'),
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 20),
        PlatformGrid(
          minWidth: 420,
          children: [
            PlatformPanel(
              title: 'Novas empresas',
              subtitle: 'Cadastros no período selecionado.',
              child: companies['available'] == true
                  ? PlatformSeries(
                      data: platformItems(companies['series']),
                      valueKey: 'count',
                      label: 'empresas',
                    )
                  : PlatformState(
                      message: platformUnavailable(companies),
                      onRetry: onRefresh,
                    ),
            ),
            PlatformPanel(
              title: 'Pagamentos confirmados',
              subtitle:
                  'Cobranças da plataforma pagas em BRL. Não inclui vendas dos lojistas.',
              child: billing['available'] == true
                  ? PlatformSeries(
                      data: platformItems(billing['series']),
                      valueKey: 'amountCents',
                      label: 'pagamentos',
                      money: true,
                    )
                  : PlatformState(
                      message: platformUnavailable(billing),
                      onRetry: onRefresh,
                    ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        PlatformGrid(
          minWidth: 420,
          children: [
            PlatformPanel(
              title: 'Seus chamados',
              subtitle: 'Atendimentos sob sua responsabilidade.',
              action: TextButton(
                onPressed: () =>
                    platformNavigate(context, '/support/cases?mine=true'),
                child: const Text('Ver todos'),
              ),
              child: support['available'] == true
                  ? PlatformCaseRows(items: platformItems(support['mine']))
                  : PlatformState(
                      message: platformUnavailable(support),
                      onRetry: onRefresh,
                    ),
            ),
            PlatformPanel(
              title: 'Últimas ações administrativas',
              subtitle: 'Registro das alterações e de seus responsáveis.',
              action: TextButton(
                onPressed: () => platformNavigate(context, '/audit'),
                child: const Text('Abrir auditoria'),
              ),
              child: audit['available'] != true
                  ? PlatformState(
                      message: platformUnavailable(audit),
                      onRetry: onRefresh,
                    )
                  : platformItems(audit['items']).isEmpty
                  ? const PlatformState(
                      message: 'Nenhuma ação administrativa recente.',
                    )
                  : Column(
                      children: [
                        for (final item in platformItems(audit['items']))
                          PlatformRow(
                            title: platformText(
                              item['action'] ??
                                  item['eventType'] ??
                                  item['type'],
                            ),
                            subtitle:
                                '${platformText(item['actorName'] ?? item['actorLabel'], 'Administrador')} · ${platformDate(item['createdAt'])}',
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ],
    );
  }
}

String platformUnavailable(PlatformMap section) =>
    section['reason'] == 'FORBIDDEN'
    ? 'Sem permissão para esta seção.'
    : 'Fonte indisponível. Os demais dados continuam acessíveis.';

class PlatformSeries extends StatelessWidget {
  const PlatformSeries({
    super.key,
    required this.data,
    required this.valueKey,
    required this.label,
    this.money = false,
  });
  final List<PlatformMap> data;
  final String valueKey;
  final String label;
  final bool money;
  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const PlatformState(
        message: 'Não há série disponível para este período.',
      );
    }
    final maxValue = data.fold<int>(
      0,
      (result, row) => math.max(result, platformInt(row[valueKey])),
    );
    if (maxValue == 0) {
      return const PlatformState(
        message: 'Nenhum movimento registrado neste período.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Total: ${money ? platformMoney(data.fold<int>(0, (sum, row) => sum + platformInt(row[valueKey]))) : data.fold<int>(0, (sum, row) => sum + platformInt(row[valueKey]))}',
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final row in data)
                Tooltip(
                  message:
                      '${platformText(row['date'])}: ${money ? platformMoney(row[valueKey]) : platformInt(row[valueKey])} $label',
                  child: Semantics(
                    label:
                        '${platformText(row['date'])}: ${money ? platformMoney(row[valueKey]) : platformInt(row[valueKey])} $label',
                    child: SizedBox(
                      width: 55,
                      height: MediaQuery.textScalerOf(context).scale(1) > 1.5
                          ? 230
                          : 180,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Container(
                              width: 24,
                              height: math.max(
                                2.0,
                                platformInt(row[valueKey]) / maxValue * 110,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(4),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              platformText(
                                row['date'],
                                '',
                              ).replaceFirst(RegExp(r'^\d{4}-'), ''),
                              style: Theme.of(context).textTheme.labelSmall,
                              maxLines: 2,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Role para percorrer as datas. Consulte os valores nas barras com toque ou leitor de tela.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class PlatformCaseRows extends StatelessWidget {
  const PlatformCaseRows({super.key, required this.items});
  final List<PlatformMap> items;
  @override
  Widget build(BuildContext context) => items.isEmpty
      ? const PlatformState(message: 'Nenhum chamado nesta seleção.')
      : Column(
          children: [
            for (final item in items)
              PlatformRow(
                title: platformText(item['subject']),
                subtitle:
                    '${platformText(item['companyName'])} · ${platformStatus(platformText(item['status']))}\n${platformStatus(platformText(item['priority']))} · ${platformText(platformMap(item['assignee'])['name'], 'Sem responsável')} · ${platformDate(item['updatedAt'])}',
                trailing: OutlinedButton(
                  onPressed: () => platformNavigate(
                    context,
                    '/support/cases/${Uri.encodeComponent(platformText(item['id'], ''))}',
                  ),
                  child: const Text('Abrir chamado'),
                ),
              ),
          ],
        );
}
