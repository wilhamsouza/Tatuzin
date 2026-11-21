import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/platform_api.dart';
import 'platform_widgets.dart';

class PlatformCompaniesPage extends ConsumerWidget {
  const PlatformCompaniesPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = platformLocation(context, '/companies');
    final q = location.queryParameters;
    final page = int.tryParse(q['page'] ?? '') ?? 1;
    final path = platformResource('/admin/platform-companies', {
      'page': '$page',
      'pageSize': '20',
      'search': q['search'],
      'sortBy': q['sortBy'] ?? 'createdAt',
      'sortDirection': q['sortDirection'] ?? 'desc',
      'licenseStatus': q['licenseStatus'],
      'isActive': q['isActive'],
    });
    void filter(Map<String, String?> changes) => platformNavigate(
      context,
      platformResource('/companies', {...q, 'page': '1', ...changes}),
    );
    return PlatformPage(
      storageKey: path,
      children: [
        const PlatformHeader(
          title: 'Empresas',
          subtitle:
              'Encontre a empresa e mantenha o contexto até resolver o atendimento.',
        ),
        TextFormField(
          key: ValueKey(q['search']),
          initialValue: q['search'],
          decoration: const InputDecoration(
            labelText: 'Buscar nome, identificação ou documento',
            suffixIcon: Icon(Icons.search),
          ),
          onFieldSubmitted: (v) => filter({'search': v.trim()}),
        ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<String>(
                key: ValueKey(q['licenseStatus']),
                initialValue: q['licenseStatus'] ?? 'all',
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Licença'),
                items: [
                  for (final entry in {
                    'all': 'Todas',
                    'active': 'Ativa',
                    'trial': 'Teste',
                    'expired': 'Vencida',
                    'suspended': 'Suspensa',
                    'without_license': 'Sem licença',
                  }.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                ],
                onChanged: (v) =>
                    filter({'licenseStatus': v == 'all' ? null : v}),
              ),
            ),
            SizedBox(
              width: 230,
              child: DropdownButtonFormField<String>(
                key: ValueKey(q['sortBy']),
                initialValue: q['sortBy'] ?? 'createdAt',
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Ordenar por'),
                items: const [
                  DropdownMenuItem(value: 'createdAt', child: Text('Cadastro')),
                  DropdownMenuItem(
                    value: 'updatedAt',
                    child: Text('Atualização'),
                  ),
                  DropdownMenuItem(value: 'name', child: Text('Nome')),
                ],
                onChanged: (v) => filter({'sortBy': v}),
              ),
            ),
            FilterChip(
              label: const Text('Ordem crescente'),
              selected: q['sortDirection'] == 'asc',
              onSelected: (v) => filter({'sortDirection': v ? 'asc' : 'desc'}),
            ),
            TextButton(
              onPressed: () => platformNavigate(context, '/companies'),
              child: const Text('Limpar filtros'),
            ),
          ],
        ),
        PlatformPanel(
          title: 'Empresas cadastradas',
          child: PlatformResourceView(
            resource: path,
            builder: (data) => Column(
              children: [
                if (platformItems(data['items']).isEmpty)
                  const PlatformState(message: 'Nenhuma empresa encontrada.'),
                for (final company in platformItems(data['items']))
                  PlatformRow(
                    title: platformText(company['name']),
                    subtitle:
                        '${platformText(company['slug'])}\n${platformText(platformMap(company['license'])['plan'], 'Sem plano')} · ${platformText(platformMap(company['license'])['status'], 'Sem licença')}',
                    trailing: OutlinedButton(
                      onPressed: () => platformNavigate(
                        context,
                        '/companies/${company['id']}',
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
            ),
          ),
        ),
      ],
    );
  }
}

class PlatformCompanyWorkspace extends ConsumerWidget {
  const PlatformCompanyWorkspace({
    super.key,
    required this.companyId,
    required this.child,
  });
  final String companyId;
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cap = ref.watch(platformCapabilitiesProvider).asData?.value;
    final current = platformLocation(context, '/companies/$companyId').path;
    final tabs = <(String, String, String)>[
      ('Resumo', '', 'companies'),
      ('Suporte', '/support', 'support'),
      ('Pessoas e acessos', '/users', 'companies'),
      ('Dispositivos', '/devices', 'devices'),
      ('Sincronização', '/sync', 'sync'),
      ('Assinatura e cobranças', '/commercial', 'billing'),
      ('Histórico', '/history', 'audit'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PlatformResourceView(
          resource: '/admin/companies/$companyId',
          builder: (data) {
            final c = platformMap(data['company']);
            final l = platformMap(c['license'] ?? data['license']);
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      platformText(c['name']),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${platformText(c['slug'])} · ${platformText(l['plan'], 'Sem plano')} · ${platformText(l['status'], 'Sem licença')}',
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      'Identificação: $companyId',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final t in tabs)
                if (platformAllowsSection(cap, t.$3))
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(t.$1),
                      selected: current == '/companies/$companyId${t.$2}',
                      onSelected: (_) => platformNavigate(
                        context,
                        '/companies/$companyId${t.$2}',
                      ),
                    ),
                  ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(child: child),
      ],
    );
  }
}

class PlatformCompanyOverview extends ConsumerWidget {
  const PlatformCompanyOverview({super.key, required this.companyId});
  final String companyId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cap = ref.watch(platformCapabilitiesProvider).asData?.value;
    return PlatformPage(
      children: [
        const PlatformHeader(
          title: 'Resumo da empresa',
          subtitle: 'Consulte as evidências e escolha o próximo passo.',
        ),
        if (platformAllowsSection(cap, 'support'))
          PlatformPanel(
            title: 'Problemas observados',
            child: PlatformResourceView(
              resource: '/admin/triage?companyId=$companyId',
              builder: (data) => Column(
                children: [
                  if (platformItems(data['items']).isEmpty)
                    const PlatformState(
                      message: 'Nenhum problema observado nesta seleção.',
                    ),
                  for (final issue in platformItems(data['items']))
                    PlatformRow(
                      title: platformText(issue['reason']),
                      subtitle: 'Desde ${platformDate(issue['occurredAt'])}',
                      trailing: TextButton(
                        onPressed: () => platformNavigate(
                          context,
                          '/companies/$companyId/sync',
                        ),
                        child: const Text('Investigar'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        PlatformGrid(
          children: [
            if (platformAllowsSection(cap, 'support'))
              PlatformMetric(
                title: 'Atendimento',
                value: 'Suporte',
                detail: 'Chamados e acompanhamento desta empresa',
                icon: Icons.support_agent_outlined,
                onTap: () =>
                    platformNavigate(context, '/companies/$companyId/support'),
              ),
            if (platformAllowsSection(cap, 'sync'))
              PlatformMetric(
                title: 'Sincronização',
                value: 'Investigar',
                detail: 'Eventos, conflitos e evidências dos dispositivos',
                icon: Icons.sync_outlined,
                onTap: () =>
                    platformNavigate(context, '/companies/$companyId/sync'),
              ),
            if (platformAllowsSection(cap, 'billing'))
              PlatformMetric(
                title: 'Assinatura',
                value: 'Consultar',
                detail: 'Licença, cobranças e eventos do provedor',
                icon: Icons.receipt_long_outlined,
                onTap: () => platformNavigate(
                  context,
                  '/companies/$companyId/commercial',
                ),
              ),
          ],
        ),
        PlatformPanel(
          title: 'Ações e contexto',
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              OutlinedButton(
                onPressed: () => platformNavigate(
                  context,
                  '/companies/$companyId/operations',
                ),
                child: const Text('Operações administrativas'),
              ),
              if (platformAllowsSection(cap, 'devices'))
                OutlinedButton(
                  onPressed: () => platformNavigate(
                    context,
                    '/companies/$companyId/sessions',
                  ),
                  child: const Text('Sessões'),
                ),
              if (platformAllowsSection(cap, 'support'))
                OutlinedButton(
                  onPressed: () => platformNavigate(
                    context,
                    '/companies/$companyId/diagnostics',
                  ),
                  child: const Text('Diagnóstico detalhado'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
