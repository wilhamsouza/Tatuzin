import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/platform_api.dart';
import 'platform_widgets.dart';
import 'platform_search.dart';

class PlatformRegistryPage extends ConsumerWidget {
  const PlatformRegistryPage({super.key, required this.kind, this.companyId});
  final String kind;
  final String? companyId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cap = ref.watch(platformCapabilitiesProvider).asData?.value;
    final section = platformItems(cap?['sections'])
        .where(
          (s) => s['key'] == kind || (kind == 'audit' && s['key'] == 'audit'),
        )
        .firstOrNull;
    final selectedCompany =
        companyId ??
        platformLocation(context, '/').queryParameters['companyId'];
    if (section?['globalAllowed'] == false && selectedCompany == null) {
      return PlatformPage(
        children: [
          const PlatformHeader(
            title: 'Escolha uma empresa',
            subtitle: 'Seu acesso está limitado às empresas autorizadas.',
          ),
          FilledButton.icon(
            onPressed: () async {
              final company = await choosePlatformCompany(context);
              if (!context.mounted || company == null) return;
              final id = platformText(
                company['companyId'] ?? company['id'],
                '',
              );
              platformNavigate(
                context,
                kind == 'sync'
                    ? '/companies/$id/sync'
                    : '/${kind == 'devices' ? 'devices' : 'audit'}?companyId=$id',
              );
            },
            icon: const Icon(Icons.apartment_outlined),
            label: const Text('Escolher empresa'),
          ),
        ],
      );
    }
    final route = kind == 'sync'
        ? '/sync'
        : kind == 'devices'
        ? '/devices'
        : '/audit';
    final location = platformLocation(context, route);
    final q = location.queryParameters;
    final page = int.tryParse(q['page'] ?? '') ?? 1;
    final endpoint = kind == 'sync'
        ? '/admin/sync/companies'
        : kind == 'devices'
        ? '/admin/devices'
        : '/admin/audit';
    final path = platformResource(endpoint, {
      'page': '$page',
      'pageSize': '20',
      'search': q['search'],
      'companyId': companyId ?? q['companyId'],
      if (kind == 'sync') 'status': q['status'] ?? 'requires_review',
      if (kind == 'audit') 'action': q['action'],
    });
    void filter(Map<String, String?> change) => platformNavigate(
      context,
      platformResource(location.path, {...q, 'page': '1', ...change}),
    );
    return PlatformPage(
      storageKey: path,
      children: [
        PlatformHeader(
          title: kind == 'sync'
              ? 'Sincronização'
              : kind == 'devices'
              ? 'Dispositivos e acessos'
              : 'Auditoria',
          subtitle: kind == 'sync'
              ? 'Investigue o que foi observado. Sem eventos recentes não significa aparelho conectado.'
              : kind == 'devices'
              ? 'Aparelhos registrados e suas evidências recentes de acesso.'
              : 'Alterações administrativas, responsáveis e contexto da empresa.',
          actions: [
            IconButton(
              tooltip: 'Atualizar lista',
              onPressed: () => ref.invalidate(platformResourceProvider(path)),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        TextFormField(
          key: ValueKey(q['search']),
          initialValue: q['search'],
          decoration: const InputDecoration(
            labelText: 'Pesquisar',
            suffixIcon: Icon(Icons.search),
          ),
          onFieldSubmitted: (value) => filter({'search': value.trim()}),
        ),
        if (kind == 'sync')
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in {
                'requires_review': 'Requer atenção',
                'all': 'Todas as empresas',
                'failed': 'Com falhas',
                'conflict': 'Com conflitos',
              }.entries)
                ChoiceChip(
                  label: Text(entry.value),
                  selected: (q['status'] ?? 'requires_review') == entry.key,
                  onSelected: (_) => filter({'status': entry.key}),
                ),
            ],
          ),
        PlatformPanel(
          title: 'Registros',
          child: PlatformResourceView(
            resource: path,
            builder: (data) {
              final rows = platformItems(data['items']);
              return Column(
                children: [
                  if (rows.isEmpty)
                    const PlatformState(
                      message: 'Nenhum registro nesta seleção.',
                    ),
                  for (final row in rows)
                    PlatformRow(
                      title: platformText(
                        kind == 'devices'
                            ? row['deviceLabel'] ?? row['maskedDeviceId']
                            : kind == 'audit'
                            ? row['action'] ?? row['eventType']
                            : row['companyName'],
                      ),
                      subtitle: kind == 'sync'
                          ? '${platformInt(row['failedCount'])} falhas · ${platformInt(row['openConflictCount'])} conflitos abertos\nÚltimo evento ${platformDate(row['lastEventAt'])}'
                          : kind == 'devices'
                          ? '${platformText(row['companyName'])} · ${platformText(row['userName'])}\n${platformText(row['appVersion'], 'Versão não informada')} · Atividade ${platformDate(row['lastSeenAt'])}'
                          : '${platformText(row['actorName'] ?? row['actorLabel'], 'Administrador')} · ${platformDate(row['createdAt'])}\n${platformText(row['companyName'], 'Sem empresa vinculada')}',
                      trailing:
                          row['companyId'] != null ||
                              row['targetCompanyId'] != null
                          ? OutlinedButton(
                              onPressed: () => platformNavigate(
                                context,
                                '/companies/${row['companyId'] ?? row['targetCompanyId']}${kind == 'sync'
                                    ? '/sync'
                                    : kind == 'devices'
                                    ? '/devices'
                                    : ''}',
                              ),
                              child: Text(
                                kind == 'sync' ? 'Investigar' : 'Abrir empresa',
                              ),
                            )
                          : null,
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
