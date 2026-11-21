import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/platform_api.dart';
import 'platform_widgets.dart';

class PlatformCompanyPeople extends ConsumerWidget {
  const PlatformCompanyPeople({super.key, required this.companyId});
  final String companyId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cap = ref.watch(platformCapabilitiesProvider).asData?.value;
    final canManage =
        platformAllowsAction(cap, 'access.block', companyId: companyId) ||
        platformAllowsAction(cap, 'access.reactivate', companyId: companyId);
    return PlatformPage(
      children: [
        PlatformHeader(
          title: 'Pessoas e acessos',
          subtitle: 'Usuários e perfis operacionais vinculados à empresa.',
          actions: [
            if (canManage)
              OutlinedButton(
                onPressed: () => platformNavigate(
                  context,
                  '/companies/$companyId/operations',
                ),
                child: const Text('Gerenciar acesso'),
              ),
          ],
        ),
        PlatformPanel(
          title: 'Funcionários',
          child: PlatformResourceView(
            resource: '/admin/companies/$companyId/access-summary',
            builder: (data) => Column(
              children: [
                if (platformItems(data['employees']).isEmpty)
                  const PlatformState(
                    message: 'Nenhum perfil operacional retornado.',
                  ),
                for (final row in platformItems(data['employees']))
                  PlatformRow(
                    title: platformText(row['name']),
                    subtitle:
                        '${platformText(row['employeeRole'] ?? row['role'])} · ${platformText(row['status'])}\n${platformText(row['email'], 'Sem e-mail')}',
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class PlatformCompanySync extends ConsumerWidget {
  const PlatformCompanySync({super.key, required this.companyId});
  final String companyId;
  @override
  Widget build(BuildContext context, WidgetRef ref) => PlatformPage(
    children: [
      PlatformHeader(
        title: 'Sincronização da empresa',
        subtitle:
            'Eventos e conflitos observados no servidor. Sem acesso à fila local enquanto o aparelho não enviar diagnóstico.',
        actions: [
          OutlinedButton(
            onPressed: () =>
                platformNavigate(context, '/companies/$companyId/operations'),
            child: const Text('Diagnósticos permitidos'),
          ),
        ],
      ),
      PlatformPanel(
        title: 'Eventos recentes',
        child: PlatformResourceView(
          resource:
              '/admin/sync/companies/$companyId/events?page=1&pageSize=20',
          builder: (data) => Column(
            children: [
              if (platformItems(data['items']).isEmpty)
                const PlatformState(message: 'Nenhum evento nesta seleção.'),
              for (final row in platformItems(data['items']))
                PlatformRow(
                  title:
                      '${platformText(row['entity'])} · ${platformText(row['operation'])}',
                  subtitle:
                      '${platformText(row['status'])} · ${platformDate(row['occurredAt'] ?? row['createdAt'])}',
                  trailing: TextButton(
                    onPressed: () =>
                        _showEvent(context, ref, platformText(row['id'], '')),
                    child: const Text('Ver evidência'),
                  ),
                ),
            ],
          ),
        ),
      ),
      PlatformPanel(
        title: 'Conflitos abertos',
        child: PlatformResourceView(
          resource:
              '/admin/sync/companies/$companyId/conflicts?page=1&pageSize=20&status=OPEN',
          builder: (data) => Column(
            children: [
              if (platformItems(data['items']).isEmpty)
                const PlatformState(
                  message: 'Nenhum conflito aberto retornado.',
                ),
              for (final row in platformItems(data['items']))
                PlatformRow(
                  title: platformText(row['code']),
                  subtitle:
                      '${platformText(row['message'])}\n${platformDate(row['createdAt'])}',
                ),
            ],
          ),
        ),
      ),
    ],
  );
  Future<void> _showEvent(
    BuildContext context,
    WidgetRef ref,
    String id,
  ) async {
    try {
      final response = await ref
          .read(platformApiProvider)
          .get('/admin/sync/events/$id');
      if (!context.mounted) return;
      final event = platformMap(
        response['event'] ?? response['item'] ?? response,
      );
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Evidência de sincronização'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: SelectableText(
                'Entidade: ${platformText(event['entity'])}\nOperação: ${platformText(event['operation'])}\nSituação: ${platformText(event['status'])}\nCódigo: ${platformText(event['rejectionCode'], 'Sem código de erro')}\n${platformText(event['rejectionMessage'], 'Sem mensagem adicional')}',
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Fechar'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(platformError(error))));
      }
    }
  }
}
