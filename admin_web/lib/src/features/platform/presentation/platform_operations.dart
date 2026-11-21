import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/admin_providers.dart';
import '../data/platform_api.dart';
import 'platform_widgets.dart';

const _actions = <String, String>{
  'session.revoke': 'Revogar sessão',
  'access.block': 'Bloquear acesso',
  'access.reactivate': 'Reativar acesso',
  'license.extend': 'Prorrogar licença',
  'license.suspend': 'Suspender licença',
  'license.reactivate': 'Reativar licença',
  'billing.refresh': 'Atualizar cobrança',
  'device.diagnostics': 'Solicitar diagnóstico do aparelho',
};

class PlatformOperationsPage extends ConsumerStatefulWidget {
  const PlatformOperationsPage({super.key, required this.companyId});
  final String companyId;
  @override
  ConsumerState<PlatformOperationsPage> createState() => _OperationsState();
}

class _OperationsState extends ConsumerState<PlatformOperationsPage> {
  final reason = TextEditingController();
  final confirmation = TextEditingController();
  String? action;
  String? target;
  int days = 1;
  bool busy = false;
  PlatformMap? preview;
  PlatformMap? result;
  String? error;
  String requestKey = platformRequestKey();
  @override
  void dispose() {
    reason.dispose();
    confirmation.dispose();
    super.dispose();
  }

  void invalidate() {
    setState(() {
      preview = null;
      result = null;
      error = null;
      confirmation.clear();
      requestKey = platformRequestKey();
    });
  }

  Future<void> run(bool execute) async {
    if (busy || action == null) return;
    if (reason.text.trim().length < 12) {
      setState(() => error = 'Descreva o motivo com pelo menos 12 caracteres.');
      return;
    }
    if (execute &&
        confirmation.text.trim() != preview?['expectedConfirmationText']) {
      setState(() => error = 'Digite exatamente o texto solicitado.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final data = await ref
          .read(platformApiProvider)
          .post(
            '/admin/operations/${execute ? 'execute' : 'preview'}',
            execute
                ? {
                    'previewId': preview!['previewId'],
                    'confirmationText': confirmation.text.trim(),
                    'idempotencyKey': requestKey,
                  }
                : {
                    'companyId': widget.companyId,
                    'action': action,
                    'reason': reason.text.trim(),
                    if (action == 'license.extend') 'days': days,
                    if (target != null) 'targetId': target,
                  },
          );
      if (!mounted) return;
      if (execute && action == 'device.diagnostics' && target != null) {
        ref.invalidate(
          platformResourceProvider(
            '/admin/sync/companies/${widget.companyId}/devices/$target/support-commands',
          ),
        );
      }
      setState(() {
        if (execute) {
          result = data;
        } else {
          preview = data;
        }
      });
    } catch (e) {
      if (mounted) setState(() => error = platformError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cap = ref.watch(platformCapabilitiesProvider).asData?.value;
    final allowed = _actions.entries
        .where(
          (e) => platformAllowsAction(cap, e.key, companyId: widget.companyId),
        )
        .toList();
    final needsTarget =
        action?.startsWith('access.') == true ||
        action == 'session.revoke' ||
        action == 'device.diagnostics';
    final resource = action?.startsWith('access.') == true
        ? '/admin/companies/${widget.companyId}/access-summary'
        : action == 'session.revoke'
        ? '/admin/companies/${widget.companyId}/sessions'
        : '/admin/companies/${widget.companyId}/devices';
    return PlatformPage(
      children: [
        const PlatformHeader(
          title: 'Operações administrativas',
          subtitle: 'Revise a empresa, o alvo e o impacto antes de confirmar.',
        ),
        if (allowed.isEmpty)
          const PlatformState(
            message:
                'Você pode consultar esta empresa, mas não possui operações de alteração liberadas neste escopo.',
          ),
        if (allowed.isNotEmpty)
          PlatformPanel(
            title: 'Preparar operação',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText('Empresa: ${widget.companyId}'),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: action,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Operação'),
                  items: [
                    for (final e in allowed)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: busy
                      ? null
                      : (v) {
                          action = v;
                          target = null;
                          invalidate();
                        },
                ),
                if (needsTarget) ...[
                  const SizedBox(height: 16),
                  PlatformResourceView(
                    resource: resource,
                    builder: (data) {
                      final rows = platformItems(
                        data[action?.startsWith('access.') == true
                                ? 'employees'
                                : 'items'] ??
                            data['sessions'] ??
                            data['devices'],
                      );
                      return DropdownButtonFormField<String>(
                        key: ValueKey('$action-$target'),
                        initialValue: target,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Alvo nesta empresa',
                        ),
                        items: [
                          for (final row in rows)
                            DropdownMenuItem(
                              value: platformText(
                                row['employeeProfileId'] ??
                                    row['id'] ??
                                    row['employeeId'],
                                '',
                              ),
                              child: Text(
                                platformText(
                                  row['name'] ??
                                      row['userName'] ??
                                      platformMap(row['user'])['name'] ??
                                      row['deviceLabel'] ??
                                      row['id'],
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: busy
                            ? null
                            : (v) {
                                target = v;
                                invalidate();
                              },
                      );
                    },
                  ),
                ],
                if (action == 'license.extend') ...[
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    initialValue: days,
                    decoration: const InputDecoration(
                      labelText: 'Dias adicionais',
                    ),
                    items: [
                      for (var n = 1; n <= 7; n++)
                        DropdownMenuItem(
                          value: n,
                          child: Text('$n ${n == 1 ? 'dia' : 'dias'}'),
                        ),
                    ],
                    onChanged: busy
                        ? null
                        : (v) {
                            days = v ?? 1;
                            invalidate();
                          },
                  ),
                ],
                const SizedBox(height: 16),
                TextField(
                  controller: reason,
                  enabled: !busy,
                  minLines: 2,
                  maxLines: 5,
                  maxLength: 1000,
                  decoration: const InputDecoration(labelText: 'Motivo'),
                  onChanged: (_) {
                    if (preview != null) invalidate();
                  },
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed:
                      busy || action == null || (needsTarget && target == null)
                      ? null
                      : () => run(false),
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Ver prévia de impacto'),
                ),
              ],
            ),
          ),
        if (busy) const LinearProgressIndicator(),
        if (error != null) PlatformState(message: error!, error: true),
        if (preview != null && result == null)
          PlatformPanel(
            title: 'Confirme o impacto',
            subtitle:
                'Prévia válida até ${platformDate(preview!['expiresAt'])}',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(platformText(preview!['summary'])),
                for (final risk in (preview!['risks'] as List? ?? []))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('• $risk'),
                  ),
                for (final blocker in (preview!['blockers'] as List? ?? []))
                  Text(
                    '$blocker',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (preview!['allowed'] == true) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Digite ${platformText(preview!['expectedConfirmationText'])} para confirmar.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmation,
                    enabled: !busy,
                    decoration: const InputDecoration(labelText: 'Confirmação'),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: busy ? null : () => run(true),
                    child: const Text('Confirmar operação'),
                  ),
                ],
              ],
            ),
          ),
        if (result != null)
          PlatformPanel(
            title: result!['status'] == 'requested'
                ? 'Diagnóstico solicitado'
                : 'Operação recebida',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result!['status'] == 'requested'
                      ? 'A solicitação foi registrada. Recebimento e conclusão dependem da resposta do aparelho.'
                      : 'Confira o resultado e a auditoria antes de realizar outra alteração.',
                ),
                TextButton(
                  onPressed: () => platformNavigate(
                    context,
                    '/audit?companyId=${widget.companyId}',
                  ),
                  child: const Text('Ver auditoria'),
                ),
              ],
            ),
          ),
        if (action == 'device.diagnostics' && target != null)
          PlatformPanel(
            title: 'Solicitações ao aparelho',
            action: IconButton(
              tooltip: 'Atualizar respostas do aparelho',
              onPressed: () => ref.invalidate(
                platformResourceProvider(
                  '/admin/sync/companies/${widget.companyId}/devices/$target/support-commands',
                ),
              ),
              icon: const Icon(Icons.refresh),
            ),
            child: PlatformResourceView(
              resource:
                  '/admin/sync/companies/${widget.companyId}/devices/$target/support-commands',
              builder: (data) => Column(
                children: [
                  if (platformItems(data['items']).isEmpty)
                    const PlatformState(
                      message:
                          'Nenhuma solicitação retornada para este aparelho.',
                    ),
                  for (final row in platformItems(data['items']))
                    PlatformRow(
                      title:
                          const {
                            'PENDING': 'Solicitado',
                            'RUNNING': 'Recebido e em processamento',
                            'SUCCEEDED': 'Concluído',
                            'FAILED': 'Falhou',
                            'EXPIRED': 'Expirou',
                            'CANCELLED': 'Cancelado',
                          }[row['status']] ??
                          platformText(row['status']),
                      subtitle:
                          'Solicitado ${platformDate(row['requestedAt'])}\nRecebido ${platformDate(row['pickedUpAt'])} · Concluído ${platformDate(row['completedAt'])}',
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class PlatformAdministrationPage extends ConsumerWidget {
  const PlatformAdministrationPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cap = ref.watch(platformCapabilitiesProvider).asData?.value;
    final templates = platformItems(cap?['templates']);
    final canReadPrivacy =
        ref
            .watch(adminCurrentUserPermissionsProvider)
            .asData
            ?.value
            .activePermissions
            .any(
              (permission) =>
                  permission.permissionKey == 'tenant.deletion.read',
            ) ??
        false;
    return PlatformPage(
      children: [
        const PlatformHeader(
          title: 'Administração',
          subtitle: 'Delegue acesso à equipe sem compartilhar sua conta.',
        ),
        PlatformPanel(
          title: 'Modelos de acesso',
          subtitle:
              'Concessões são aditivas. Revogações individuais permanecem na gestão de permissões.',
          child: Column(
            children: [
              for (final t in templates)
                PlatformRow(
                  title: platformText(t['label']),
                  subtitle:
                      '${(t['permissions'] as List? ?? []).length} permissões. Revise os acessos antes de aplicar.',
                  trailing: OutlinedButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => _TemplateDialog(template: t),
                    ),
                    child: const Text('Revisar perfil'),
                  ),
                ),
              if (templates.isEmpty)
                const PlatformState(
                  message:
                      'A gestão de permissões exige concessão administrativa específica.',
                ),
            ],
          ),
        ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            OutlinedButton(
              onPressed: () => platformNavigate(context, '/permissions'),
              child: const Text('Permissões individuais e catálogo'),
            ),
            if (canReadPrivacy)
              OutlinedButton(
                onPressed: () => platformNavigate(context, '/tenant-deletion'),
                child: const Text('Solicitações de privacidade'),
              ),
          ],
        ),
      ],
    );
  }
}

class _TemplateDialog extends ConsumerStatefulWidget {
  const _TemplateDialog({required this.template});
  final PlatformMap template;
  @override
  ConsumerState<_TemplateDialog> createState() => _TemplateState();
}

class _TemplateState extends ConsumerState<_TemplateDialog> {
  final reason = TextEditingController(),
      confirmation = TextEditingController();
  String? admin;
  bool busy = false;
  String? error;
  @override
  void dispose() {
    reason.dispose();
    confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(platformText(widget.template['label'])),
    content: SizedBox(
      width: 540,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Concede estes acessos em toda a plataforma:\n${(widget.template['permissions'] as List? ?? []).join('\n')}',
            ),
            const SizedBox(height: 16),
            PlatformResourceView(
              resource: '/admin/administrators',
              builder: (data) => DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: admin,
                decoration: const InputDecoration(
                  labelText: 'Administrador destinatário',
                ),
                items: [
                  for (final row in platformItems(data['items']))
                    DropdownMenuItem(
                      value: platformText(row['id'], ''),
                      child: Text(platformText(row['name'])),
                    ),
                ],
                onChanged: busy ? null : (v) => setState(() => admin = v),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reason,
              enabled: !busy,
              decoration: const InputDecoration(labelText: 'Motivo'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmation,
              enabled: !busy,
              decoration: const InputDecoration(
                labelText: 'Digite APLICAR_PERFIL',
              ),
            ),
            if (busy) const LinearProgressIndicator(),
            if (error != null) Text(error!),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.of(context).pop(),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: busy
            ? null
            : () async {
                if (admin == null ||
                    reason.text.trim().length < 12 ||
                    confirmation.text.trim() != 'APLICAR_PERFIL') {
                  setState(
                    () => error =
                        'Selecione o destinatário, descreva o motivo e confirme APLICAR_PERFIL.',
                  );
                  return;
                }
                setState(() {
                  busy = true;
                  error = null;
                });
                try {
                  await ref.read(platformApiProvider).post(
                    '/admin/permission-templates/${widget.template['key']}/apply',
                    {
                      'adminUserId': admin,
                      'reason': reason.text.trim(),
                      'scope': 'platform',
                      'scopeId': '*',
                      'confirmationText': confirmation.text.trim(),
                    },
                  );
                  if (context.mounted) Navigator.of(context).pop();
                } catch (e) {
                  if (mounted) setState(() => error = platformError(e));
                } finally {
                  if (mounted) setState(() => busy = false);
                }
              },
        child: const Text('Aplicar perfil'),
      ),
    ],
  );
}
