import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/admin_providers.dart';
import '../models/admin_support_action_models.dart';
import '../network/admin_api_client.dart';
import 'admin_surface.dart';

class AdminSupportActionDryRunPanel extends ConsumerStatefulWidget {
  const AdminSupportActionDryRunPanel({super.key, required this.companyId});

  final String companyId;

  @override
  ConsumerState<AdminSupportActionDryRunPanel> createState() =>
      _AdminSupportActionDryRunPanelState();
}

class _AdminSupportActionDryRunPanelState
    extends ConsumerState<AdminSupportActionDryRunPanel> {
  final _targetIdController = TextEditingController();
  final _reasonController = TextEditingController();
  _SupportActionOption _selectedAction = _supportActionOptions.first;
  AdminSupportActionDryRunResponse? _response;
  String? _error;
  bool _isLoading = false;

  @override
  void dispose() {
    _targetIdController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AdminSurface(
      title: 'Simulacoes operacionais',
      subtitle:
          'Pre-visualize impacto e risco sem alterar dados reais da empresa.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _DryRunNotice(),
          const SizedBox(height: 16),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 340,
                child: DropdownButtonFormField<_SupportActionOption>(
                  initialValue: _selectedAction,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Acao operacional para simular',
                    prefixIcon: Icon(Icons.science_outlined),
                  ),
                  items: _supportActionOptions
                      .map(
                        (option) => DropdownMenuItem<_SupportActionOption>(
                          value: option,
                          child: Text(
                            option.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: _isLoading
                      ? null
                      : (option) {
                          if (option == null) {
                            return;
                          }
                          setState(() {
                            _selectedAction = option;
                            _response = null;
                            _error = null;
                          });
                        },
                ),
              ),
              Chip(
                avatar: const Icon(Icons.adjust_rounded, size: 18),
                label: Text('Alvo: ${_selectedAction.targetType}'),
              ),
              Chip(
                avatar: const Icon(Icons.key_rounded, size: 18),
                label: Text('Permissao: ${_selectedAction.permissionKey}'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _targetIdController,
            enabled: !_isLoading,
            maxLength: 120,
            decoration: InputDecoration(
              labelText: '${_selectedAction.targetType}Id',
              hintText: 'Informe o identificador do alvo',
              prefixIcon: const Icon(Icons.badge_outlined),
            ),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _reasonController,
            enabled: !_isLoading,
            maxLength: 1000,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Motivo operacional',
              hintText: 'Informe o chamado ou justificativa da simulacao',
              prefixIcon: Icon(Icons.notes_rounded),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: _isLoading ? null : _simulate,
            icon: const Icon(Icons.preview_outlined),
            label: Text(_isLoading ? 'Simulando...' : 'Simular dry-run'),
          ),
          if (_response?.action case final action?) ...[
            const SizedBox(height: 20),
            _DryRunResult(action: action),
          ],
        ],
      ),
    );
  }

  Future<void> _simulate() async {
    final targetId = _targetIdController.text.trim();
    final reason = _reasonController.text.trim();
    if (targetId.isEmpty) {
      setState(() => _error = 'Informe um alvo operacional valido.');
      return;
    }
    if (reason.length < 12) {
      setState(
        () => _error =
            'Informe um motivo operacional com pelo menos 12 caracteres.',
      );
      return;
    }
    setState(() {
      _error = null;
      _response = null;
      _isLoading = true;
    });
    try {
      final response = await ref
          .read(adminApiServiceProvider)
          .simulateSupportActionDryRun(
            request: AdminSupportActionDryRunRequest(
              actionType: _selectedAction.actionType,
              companyId: widget.companyId,
              targetType: _selectedAction.targetType,
              targetId: targetId,
              reason: reason,
            ),
          );
      if (mounted) {
        setState(() => _response = response);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = _safeSupportActionError(error));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}

class _DryRunNotice extends StatelessWidget {
  const _DryRunNotice();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Dry-run: nenhum dado real sera alterado.',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          SizedBox(height: 4),
          Text('Execucao real ainda nao esta disponivel no Admin Web.'),
          Text('Esta simulacao sera auditavel conforme politica backend.'),
          Text('PermissionKeys do cliente nao autorizam acoes.'),
        ],
      ),
    );
  }
}

class _DryRunResult extends StatelessWidget {
  const _DryRunResult({required this.action});

  final AdminSupportActionDryRun action;

  @override
  Widget build(BuildContext context) {
    final impact = action.expectedImpact;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pre-visualizacao de impacto',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          Text(action.result.message),
          const SizedBox(height: 10),
          _ResultLine(label: 'Impacto esperado', value: impact.summary),
          _ResultLine(label: 'Permissao exigida', value: action.permissionKey),
          _ResultLine(
            label: 'Confirmacao futura',
            value: action.confirmationRequired ? 'Obrigatoria' : 'Nao exigida',
          ),
          _ResultLine(
            label: 'Auditoria preparada',
            value: action.auditPrepared ? 'Sim' : 'Nao',
          ),
          _ResultLine(
            label: 'Audit event',
            value: action.auditEventId ?? 'Pendente',
          ),
          _ResultLine(
            label: 'Risco',
            value: _riskLabel(action.auditDraft.riskLevel),
          ),
          const SizedBox(height: 10),
          Text('Riscos', style: Theme.of(context).textTheme.titleSmall),
          if (impact.risks.isEmpty)
            const Text('Nenhum risco informado.')
          else
            ...impact.risks.map((risk) => Text('- $risk')),
          const SizedBox(height: 10),
          Text(
            'Entidades afetadas',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (impact.affectedEntities.isEmpty)
            const Text('Nenhuma entidade informada.')
          else
            ...impact.affectedEntities.map(
              (entity) =>
                  Text('- ${entity.type}: ${entity.label ?? entity.id}'),
            ),
        ],
      ),
    );
  }
}

class _ResultLine extends StatelessWidget {
  const _ResultLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 170,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}

class _SupportActionOption {
  const _SupportActionOption({
    required this.actionType,
    required this.targetType,
    required this.permissionKey,
    required this.label,
  });

  final String actionType;
  final String targetType;
  final String permissionKey;
  final String label;
}

const _supportActionOptions = <_SupportActionOption>[
  _SupportActionOption(
    actionType: 'revoke_session',
    targetType: 'session',
    permissionKey: 'support.session.revoke',
    label: 'Simular revoke_session',
  ),
  _SupportActionOption(
    actionType: 'block_user',
    targetType: 'user',
    permissionKey: 'support.user.block',
    label: 'Simular block_user',
  ),
  _SupportActionOption(
    actionType: 'unblock_user',
    targetType: 'user',
    permissionKey: 'support.user.unblock',
    label: 'Simular unblock_user',
  ),
  _SupportActionOption(
    actionType: 'force_sync',
    targetType: 'device',
    permissionKey: 'support.sync.force',
    label: 'Simular force_sync',
  ),
  _SupportActionOption(
    actionType: 'resolve_conflict',
    targetType: 'conflict',
    permissionKey: 'support.sync.conflict.resolve',
    label: 'Simular resolve_conflict',
  ),
  _SupportActionOption(
    actionType: 'update_license',
    targetType: 'license',
    permissionKey: 'support.license.update',
    label: 'Simular update_license',
  ),
  _SupportActionOption(
    actionType: 'update_android_version_policy',
    targetType: 'android_version_policy',
    permissionKey: 'support.androidVersionPolicy.update',
    label: 'Simular update_android_version_policy',
  ),
  _SupportActionOption(
    actionType: 'send_push_notification',
    targetType: 'push_notification',
    permissionKey: 'support.push.send',
    label: 'Simular send_push_notification',
  ),
];

String _safeSupportActionError(Object error) {
  if (error is! AdminApiException) {
    return 'Nao foi possivel preparar a simulacao. Tente novamente.';
  }
  switch (error.code) {
    case 'OPERATIONAL_ACTION_VALIDATION_ERROR':
    case 'OPERATIONAL_ACTION_REASON_REQUIRED':
      return 'Informe um motivo operacional com pelo menos 12 caracteres.';
    case 'OPERATIONAL_ACTION_PERMISSION_REQUIRED':
    case 'OPERATIONAL_ACTION_PERMISSION_DENIED':
    case 'OPERATIONAL_ACTION_MISSING_PERMISSION':
      return 'Sem permissao persistida para simular esta acao operacional.';
    case 'OPERATIONAL_ACTION_TARGET_NOT_FOUND':
    case 'OPERATIONAL_ACTION_TARGET_REQUIRED':
      return 'Alvo operacional nao encontrado ou invalido.';
    case 'OPERATIONAL_ACTION_UNSUPPORTED':
      return 'Acao operacional nao suportada.';
    case 'OPERATIONAL_ACTION_ACTOR_REQUIRED':
    case 'ADMIN_SESSION_MISSING':
      return 'Sessao administrativa ausente ou expirada. Faca login novamente.';
  }
  if (error.statusCode == 401) {
    return 'Sessao administrativa ausente ou expirada. Faca login novamente.';
  }
  if (error.statusCode == 403) {
    return 'Sem permissao persistida para simular esta acao operacional.';
  }
  return 'Nao foi possivel preparar a simulacao. Tente novamente.';
}

String _riskLabel(String value) {
  return switch (value.toLowerCase()) {
    'critical' => 'Critico',
    'high' => 'Alto',
    'medium' => 'Medio',
    _ => 'Indisponivel',
  };
}
