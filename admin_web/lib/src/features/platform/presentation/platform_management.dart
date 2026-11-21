import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/platform_api.dart';
import 'platform_widgets.dart';
import 'platform_overview.dart';
import 'platform_cases.dart';

class PlatformTriagePage extends ConsumerStatefulWidget {
  const PlatformTriagePage({super.key});
  @override
  ConsumerState<PlatformTriagePage> createState() => _TriageState();
}

class _TriageState extends ConsumerState<PlatformTriagePage>
    with WidgetsBindingObserver {
  Timer? timer;
  bool visible = true;
  String? resource;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    timer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted &&
          visible &&
          ModalRoute.of(context)?.isCurrent != false &&
          resource != null) {
        ref.invalidate(platformResourceProvider(resource!));
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      visible = state == AppLifecycleState.resumed;
  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final location = platformLocation(context, '/support');
    final page = int.tryParse(location.queryParameters['page'] ?? '') ?? 1;
    final path = '/admin/triage?page=$page&pageSize=20';
    resource = path;
    final cap = ref.watch(platformCapabilitiesProvider).asData?.value;
    return PlatformPage(
      children: [
        PlatformHeader(
          title: 'Suporte da plataforma',
          subtitle: 'Problemas observados, por gravidade e tempo em aberto.',
          actions: [
            OutlinedButton(
              onPressed: () => platformNavigate(context, '/support/cases'),
              child: const Text('Chamados internos'),
            ),
            IconButton(
              tooltip: 'Atualizar problemas',
              onPressed: () => ref.invalidate(platformResourceProvider(path)),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        PlatformPanel(
          title: 'Precisa da sua atenção',
          child: PlatformResourceView(
            resource: path,
            builder: (data) => Column(
              children: [
                if (platformItems(data['items']).isEmpty)
                  const PlatformState(
                    message:
                        'Nenhum problema observado nesta seleção. Ausência de eventos não comprova saúde dos aparelhos.',
                  ),
                for (final item in platformItems(data['items']))
                  PlatformRow(
                    title:
                        '${platformStatus(platformText(item['severity']))} · ${platformText(item['companyName'])}',
                    subtitle:
                        '${platformText(item['reason'])}\nDesde ${platformDate(item['occurredAt'])}',
                    trailing: Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: () => platformNavigate(
                            context,
                            platformText(item['href'], '/companies'),
                          ),
                          child: const Text('Investigar'),
                        ),
                        if (platformAllowsAction(
                          cap,
                          'admin.support.manage',
                          companyId: platformText(item['companyId'], ''),
                        ))
                          OutlinedButton(
                            onPressed: () => showPlatformCaseCreation(
                              context,
                              companyId: platformText(item['companyId'], ''),
                              companyName: platformText(item['companyName']),
                              evidence: item['evidence'] == null
                                  ? null
                                  : platformMap(item['evidence']),
                            ),
                            child: const Text('Criar ou localizar chamado'),
                          ),
                      ],
                    ),
                  ),
                PlatformPager(
                  page: page,
                  total: platformInt(data['total']),
                  pageSize: 20,
                  onPage: (p) => platformNavigate(context, '/support?page=$p'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class PlatformCommercialPage extends ConsumerWidget {
  const PlatformCommercialPage({super.key, this.companyId});
  final String? companyId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (companyId != null) return _CompanyCommercial(companyId: companyId!);
    final location = platformLocation(context, '/commercial');
    final q = location.queryParameters;
    final page = int.tryParse(q['page'] ?? '') ?? 1;
    final invoice = q['tab'] == 'invoices';
    final path = platformResource(
      invoice ? '/admin/invoices' : '/admin/subscriptions',
      {
        'page': '$page',
        'pageSize': '20',
        'search': q['search'],
        if (invoice) ...{
          'status': q['status'],
          'startDate': q['startDate'],
          'endDate': q['endDate'],
        } else ...{
          'status': q['status'],
          'hasProviderSubscription': q['hasProviderSubscription'],
        },
      },
    );
    void filter(Map<String, String?> changes) => platformNavigate(
      context,
      platformResource('/commercial', {...q, 'page': '1', ...changes}),
    );
    return PlatformPage(
      storageKey: path,
      children: [
        const PlatformHeader(
          title: 'Assinaturas e cobranças',
          subtitle:
              'Contratos, vencimentos e pagamentos confirmados da plataforma.',
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Assinaturas'),
              selected: !invoice,
              onSelected: (_) => filter({'tab': null, 'status': null}),
            ),
            ChoiceChip(
              label: const Text('Cobranças'),
              selected: invoice,
              onSelected: (_) => filter({'tab': 'invoices', 'status': null}),
            ),
            if (invoice) ...[
              FilterChip(
                label: const Text('Pagas'),
                selected: q['status'] == 'paid',
                onSelected: (v) => filter({'status': v ? 'paid' : null}),
              ),
              FilterChip(
                label: const Text('Vencidas'),
                selected: q['status'] == 'overdue',
                onSelected: (v) => filter({'status': v ? 'overdue' : null}),
              ),
            ],
            OutlinedButton(
              onPressed: () => platformNavigate(context, '/plans'),
              child: const Text('Matriz de planos'),
            ),
          ],
        ),
        if (!invoice)
          TextFormField(
            key: ValueKey(q['search']),
            initialValue: q['search'],
            decoration: const InputDecoration(
              labelText: 'Buscar empresa',
              suffixIcon: Icon(Icons.search),
            ),
            onFieldSubmitted: (value) => filter({'search': value.trim()}),
          ),
        PlatformPanel(
          title: invoice ? 'Cobranças registradas' : 'Empresas e assinaturas',
          child: PlatformResourceView(
            resource: path,
            builder: (data) {
              final items = platformItems(data['items']);
              return Column(
                children: [
                  if (items.isEmpty)
                    const PlatformState(
                      message: 'Nenhum registro para os filtros selecionados.',
                    ),
                  for (final item in items)
                    PlatformRow(
                      title: platformText(
                        item['companyName'] ??
                            platformMap(item['company'])['name'],
                      ),
                      subtitle: invoice
                          ? '${platformText(item['status'])} · ${platformCurrency(item['amountCents'], item['currency'])}\nVencimento ${platformDate(item['dueAt'])} · Pagamento ${platformDate(item['paidAt'])}'
                          : '${platformText(item['plan'] ?? platformMap(item['license'])['plan'], 'Sem plano')} · ${platformText(item['status'] ?? platformMap(item['license'])['status'])}',
                      trailing: OutlinedButton(
                        onPressed: () => platformNavigate(
                          context,
                          '/companies/${Uri.encodeComponent(platformText(item['companyId'] ?? item['id'], ''))}/commercial',
                        ),
                        child: const Text('Abrir empresa'),
                      ),
                    ),
                  PlatformPager(
                    page: page,
                    total: platformTotal(data),
                    pageSize: 20,
                    onPage: (p) => filter({'page': '$p'}),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CompanyCommercial extends ConsumerWidget {
  const _CompanyCommercial({required this.companyId});
  final String companyId;
  @override
  Widget build(BuildContext context, WidgetRef ref) => PlatformPage(
    children: [
      PlatformHeader(
        title: 'Assinatura e cobranças',
        subtitle: 'Estado administrativo e evidências do provedor.',
        actions: [
          OutlinedButton(
            onPressed: () =>
                platformNavigate(context, '/companies/$companyId/operations'),
            child: const Text('Operações permitidas'),
          ),
        ],
      ),
      PlatformPanel(
        title: 'Situação da assinatura',
        child: PlatformResourceView(
          resource: '/admin/companies/$companyId/billing/status',
          builder: (data) {
            final license = platformMap(data['license']);
            final billing = platformMap(data['billing']);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PlatformRow(
                  title: platformText(license['plan'], 'Sem licença'),
                  subtitle:
                      '${platformText(license['status'])}\nVálida até ${platformDate(license['expiresAt'])}',
                ),
                PlatformRow(
                  title: 'Cobrança',
                  subtitle:
                      '${platformText(billing['provider'], 'Sem provedor')} · ${platformText(billing['billingSubscriptionStatus'])}\nPróxima cobrança ${platformDate(billing['nextPaymentDate'])}',
                ),
              ],
            );
          },
        ),
      ),
      PlatformPanel(
        title: 'Eventos de cobrança',
        child: PlatformResourceView(
          resource:
              '/admin/companies/$companyId/billing/events?page=1&pageSize=20',
          builder: (data) => Column(
            children: [
              if (platformItems(data['items']).isEmpty)
                const PlatformState(
                  message: 'Nenhum evento de cobrança retornado.',
                ),
              for (final row in platformItems(data['items']))
                PlatformRow(
                  title: platformText(
                    row['eventType'] ?? row['type'] ?? row['status'],
                  ),
                  subtitle: platformDate(row['createdAt']),
                ),
            ],
          ),
        ),
      ),
      PlatformPanel(
        title: 'Histórico administrativo',
        child: PlatformResourceView(
          resource:
              '/admin/companies/$companyId/billing/audit-logs?page=1&pageSize=20',
          builder: (data) => Column(
            children: [
              if (platformItems(data['items']).isEmpty)
                const PlatformState(
                  message: 'Nenhuma alteração administrativa retornada.',
                ),
              for (final row in platformItems(data['items']))
                PlatformRow(
                  title: platformText(row['action']),
                  subtitle: platformDate(row['createdAt']),
                ),
            ],
          ),
        ),
      ),
    ],
  );
}

class PlatformUsagePage extends ConsumerWidget {
  const PlatformUsagePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = platformPeriod(
      platformLocation(context, '/usage').queryParameters,
    );
    final path = platformResource('/admin/usage', p);
    return PlatformPage(
      children: [
        PlatformHeader(
          title: 'Uso da plataforma',
          subtitle:
              'Adoção observada nos eventos reais enviados pelos aplicativos.',
          actions: [
            OutlinedButton.icon(
              onPressed: () => selectPlatformPeriod(context, p),
              icon: const Icon(Icons.date_range),
              label: const Text('Período'),
            ),
          ],
        ),
        PlatformResourceView(
          resource: path,
          builder: (data) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PlatformPanel(
                title: 'Empresas com eventos no período',
                child: Text(
                  '${platformInt(data['activeCompanies'])}',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
              ),
              const SizedBox(height: 16),
              Text(platformText(data['definition'])),
              const SizedBox(height: 16),
              PlatformPanel(
                title: 'Eventos observados',
                child: Column(
                  children: [
                    if (platformItems(data['events']).isEmpty)
                      const PlatformState(
                        message:
                            'Ainda não há eventos de uso para este período.',
                      ),
                    for (final row in platformItems(data['events']))
                      PlatformRow(
                        title: platformText(row['name']),
                        subtitle: '${platformInt(row['count'])} eventos',
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              PlatformPanel(
                title: 'Versões com telemetria',
                child: Column(
                  children: [
                    for (final row in platformItems(data['versions']))
                      PlatformRow(
                        title: platformText(row['appVersion']),
                        subtitle: '${platformInt(row['count'])} eventos',
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
