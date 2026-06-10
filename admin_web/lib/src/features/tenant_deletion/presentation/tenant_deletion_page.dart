import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/admin_providers.dart';
import '../../../core/models/admin_tenant_deletion_models.dart';
import '../../../core/network/admin_api_client.dart';
import '../../../core/widgets/admin_surface.dart';

class TenantDeletionPage extends ConsumerStatefulWidget {
  const TenantDeletionPage({super.key});

  @override
  ConsumerState<TenantDeletionPage> createState() => _TenantDeletionPageState();
}

class _TenantDeletionPageState extends ConsumerState<TenantDeletionPage> {
  final _filterCompanyController = TextEditingController();
  final _requestCompanyController = TextEditingController();
  final _requesterNameController = TextEditingController();
  final _requesterEmailController = TextEditingController();
  final _requesterChannelController = TextEditingController(text: 'web');
  final _requestReasonController = TextEditingController();
  final _dryRunCompanyController = TextEditingController();
  final _dryRunRequestController = TextEditingController();
  final _dryRunReasonController = TextEditingController();

  String? _statusFilter;
  String? _message;
  String? _error;
  bool _creating = false;
  bool _dryRunning = false;
  AdminTenantDeletionDryRunResponse? _dryRunResponse;

  @override
  void dispose() {
    _filterCompanyController.dispose();
    _requestCompanyController.dispose();
    _requesterNameController.dispose();
    _requesterEmailController.dispose();
    _requesterChannelController.dispose();
    _requestReasonController.dispose();
    _dryRunCompanyController.dispose();
    _dryRunRequestController.dispose();
    _dryRunReasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = AdminTenantDeletionQuery(
      companyId: _filterCompanyController.text.trim().isEmpty
          ? null
          : _filterCompanyController.text.trim(),
      status: _statusFilter,
    );
    final requests = ref.watch(adminTenantDeletionRequestsProvider(query));

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SafetyBanner(),
          const SizedBox(height: 16),
          if (_message != null) _StatusBanner(message: _message!, error: false),
          if (_error != null) _StatusBanner(message: _error!, error: true),
          if (_message != null || _error != null) const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 980;
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildCreateRequestCard(context),
                    const SizedBox(height: 16),
                    _buildDryRunCard(context),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildCreateRequestCard(context)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildDryRunCard(context)),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          _buildRequestsCard(context, requests),
          if (_dryRunResponse != null) ...[
            const SizedBox(height: 16),
            _DryRunResult(response: _dryRunResponse!),
          ],
        ],
      ),
    );
  }

  Widget _buildCreateRequestCard(BuildContext context) {
    return AdminSurface(
      title: 'Registrar solicitacao',
      subtitle:
          'Cria uma solicitacao no workflow dedicado e registra auditoria sanitizada. Nao altera Company, billing, usuarios ou dados operacionais.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _requestCompanyController,
            decoration: const InputDecoration(
              labelText: 'companyId',
              helperText: 'Obrigatorio para vincular a solicitacao.',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _requesterEmailController,
            decoration: const InputDecoration(labelText: 'E-mail solicitante'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _requesterNameController,
                  decoration: const InputDecoration(
                    labelText: 'Nome solicitante',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 140,
                child: TextField(
                  controller: _requesterChannelController,
                  decoration: const InputDecoration(labelText: 'Canal'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _requestReasonController,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Motivo do registro',
              helperText: 'Minimo de 12 caracteres. Obrigatorio e auditado.',
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _creating ? null : _createRequest,
              icon: _creating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.playlist_add_check_rounded),
              label: const Text('Registrar solicitacao'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDryRunCard(BuildContext context) {
    return AdminSurface(
      title: 'Inventario dry-run',
      subtitle:
          'Consulta categorias, bloqueadores e riscos sem executar exclusao, anonimizacao, desativacao ou cancelamento externo.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _dryRunCompanyController,
            decoration: const InputDecoration(labelText: 'companyId'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _dryRunRequestController,
            decoration: const InputDecoration(
              labelText: 'requestId',
              helperText: 'Obrigatorio para salvar o snapshot na solicitacao.',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _dryRunReasonController,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Motivo do dry-run',
              helperText: 'Motivo obrigatorio e auditado.',
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonalIcon(
              onPressed: _dryRunning ? null : _runDryRun,
              icon: _dryRunning
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.fact_check_rounded),
              label: const Text('Gerar dry-run'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestsCard(
    BuildContext context,
    AsyncValue<AdminTenantDeletionRequestsSnapshot> requests,
  ) {
    return AdminSurface(
      title: 'Solicitacoes de exclusao de tenant',
      subtitle:
          'Acompanhamento seguro por status usando persistencia dedicada. Execucao real continua indisponivel.',
      trailing: FilledButton.tonalIcon(
        onPressed: () {
          ref.invalidate(adminTenantDeletionRequestsProvider);
        },
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Atualizar'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 280,
                child: TextField(
                  controller: _filterCompanyController,
                  decoration: const InputDecoration(
                    labelText: 'Filtrar por companyId',
                  ),
                  onSubmitted: (_) => setState(() {}),
                ),
              ),
              SizedBox(
                width: 240,
                child: DropdownButtonFormField<String?>(
                  initialValue: _statusFilter,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('Todos')),
                    DropdownMenuItem(
                      value: 'REQUESTED',
                      child: Text('REQUESTED'),
                    ),
                    DropdownMenuItem(
                      value: 'IDENTITY_PENDING',
                      child: Text('IDENTITY_PENDING'),
                    ),
                    DropdownMenuItem(
                      value: 'VERIFIED',
                      child: Text('VERIFIED'),
                    ),
                    DropdownMenuItem(
                      value: 'DRY_RUN_READY',
                      child: Text('DRY_RUN_READY'),
                    ),
                    DropdownMenuItem(
                      value: 'CANCELLED',
                      child: Text('CANCELLED'),
                    ),
                    DropdownMenuItem(
                      value: 'REJECTED',
                      child: Text('REJECTED'),
                    ),
                  ],
                  onChanged: (value) => setState(() => _statusFilter = value),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => setState(() {}),
                icon: const Icon(Icons.search_rounded),
                label: const Text('Filtrar'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          requests.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => _ErrorState(error: error),
            data: (snapshot) {
              if (snapshot.items.isEmpty) {
                return const _EmptyState();
              }
              return Column(
                children: snapshot.items
                    .map(
                      (request) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _RequestTile(request: request),
                      ),
                    )
                    .toList(growable: false),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _createRequest() async {
    final companyId = _requestCompanyController.text.trim();
    final reason = _requestReasonController.text.trim();
    if (companyId.isEmpty || reason.length < 12) {
      setState(() {
        _error = 'Informe companyId e motivo com pelo menos 12 caracteres.';
        _message = null;
      });
      return;
    }
    setState(() {
      _creating = true;
      _error = null;
      _message = null;
    });
    try {
      final result = await ref
          .read(adminApiServiceProvider)
          .createTenantDeletionRequest(
            companyId: companyId,
            reason: reason,
            requesterName: _requesterNameController.text,
            requesterEmail: _requesterEmailController.text,
            requesterChannel: _requesterChannelController.text,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _message =
            'Solicitacao registrada: ${result.request?.requestId ?? result.auditEventId ?? result.code}';
        _requestReasonController.clear();
      });
      ref.invalidate(adminTenantDeletionRequestsProvider);
    } on AdminApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _error = _safeError(error));
    } finally {
      if (mounted) {
        setState(() => _creating = false);
      }
    }
  }

  Future<void> _runDryRun() async {
    final companyId = _dryRunCompanyController.text.trim();
    final requestId = _dryRunRequestController.text.trim();
    final reason = _dryRunReasonController.text.trim();
    if (companyId.isEmpty || requestId.isEmpty || reason.length < 12) {
      setState(() {
        _error =
            'Informe companyId, requestId e motivo com pelo menos 12 caracteres.';
        _message = null;
      });
      return;
    }
    setState(() {
      _dryRunning = true;
      _error = null;
      _message = null;
    });
    try {
      final result = await ref
          .read(adminApiServiceProvider)
          .dryRunTenantDeletion(
            companyId: companyId,
            reason: reason,
            requestId: requestId,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _dryRunResponse = result;
        _message = 'Dry-run auditado: ${result.auditEventId ?? result.code}';
      });
      ref.invalidate(adminTenantDeletionRequestsProvider);
    } on AdminApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _error = _safeError(error));
    } finally {
      if (mounted) {
        setState(() => _dryRunning = false);
      }
    }
  }

  String _safeError(AdminApiException error) {
    switch (error.code) {
      case 'TENANT_DELETION_PERMISSION_REQUIRED':
        return 'Sem permissao granular para esta etapa do fluxo.';
      case 'TENANT_DELETION_REASON_REQUIRED':
        return 'Informe um motivo com pelo menos 12 caracteres.';
      case 'TENANT_DELETION_COMPANY_NOT_FOUND':
        return 'Empresa nao encontrada.';
      case 'TENANT_DELETION_REQUEST_NOT_FOUND':
        return 'Solicitacao nao encontrada.';
      case 'TENANT_DELETION_STATE_CONFLICT':
        return 'A solicitacao mudou de estado. Atualize a pagina e tente novamente.';
      default:
        return 'Nao foi possivel concluir a operacao administrativa.';
    }
  }
}

class _SafetyBanner extends StatelessWidget {
  const _SafetyBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_rounded, color: scheme.onSecondaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Workflow persistido e seguro: registra solicitacoes, valida RBAC granular e gera inventario dry-run. Nao ha purge fisico, anonimizacao real, quarentena, worker ou cancelamento de Mercado Pago nesta etapa.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSecondaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.message, required this.error});

  final String message;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: error ? scheme.errorContainer : scheme.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: error ? scheme.onErrorContainer : scheme.onPrimaryContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _RequestTile extends StatelessWidget {
  const _RequestTile({required this.request});

  final AdminTenantDeletionRequest request;

  @override
  Widget build(BuildContext context) {
    final company = request.company;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _StatusChip(status: request.status),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  request.requestId,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              if (company != null)
                TextButton.icon(
                  onPressed: () => context.go('/companies/${company.id}'),
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('Empresa'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            company == null
                ? 'Empresa nao vinculada'
                : '${company.name} (${company.id})',
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              Text('Acao: ${request.latestAction}'),
              Text('Identidade: ${request.identityStatus}'),
              Text('Origem: ${request.source}'),
              Text('Audit: ${request.latestAuditEventId}'),
              if (request.updatedAt != null)
                Text('Atualizado: ${request.updatedAt!.toLocal()}'),
              if (request.requester.email != null)
                Text('Solicitante: ${request.requester.email}'),
              if (request.dryRunSummary != null)
                Text(
                  'Dry-run: ${request.dryRunSummary!.categories} categorias, ${request.dryRunSummary!.blockers} bloqueadores',
                ),
            ],
          ),
          if (request.reason != null) ...[
            const SizedBox(height: 6),
            Text('Motivo: ${request.reason}'),
          ],
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (status) {
      'CANCELLED' || 'REJECTED' => scheme.errorContainer,
      'DRY_RUN_READY' || 'VERIFIED' => scheme.primaryContainer,
      _ => scheme.surfaceContainerHighest,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _DryRunResult extends StatelessWidget {
  const _DryRunResult({required this.response});

  final AdminTenantDeletionDryRunResponse response;

  @override
  Widget build(BuildContext context) {
    final dryRun = response.dryRun;
    return AdminSurface(
      title: 'Resultado do dry-run',
      subtitle:
          'Inventario read-only para ${dryRun.company.name}. Audit: ${response.auditEventId ?? "pendente"}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _InfoPill(label: 'Modo', value: dryRun.persistenceMode),
              _InfoPill(
                label: 'Categorias',
                value: '${dryRun.categories.length}',
              ),
              _InfoPill(
                label: 'Bloqueadores',
                value: '${dryRun.blockers.length}',
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Bloqueadores e riscos',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          ...dryRun.blockers.map(
            (blocker) => ListTile(
              dense: true,
              leading: Icon(
                blocker.severity == 'blocking'
                    ? Icons.block_rounded
                    : Icons.warning_amber_rounded,
              ),
              title: Text(blocker.message),
              subtitle: Text(
                blocker.count == null
                    ? blocker.key
                    : '${blocker.key}: ${blocker.count}',
              ),
            ),
          ),
          const Divider(height: 24),
          Text(
            'Categorias avaliadas',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          ...dryRun.categories.map(
            (category) => ListTile(
              dense: true,
              title: Text('${category.label}: ${category.count}'),
              subtitle: Text(
                '${category.recommendedHandling} - ${category.retentionReason ?? "sem retencao informada"}',
              ),
            ),
          ),
          const Divider(height: 24),
          ...dryRun.notes.map((note) => Text('- $note')),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text('$label: $value'));
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Text(
      'Nao foi possivel carregar solicitacoes: $error',
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 18),
      child: Text('Nenhuma solicitacao registrada nesta fundacao.'),
    );
  }
}
