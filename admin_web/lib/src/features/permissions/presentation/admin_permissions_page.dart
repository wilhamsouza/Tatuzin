import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/admin_providers.dart';
import '../../../core/models/admin_permissions_models.dart';
import '../../../core/network/admin_api_client.dart';
import '../../../core/utils/admin_formatters.dart';
import '../../../core/widgets/admin_operational_status.dart';
import '../../../core/widgets/admin_surface.dart';

class AdminPermissionsPage extends ConsumerStatefulWidget {
  const AdminPermissionsPage({super.key, this.initialAdminUserId});

  final String? initialAdminUserId;

  @override
  ConsumerState<AdminPermissionsPage> createState() =>
      _AdminPermissionsPageState();
}

class _AdminPermissionsPageState extends ConsumerState<AdminPermissionsPage> {
  late final TextEditingController _adminUserIdController;
  String? _selectedAdminUserId;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialAdminUserId?.trim() ?? '';
    _adminUserIdController = TextEditingController(text: initial);
    _selectedAdminUserId = initial.isEmpty ? null : initial;
  }

  @override
  void dispose() {
    _adminUserIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catalogAsync = ref.watch(adminPermissionsCatalogProvider);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminSurface(
            title: 'Permissoes administrativas',
            subtitle:
                'Gestao controlada de permissoes persistidas por admin, com motivo e auditoria.',
            trailing: FilledButton.tonalIcon(
              onPressed: () => ref.invalidate(adminPermissionsCatalogProvider),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Atualizar catalogo'),
            ),
            child: const _SecurityNotice(),
          ),
          const SizedBox(height: 24),
          catalogAsync.when(
            data: (catalog) => _CatalogSection(catalog: catalog),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => _ErrorSurface(
              title: 'Catalogo indisponivel',
              message: _safeError(error),
              onRetry: () => ref.invalidate(adminPermissionsCatalogProvider),
            ),
          ),
          const SizedBox(height: 24),
          AdminSurface(
            title: 'Permissoes por admin',
            subtitle:
                'Informe o adminUserId para consultar e gerenciar permissoes administrativas persistidas.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _AdminUserLookup(
                  controller: _adminUserIdController,
                  onSubmit: _submitAdminUserId,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Bootstrap inicial permanece restrito ao backend/CLI controlado.',
                ),
                const SizedBox(height: 8),
                const Text(
                  'Use este painel apenas para permissoes administrativas. Acoes operacionais continuam bloqueadas nesta fase.',
                ),
                const SizedBox(height: 20),
                _selectedAdminUserId == null
                    ? const _EmptyState(
                        icon: Icons.manage_accounts_rounded,
                        message:
                            'Nenhum admin selecionado. Informe um adminUserId para consultar permissoes.',
                      )
                    : _UserPermissionsSection(
                        adminUserId: _selectedAdminUserId!,
                        catalog: catalogAsync.valueOrNull?.items ?? const [],
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _submitAdminUserId() {
    final normalized = _adminUserIdController.text.trim();
    setState(() {
      _selectedAdminUserId = normalized.isEmpty ? null : normalized;
    });
  }
}

class _SecurityNotice extends StatelessWidget {
  const _SecurityNotice();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        Chip(
          avatar: Icon(Icons.security_rounded, size: 18),
          label: Text('Permissoes resolvidas no backend'),
        ),
        Chip(
          avatar: Icon(Icons.key_off_rounded, size: 18),
          label: Text('permissionKeys do cliente nao concedem acesso'),
        ),
        Chip(
          avatar: Icon(Icons.admin_panel_settings_rounded, size: 18),
          label: Text('isPlatformAdmin sozinho nao libera acoes sensiveis'),
        ),
        Chip(
          avatar: Icon(Icons.rule_rounded, size: 18),
          label: Text('Grant/revoke exigem motivo, confirmacao e auditoria'),
        ),
      ],
    );
  }
}

class _CatalogSection extends StatelessWidget {
  const _CatalogSection({required this.catalog});

  final AdminPermissionsCatalog catalog;

  @override
  Widget build(BuildContext context) {
    return AdminSurface(
      title: 'Catalogo de permissionKeys',
      subtitle:
          'Permissoes conhecidas pelo backend para admin-permissions e support-actions futuras.',
      child: catalog.items.isEmpty
          ? const _EmptyState(
              icon: Icons.inventory_2_rounded,
              message: 'Nenhum permissionKey encontrado no catalogo.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CatalogSummary(items: catalog.items),
                const SizedBox(height: 18),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('permissionKey')),
                      DataColumn(label: Text('Descricao')),
                      DataColumn(label: Text('Categoria')),
                      DataColumn(label: Text('Risco')),
                      DataColumn(label: Text('actionType')),
                      DataColumn(label: Text('Dry-run')),
                      DataColumn(label: Text('Motivo')),
                      DataColumn(label: Text('Confirmacao')),
                      DataColumn(label: Text('Auditoria')),
                      DataColumn(label: Text('Escopos')),
                    ],
                    rows: catalog.items.map(_catalogRow).toList(),
                  ),
                ),
              ],
            ),
    );
  }

  DataRow _catalogRow(AdminPermissionDefinition permission) {
    return DataRow(
      cells: [
        DataCell(SelectableText(permission.permissionKey)),
        DataCell(Text(_fallback(permission.description))),
        DataCell(Text(_label(permission.category))),
        DataCell(_RiskIndicator(riskLevel: permission.riskLevel)),
        DataCell(Text(_fallback(permission.actionType))),
        DataCell(_FlagChip(enabled: permission.requiresDryRun)),
        DataCell(_FlagChip(enabled: permission.requiresReason)),
        DataCell(_FlagChip(enabled: permission.requiresExplicitConfirmation)),
        DataCell(_FlagChip(enabled: permission.requiresPersistentAudit)),
        DataCell(
          Text(
            permission.scopes.isEmpty
                ? 'Indisponivel'
                : permission.scopes.join(', '),
          ),
        ),
      ],
    );
  }
}

class _CatalogSummary extends StatelessWidget {
  const _CatalogSummary({required this.items});

  final List<AdminPermissionDefinition> items;

  @override
  Widget build(BuildContext context) {
    final critical = items
        .where((item) => item.riskLevel.toLowerCase() == 'critical')
        .length;
    final high = items
        .where((item) => item.riskLevel.toLowerCase() == 'high')
        .length;
    final supportActions = items
        .where((item) => item.category == 'support-action')
        .length;
    return Wrap(
      spacing: 14,
      runSpacing: 14,
      children: [
        _MetricTile(title: 'PermissionKeys', value: '${items.length}'),
        _MetricTile(title: 'Risco critico', value: '$critical'),
        _MetricTile(title: 'Risco alto', value: '$high'),
        _MetricTile(title: 'Support-actions', value: '$supportActions'),
      ],
    );
  }
}

class _AdminUserLookup extends StatelessWidget {
  const _AdminUserLookup({required this.controller, required this.onSubmit});

  final TextEditingController controller;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 420,
          child: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'adminUserId',
              hintText: 'Cole o ID do admin',
              prefixIcon: Icon(Icons.badge_rounded),
            ),
            onSubmitted: (_) => onSubmit(),
          ),
        ),
        FilledButton.icon(
          onPressed: onSubmit,
          icon: const Icon(Icons.search_rounded),
          label: const Text('Consultar'),
        ),
      ],
    );
  }
}

class _UserPermissionsSection extends ConsumerStatefulWidget {
  const _UserPermissionsSection({
    required this.adminUserId,
    required this.catalog,
  });

  final String adminUserId;
  final List<AdminPermissionDefinition> catalog;

  @override
  ConsumerState<_UserPermissionsSection> createState() =>
      _UserPermissionsSectionState();
}

class _UserPermissionsSectionState
    extends ConsumerState<_UserPermissionsSection> {
  String? _mutationError;
  bool _isMutating = false;

  @override
  Widget build(BuildContext context) {
    final permissionsAsync = ref.watch(
      adminUserPermissionsProvider(widget.adminUserId),
    );
    return permissionsAsync.when(
      data: (snapshot) => _UserPermissionsTables(
        snapshot: snapshot,
        catalog: widget.catalog,
        isMutating: _isMutating,
        mutationError: _mutationError,
        onGrant: _grant,
        onRevoke: _revoke,
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _InlineError(
        title: _permissionErrorTitle(error),
        message: _safeError(error),
        onRetry: () =>
            ref.invalidate(adminUserPermissionsProvider(widget.adminUserId)),
      ),
    );
  }

  Future<void> _grant(
    AdminPermissionDefinition permission,
    String reason,
  ) async {
    final confirmed = await _showGrantConfirmationDialog(
      context: context,
      permission: permission,
      reason: reason,
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await _mutate(
      operation: 'grant',
      request: () => ref
          .read(adminApiServiceProvider)
          .grantAdminPermission(
            adminUserId: widget.adminUserId,
            permissionKey: permission.permissionKey,
            reason: reason,
          ),
    );
  }

  Future<void> _revoke(AdminUserPermission permission) async {
    final definition = _definitionForKey(
      widget.catalog,
      permission.permissionKey,
    );
    final reason = await _showRevokeConfirmationDialog(
      context: context,
      permission: definition,
    );
    if (reason == null || !mounted) {
      return;
    }
    await _mutate(
      operation: 'revoke',
      request: () => ref
          .read(adminApiServiceProvider)
          .revokeAdminPermission(
            adminUserId: widget.adminUserId,
            permissionKey: permission.permissionKey,
            reason: reason,
            scope: permission.scope,
            scopeId: permission.scopeId,
          ),
    );
  }

  Future<void> _mutate({
    required String operation,
    required Future<AdminPermissionMutationResult> Function() request,
  }) async {
    setState(() {
      _mutationError = null;
      _isMutating = true;
    });
    try {
      final result = await request();
      if (!mounted) {
        return;
      }
      final _ = await ref.refresh(
        adminUserPermissionsProvider(widget.adminUserId).future,
      );
      if (!mounted) {
        return;
      }
      final noActivePermission =
          operation == 'revoke' && result.revokedCount == 0;
      final message = noActivePermission
          ? 'Permissao ativa nao encontrada para revogar. Nenhuma alteracao foi aplicada. Tentativa auditada.'
          : '${result.message} Acao auditada: ${result.auditEventId ?? 'registro persistido'}.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (mounted) {
        setState(() => _mutationError = _permissionMutationError(error));
      }
    } finally {
      if (mounted) {
        setState(() => _isMutating = false);
      }
    }
  }
}

class _UserPermissionsTables extends StatelessWidget {
  const _UserPermissionsTables({
    required this.snapshot,
    required this.catalog,
    required this.isMutating,
    required this.mutationError,
    required this.onGrant,
    required this.onRevoke,
  });

  final AdminUserPermissionsSnapshot snapshot;
  final List<AdminPermissionDefinition> catalog;
  final bool isMutating;
  final String? mutationError;
  final Future<void> Function(
    AdminPermissionDefinition permission,
    String reason,
  )
  onGrant;
  final Future<void> Function(AdminUserPermission permission) onRevoke;

  @override
  Widget build(BuildContext context) {
    final active = snapshot.activePermissions;
    final inactive = snapshot.inactivePermissions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            _MetricTile(title: 'Admin', value: snapshot.adminUserId),
            _MetricTile(title: 'Ativas', value: '${active.length}'),
            _MetricTile(title: 'Inativas', value: '${inactive.length}'),
            _MetricTile(
              title: 'Audit event',
              value: snapshot.auditEventId ?? 'Indisponivel',
            ),
          ],
        ),
        const SizedBox(height: 20),
        _GrantPermissionPanel(
          catalog: catalog,
          isMutating: isMutating,
          onGrant: onGrant,
        ),
        if (mutationError != null) ...[
          const SizedBox(height: 16),
          _MutationError(message: mutationError!),
        ],
        const SizedBox(height: 20),
        _PermissionTable(
          title: 'Permissoes ativas',
          emptyMessage: 'Admin sem permissoes ativas.',
          permissions: active,
          catalog: catalog,
          isMutating: isMutating,
          onRevoke: onRevoke,
        ),
        const SizedBox(height: 20),
        _PermissionTable(
          title: 'Permissoes inativas ou revogadas',
          emptyMessage:
              'Nenhuma permissao inativa retornada pelo backend para este admin.',
          permissions: inactive,
          catalog: catalog,
          isMutating: isMutating,
        ),
      ],
    );
  }
}

class _GrantPermissionPanel extends StatefulWidget {
  const _GrantPermissionPanel({
    required this.catalog,
    required this.isMutating,
    required this.onGrant,
  });

  final List<AdminPermissionDefinition> catalog;
  final bool isMutating;
  final Future<void> Function(
    AdminPermissionDefinition permission,
    String reason,
  )
  onGrant;

  @override
  State<_GrantPermissionPanel> createState() => _GrantPermissionPanelState();
}

class _GrantPermissionPanelState extends State<_GrantPermissionPanel> {
  final _reasonController = TextEditingController();
  String? _selectedPermissionKey;
  String? _validationError;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedPermissionKey == null
        ? null
        : _definitionForKey(widget.catalog, _selectedPermissionKey!);
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
            'Conceder permissao administrativa',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          const Text(
            'Selecione uma permissionKey do catalogo. A concessao exige motivo, confirmacao explicita e auditoria backend.',
          ),
          const SizedBox(height: 16),
          if (widget.catalog.isEmpty)
            const _EmptyState(
              icon: Icons.inventory_2_rounded,
              message:
                  'Catalogo indisponivel. Nao e possivel conceder permissao.',
            )
          else ...[
            DropdownButtonFormField<String>(
              initialValue: _selectedPermissionKey,
              decoration: const InputDecoration(
                labelText: 'permissionKey para conceder',
                prefixIcon: Icon(Icons.key_rounded),
              ),
              items: widget.catalog
                  .map(
                    (item) => DropdownMenuItem<String>(
                      value: item.permissionKey,
                      child: Text(item.permissionKey),
                    ),
                  )
                  .toList(growable: false),
              onChanged: widget.isMutating
                  ? null
                  : (value) => setState(() {
                      _selectedPermissionKey = value;
                      _validationError = null;
                    }),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reasonController,
              enabled: !widget.isMutating,
              maxLength: 1000,
              decoration: const InputDecoration(
                labelText: 'Motivo da concessao',
                hintText: 'Informe o chamado ou justificativa administrativa',
                prefixIcon: Icon(Icons.notes_rounded),
              ),
            ),
            if (selected != null) ...[
              const SizedBox(height: 6),
              _PermissionRiskDetails(permission: selected),
            ],
            if (_validationError != null) ...[
              const SizedBox(height: 10),
              Text(
                _validationError!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: widget.isMutating ? null : _submit,
              icon: const Icon(Icons.add_moderator_rounded),
              label: const Text('Conceder permissao'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final selectedPermissionKey = _selectedPermissionKey;
    final reason = _reasonController.text.trim();
    if (selectedPermissionKey == null) {
      setState(() => _validationError = 'Selecione uma permissionKey.');
      return;
    }
    if (reason.length < 12) {
      setState(
        () => _validationError =
            'Informe um motivo com pelo menos 12 caracteres.',
      );
      return;
    }
    setState(() => _validationError = null);
    await widget.onGrant(
      _definitionForKey(widget.catalog, selectedPermissionKey),
      reason,
    );
  }
}

class _PermissionTable extends StatelessWidget {
  const _PermissionTable({
    required this.title,
    required this.emptyMessage,
    required this.permissions,
    required this.catalog,
    required this.isMutating,
    this.onRevoke,
  });

  final String title;
  final String emptyMessage;
  final List<AdminUserPermission> permissions;
  final List<AdminPermissionDefinition> catalog;
  final bool isMutating;
  final Future<void> Function(AdminUserPermission permission)? onRevoke;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        if (permissions.isEmpty)
          _EmptyState(icon: Icons.rule_folder_rounded, message: emptyMessage)
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: [
                const DataColumn(label: Text('permissionKey')),
                const DataColumn(label: Text('Status')),
                const DataColumn(label: Text('Escopo')),
                const DataColumn(label: Text('scopeId')),
                const DataColumn(label: Text('Criada em')),
                const DataColumn(label: Text('Atualizada em')),
                const DataColumn(label: Text('Revogada em')),
                if (onRevoke != null) const DataColumn(label: Text('Acao')),
              ],
              rows: permissions.map(_permissionRow).toList(),
            ),
          ),
      ],
    );
  }

  DataRow _permissionRow(AdminUserPermission permission) {
    return DataRow(
      cells: [
        DataCell(SelectableText(permission.permissionKey)),
        DataCell(
          AdminOperationalStatus(
            label: permission.isActive ? 'Ativa' : 'Inativa',
            tone: permission.isActive
                ? AdminOperationalTone.ok
                : AdminOperationalTone.noData,
            compact: true,
          ),
        ),
        DataCell(Text(_fallback(permission.scope))),
        DataCell(Text(_fallback(permission.scopeId))),
        DataCell(Text(_formatDate(permission.createdAt))),
        DataCell(Text(_formatDate(permission.updatedAt))),
        DataCell(Text(_formatDate(permission.revokedAt))),
        if (onRevoke != null)
          DataCell(
            TextButton.icon(
              onPressed: isMutating || !permission.isActive
                  ? null
                  : () => onRevoke!(permission),
              icon: const Icon(Icons.remove_moderator_rounded),
              label: const Text('Revogar'),
            ),
          ),
      ],
    );
  }
}

class _MutationError extends StatelessWidget {
  const _MutationError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(message),
    );
  }
}

class _RiskIndicator extends StatelessWidget {
  const _RiskIndicator({required this.riskLevel});

  final String riskLevel;

  @override
  Widget build(BuildContext context) {
    final normalized = riskLevel.toLowerCase();
    final tone = switch (normalized) {
      'critical' => AdminOperationalTone.critical,
      'high' => AdminOperationalTone.attention,
      'medium' => AdminOperationalTone.attention,
      'low' => AdminOperationalTone.ok,
      _ => AdminOperationalTone.noData,
    };
    return AdminOperationalStatus(
      label: _riskLabel(normalized),
      tone: tone,
      compact: true,
    );
  }
}

class _PermissionRiskDetails extends StatelessWidget {
  const _PermissionRiskDetails({required this.permission});

  final AdminPermissionDefinition permission;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _RiskIndicator(riskLevel: permission.riskLevel),
        Chip(label: Text(_fallback(permission.description))),
        Chip(
          label: Text('Dry-run: ${permission.requiresDryRun ? 'Sim' : 'Nao'}'),
        ),
        Chip(
          label: Text('Motivo: ${permission.requiresReason ? 'Sim' : 'Nao'}'),
        ),
        Chip(
          label: Text(
            'Confirmacao: ${permission.requiresExplicitConfirmation ? 'Sim' : 'Nao'}',
          ),
        ),
        Chip(
          label: Text(
            'Auditoria: ${permission.requiresPersistentAudit ? 'Sim' : 'Nao'}',
          ),
        ),
      ],
    );
  }
}

class _FlagChip extends StatelessWidget {
  const _FlagChip({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(
        enabled ? Icons.check_circle_rounded : Icons.remove_circle_outline,
        size: 18,
      ),
      label: Text(enabled ? 'Sim' : 'Nao'),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 180, maxWidth: 300),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          SelectableText(
            value,
            maxLines: 2,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorSurface extends StatelessWidget {
  const _ErrorSurface({
    required this.title,
    required this.message,
    required this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return AdminSurface(
      title: title,
      subtitle: message,
      child: FilledButton.tonalIcon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Tentar novamente'),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({
    required this.title,
    required this.message,
    required this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(message),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

Future<bool?> _showGrantConfirmationDialog({
  required BuildContext context,
  required AdminPermissionDefinition permission,
  required String reason,
}) {
  var confirmed = false;
  return showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Confirmar concessao'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Voce esta concedendo uma permissao administrativa sensivel. Esta acao sera auditada.',
              ),
              const SizedBox(height: 14),
              SelectableText(permission.permissionKey),
              const SizedBox(height: 10),
              _PermissionRiskDetails(permission: permission),
              const SizedBox(height: 12),
              Text('Motivo: $reason'),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: confirmed,
                onChanged: (value) => setState(() => confirmed = value == true),
                title: const Text(
                  'Confirmo a concessao desta permissao administrativa.',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: confirmed ? () => Navigator.of(context).pop(true) : null,
            child: const Text('Confirmar concessao'),
          ),
        ],
      ),
    ),
  );
}

Future<String?> _showRevokeConfirmationDialog({
  required BuildContext context,
  required AdminPermissionDefinition permission,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _RevokePermissionDialog(permission: permission),
  );
}

class _RevokePermissionDialog extends StatefulWidget {
  const _RevokePermissionDialog({required this.permission});

  final AdminPermissionDefinition permission;

  @override
  State<_RevokePermissionDialog> createState() =>
      _RevokePermissionDialogState();
}

class _RevokePermissionDialogState extends State<_RevokePermissionDialog> {
  final _reasonController = TextEditingController();
  bool _confirmed = false;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final normalizedReason = _reasonController.text.trim();
    final reasonValid = normalizedReason.length >= 12;
    return AlertDialog(
      title: const Text('Confirmar revogacao'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Voce esta revogando uma permissao administrativa. Esta acao sera auditada.',
            ),
            const SizedBox(height: 14),
            SelectableText(widget.permission.permissionKey),
            const SizedBox(height: 10),
            _PermissionRiskDetails(permission: widget.permission),
            const SizedBox(height: 12),
            TextField(
              controller: _reasonController,
              maxLength: 1000,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Motivo da revogacao',
                hintText: 'Informe o chamado ou justificativa administrativa',
                prefixIcon: Icon(Icons.notes_rounded),
              ),
            ),
            if (normalizedReason.isNotEmpty && !reasonValid)
              Text(
                'Informe um motivo com pelo menos 12 caracteres.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _confirmed,
              onChanged: (value) => setState(() => _confirmed = value == true),
              title: const Text(
                'Confirmo a revogacao desta permissao administrativa.',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _confirmed && reasonValid
              ? () => Navigator.of(context).pop(normalizedReason)
              : null,
          child: const Text('Confirmar revogacao'),
        ),
      ],
    );
  }
}

String _safeError(Object error) {
  final message = error.toString();
  if (message.contains('AdminApiException')) {
    return message.split('AdminApiException').last.trim();
  }
  if (message.contains('Exception:')) {
    return message.split('Exception:').last.trim();
  }
  return message;
}

String _permissionMutationError(Object error) {
  if (error is! AdminApiException) {
    return 'Nao foi possivel concluir a alteracao de permissao. Tente novamente.';
  }
  switch (error.code) {
    case 'ADMIN_REASON_REQUIRED':
    case 'ADMIN_PERMISSION_VALIDATION_ERROR':
      return 'Informe um motivo valido com pelo menos 12 caracteres.';
    case 'ADMIN_PERMISSION_UNSUPPORTED':
      return 'PermissionKey desconhecida ou nao suportada pelo backend.';
    case 'ADMIN_PERMISSION_MANAGE_REQUIRED':
    case 'ADMIN_PERMISSION_SELF_GRANT_BLOCKED':
      return 'Sem autorizacao para alterar esta permissao administrativa.';
    case 'ADMIN_PERMISSION_DUPLICATE':
      return 'Esta permissao ja esta ativa para o admin selecionado.';
    case 'ADMIN_PERMISSION_NOT_FOUND':
      return 'Permissao ativa nao encontrada para revogar.';
    case 'ADMIN_PERMISSION_ACTOR_REQUIRED':
    case 'ADMIN_SESSION_MISSING':
      return 'Sessao administrativa ausente ou expirada. Faca login novamente.';
  }
  if (error.statusCode == 401) {
    return 'Sessao administrativa ausente ou expirada. Faca login novamente.';
  }
  if (error.statusCode == 403) {
    return 'Sem autorizacao para alterar esta permissao administrativa.';
  }
  if (error.statusCode == 404) {
    return 'Admin nao encontrado.';
  }
  return 'Nao foi possivel concluir a alteracao de permissao. Tente novamente.';
}

String _permissionErrorTitle(Object error) {
  final message = error.toString().toLowerCase();
  if (message.contains('401') || message.contains('auth')) {
    return 'Erro de autenticacao';
  }
  if (message.contains('403') ||
      message.contains('permission') ||
      message.contains('permissao') ||
      message.contains('autorizacao')) {
    return 'Sem permissao para consultar este admin';
  }
  if (message.contains('404') || message.contains('not_found')) {
    return 'Admin nao encontrado';
  }
  return 'Erro de carregamento';
}

String _fallback(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? 'Indisponivel' : trimmed;
}

String _formatDate(DateTime? value) {
  if (value == null) {
    return 'Indisponivel';
  }
  return AdminFormatters.formatDateTime(value);
}

String _label(String value) {
  switch (value) {
    case 'admin-permissions':
      return 'Admin permissions';
    case 'support-action':
      return 'Support action';
    default:
      return _fallback(value);
  }
}

String _riskLabel(String value) {
  switch (value) {
    case 'critical':
      return 'Critico';
    case 'high':
      return 'Alto';
    case 'medium':
      return 'Medio';
    case 'low':
      return 'Baixo';
    default:
      return 'Sem dados';
  }
}

AdminPermissionDefinition _definitionForKey(
  List<AdminPermissionDefinition> catalog,
  String permissionKey,
) {
  for (final item in catalog) {
    if (item.permissionKey == permissionKey) {
      return item;
    }
  }
  return AdminPermissionDefinition(
    permissionKey: permissionKey,
    description: 'Descricao indisponivel no catalogo.',
    category: 'Sem categoria',
    riskLevel: 'unknown',
    actionType: null,
    scopes: const [],
    requiresDryRun: false,
    requiresReason: true,
    requiresExplicitConfirmation: true,
    requiresPersistentAudit: true,
  );
}
