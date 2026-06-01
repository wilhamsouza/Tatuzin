import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/admin_providers.dart';
import '../../../core/models/admin_billing_models.dart';
import '../../../core/models/admin_models.dart';
import '../../../core/utils/admin_formatters.dart';
import '../../../core/widgets/admin_surface.dart';

const _placeholderMessage =
    'Acao administrativa sera implementada em fase posterior com dry-run, confirmacao explicita e auditoria.';

enum _LicenseListFilter {
  all,
  free,
  basic,
  pro,
  active,
  pendingPlan,
  cancelScheduled,
  billingError,
}

class LicensesPage extends ConsumerStatefulWidget {
  const LicensesPage({super.key});

  @override
  ConsumerState<LicensesPage> createState() => _LicensesPageState();
}

class _LicensesPageState extends ConsumerState<LicensesPage> {
  late final TextEditingController _searchController;
  _LicenseListFilter _filter = _LicenseListFilter.all;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = AdminBillingCompaniesQuery(
      page: _page,
      pageSize: 20,
      search: _searchController.text,
      plan: _planFilter(_filter),
      status: _statusFilter(_filter),
      sort: 'currentPeriodEnd',
      sortDirection: 'asc',
    );
    final licensesAsync = ref.watch(adminBillingCompaniesProvider(query));

    return licensesAsync.when(
      data: (result) {
        final visibleItems = result.items
            .where((item) => _matchesLocalFilter(item, _filter))
            .toList(growable: false);
        return RefreshIndicator(
          onRefresh: () async =>
              ref.invalidate(adminBillingCompaniesProvider(query)),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: AdminSurface(
              title: 'Licencas read-only',
              subtitle:
                  'Consulta administrativa de licencas e assinaturas via endpoints reais /api/admin/*. Nenhuma acao mutavel e executada nesta fase.',
              trailing: OutlinedButton.icon(
                onPressed: () =>
                    ref.invalidate(adminBillingCompaniesProvider(query)),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Atualizar'),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _ReadOnlyBanner(),
                  const SizedBox(height: 16),
                  _Filters(
                    searchController: _searchController,
                    filter: _filter,
                    onApply: (filter) => setState(() {
                      _filter = filter;
                      _page = 1;
                    }),
                    onClear: () {
                      _searchController.clear();
                      setState(() {
                        _filter = _LicenseListFilter.all;
                        _page = 1;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  if (visibleItems.isEmpty)
                    const _EmptyState(
                      message: 'Nenhuma licenca encontrada para os filtros.',
                    )
                  else
                    _LicensesTable(items: visibleItems),
                  const SizedBox(height: 16),
                  _PaginationBar(
                    pagination: result.pagination,
                    onPrevious: result.pagination.hasPrevious
                        ? () => setState(() => _page--)
                        : null,
                    onNext: result.pagination.hasNext
                        ? () => setState(() => _page++)
                        : null,
                  ),
                ],
              ),
            ),
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => AdminSurface(
        title: 'Nao foi possivel carregar licencas',
        subtitle: _safeError(error),
        trailing: FilledButton.tonalIcon(
          onPressed: () => ref.invalidate(adminBillingCompaniesProvider(query)),
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Tentar novamente'),
        ),
        child: const Text(
          'Erro amigavel: nenhum payload sensivel foi exibido.',
        ),
      ),
    );
  }
}

class _LicensesTable extends StatelessWidget {
  const _LicensesTable({required this.items});

  final List<AdminBillingCompanySummary> items;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Empresa')),
          DataColumn(label: Text('CompanyId')),
          DataColumn(label: Text('Plano ativo')),
          DataColumn(label: Text('Status licenca')),
          DataColumn(label: Text('Mudanca pendente')),
          DataColumn(label: Text('Provider')),
          DataColumn(label: Text('Status assinatura')),
          DataColumn(label: Text('Cancelamento')),
          DataColumn(label: Text('Periodo atual')),
          DataColumn(label: Text('Proxima cobranca')),
          DataColumn(label: Text('Assinatura')),
          DataColumn(label: Text('Ultimo evento')),
          DataColumn(label: Text('Acao')),
        ],
        rows: items
            .map(
              (license) => DataRow(
                cells: [
                  DataCell(
                    Text(license.companyName),
                    onTap: () => context.go('/licenses/${license.companyId}'),
                  ),
                  DataCell(Text(_maskIdentifier(license.companyId))),
                  DataCell(Text(AdminFormatters.formatPlan(license.plan))),
                  DataCell(
                    _StatusChip(
                      label: AdminFormatters.formatLicenseStatus(
                        license.licenseStatus,
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      license.pendingPlan == null
                          ? 'Nenhuma'
                          : 'Mudanca pendente: ${AdminFormatters.formatPlan(license.pendingPlan!)}',
                    ),
                  ),
                  DataCell(Text(license.billingProvider ?? 'Sem provider')),
                  DataCell(
                    Text(
                      _billingStatusLabel(license.billingSubscriptionStatus),
                    ),
                  ),
                  DataCell(
                    Text(
                      license.cancelAtPeriodEnd
                          ? 'Cancelamento agendado'
                          : 'Nao agendado',
                    ),
                  ),
                  DataCell(
                    Text(AdminFormatters.formatDate(license.currentPeriodEnd)),
                  ),
                  DataCell(
                    Text(AdminFormatters.formatDate(license.nextPaymentDate)),
                  ),
                  DataCell(
                    Text(
                      license.maskedProviderSubscriptionId ??
                          'Sem assinatura provider',
                    ),
                  ),
                  const DataCell(Text('Nao disponivel nesta versao')),
                  DataCell(
                    FilledButton.tonalIcon(
                      onPressed: () =>
                          context.go('/licenses/${license.companyId}'),
                      icon: const Icon(Icons.open_in_new_rounded),
                      label: const Text('Ver licenca'),
                    ),
                  ),
                ],
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class LicenseCompanyPage extends ConsumerWidget {
  const LicenseCompanyPage({super.key, required this.companyId});

  final String companyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final billingAsync = ref.watch(
      adminBillingCompanyStatusProvider(companyId),
    );
    final billingListQuery = AdminBillingListQuery(
      companyId: companyId,
      page: 1,
      pageSize: 20,
    );
    final eventsAsync = ref.watch(adminBillingEventsProvider(billingListQuery));
    final checkoutAsync = ref.watch(
      adminBillingCheckoutSessionsProvider(billingListQuery),
    );
    final auditLogsAsync = ref.watch(
      adminBillingAuditLogsProvider(billingListQuery),
    );
    Future<void> refreshLicense() async {
      ref.invalidate(adminBillingCompanyStatusProvider(companyId));
      ref.invalidate(adminBillingEventsProvider(billingListQuery));
      ref.invalidate(adminBillingCheckoutSessionsProvider(billingListQuery));
      ref.invalidate(adminBillingAuditLogsProvider(billingListQuery));
    }

    return billingAsync.when(
      data: (status) => RefreshIndicator(
        onRefresh: refreshLicense,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CompanyLicenseHeader(status: status),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 1000;
                  final license = _LicenseDetailCard(status: status);
                  final billing = _BillingReadOnlyCard(status: status);
                  if (compact) {
                    return Column(
                      children: [license, const SizedBox(height: 16), billing],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: license),
                      const SizedBox(width: 16),
                      Expanded(child: billing),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              _EntitlementsCard(plan: status.license?.plan),
              const SizedBox(height: 16),
              const _SecurityCard(),
              const SizedBox(height: 16),
              _PlaceholderActions(
                companyId: companyId,
                onApplied: refreshLicense,
              ),
              const SizedBox(height: 16),
              auditLogsAsync.when(
                data: (logs) => _BillingAdminHistorySection(
                  logs: logs.items,
                  onRefresh: () => ref.invalidate(
                    adminBillingAuditLogsProvider(billingListQuery),
                  ),
                ),
                loading: () => const AdminSurface(
                  title: 'Historico administrativo',
                  child: LinearProgressIndicator(),
                ),
                error: (error, _) => AdminSurface(
                  title: 'Historico administrativo',
                  subtitle: _safeError(error),
                  trailing: IconButton(
                    tooltip: 'Atualizar historico',
                    onPressed: () => ref.invalidate(
                      adminBillingAuditLogsProvider(billingListQuery),
                    ),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                  child: const Text(
                    'Historico administrativo indisponivel nesta versao.',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              eventsAsync.when(
                data: (events) => _BillingEventsSection(events: events.items),
                loading: () => const AdminSurface(
                  title: 'Eventos de billing',
                  child: LinearProgressIndicator(),
                ),
                error: (error, _) => AdminSurface(
                  title: 'Eventos de billing',
                  subtitle: _safeError(error),
                  child: const Text(
                    'Eventos de billing indisponiveis nesta versao.',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              checkoutAsync.when(
                data: (sessions) =>
                    _CheckoutSessionsSection(sessions: sessions.items),
                loading: () => const AdminSurface(
                  title: 'Sessoes de checkout',
                  child: LinearProgressIndicator(),
                ),
                error: (error, _) => AdminSurface(
                  title: 'Sessoes de checkout',
                  subtitle: _safeError(error),
                  child: const Text(
                    'Sessoes de checkout indisponiveis nesta versao.',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _InvoicesSection(invoices: status.invoices),
            ],
          ),
        ),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => AdminSurface(
        title: 'Nao foi possivel carregar a licenca',
        subtitle: _safeError(error),
        trailing: FilledButton.tonalIcon(
          onPressed: () =>
              ref.invalidate(adminBillingCompanyStatusProvider(companyId)),
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Tentar novamente'),
        ),
        child: const Text(
          'Erro amigavel: nenhum payload sensivel foi exibido.',
        ),
      ),
    );
  }
}

class _CompanyLicenseHeader extends StatelessWidget {
  const _CompanyLicenseHeader({required this.status});

  final AdminBillingCompanyStatus status;

  @override
  Widget build(BuildContext context) {
    final license = status.license;
    final billing = status.billing;
    return AdminSurface(
      title: status.companyName,
      subtitle:
          'Licenca e assinatura em modo read-only. CompanyId ${_maskIdentifier(status.companyId)}.',
      trailing: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: () => context.go('/companies/${status.companyId}'),
            icon: const Icon(Icons.business_rounded),
            label: const Text('Voltar para empresa'),
          ),
          OutlinedButton.icon(
            onPressed: () => context.go('/licenses'),
            icon: const Icon(Icons.list_alt_rounded),
            label: const Text('Todas as licencas'),
          ),
          OutlinedButton.icon(
            onPressed: () => context.go('/plans'),
            icon: const Icon(Icons.view_module_rounded),
            label: const Text('Ver matriz de planos'),
          ),
          OutlinedButton.icon(
            onPressed: () => context.go('/billing/${status.companyId}'),
            icon: const Icon(Icons.admin_panel_settings_rounded),
            label: const Text('Abrir billing avancado'),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(
                label: Text(
                  'Plano ativo: ${AdminFormatters.formatPlan(license?.plan ?? 'FREE')}',
                ),
              ),
              Chip(
                label: Text(
                  AdminFormatters.formatLicenseStatus(license?.status),
                ),
              ),
              if (license?.pendingPlan != null || billing.pendingPlan != null)
                Chip(
                  label: Text(
                    'Mudanca pendente: ${AdminFormatters.formatPlan((license?.pendingPlan ?? billing.pendingPlan)!)}',
                  ),
                ),
              if (billing.cancelAtPeriodEnd)
                const Chip(label: Text('Cancelamento agendado')),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => context.go(
              '/audit?companyId=${status.companyId}&category=billing',
            ),
            icon: const Icon(Icons.fact_check_rounded),
            label: const Text('Ver auditoria global filtrada'),
          ),
          const SizedBox(height: 12),
          Text(
            'Billing executa suporte operacional real. Use apenas para suporte operacional.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _LicenseDetailCard extends StatelessWidget {
  const _LicenseDetailCard({required this.status});

  final AdminBillingCompanyStatus status;

  @override
  Widget build(BuildContext context) {
    final license = status.license;
    return AdminSurface(
      title: 'Licenca',
      subtitle: 'license.plan e a fonte de verdade para entitlement.',
      child: license == null
          ? const _EmptyState(message: 'Empresa sem licenca cadastrada.')
          : Column(
              children: [
                _DetailRow(
                  label: 'Plano ativo',
                  value: AdminFormatters.formatPlan(license.plan),
                ),
                _DetailRow(
                  label: 'Status',
                  value: AdminFormatters.formatLicenseStatus(license.status),
                ),
                _DetailRow(
                  label: 'Mudanca pendente',
                  value: license.pendingPlan == null
                      ? 'Nenhuma'
                      : AdminFormatters.formatPlan(license.pendingPlan!),
                ),
                _DetailRow(
                  label: 'Solicitada em',
                  value: AdminFormatters.formatDateTime(
                    license.pendingPlanRequestedAt,
                  ),
                ),
                _DetailRow(
                  label: 'Inicio',
                  value: AdminFormatters.formatDate(license.startsAt),
                ),
                _DetailRow(
                  label: 'Vencimento',
                  value: AdminFormatters.formatDate(license.expiresAt),
                ),
                _DetailRow(
                  label: 'Max dispositivos',
                  value: license.maxDevices?.toString() ?? 'Nao disponivel',
                ),
                _DetailRow(
                  label: 'Sync cloud',
                  value: AdminFormatters.formatBool(
                    license.syncEnabled,
                    yes: 'Habilitada',
                    no: 'Desativada',
                  ),
                ),
                _DetailRow(
                  label: 'Criada em',
                  value: AdminFormatters.formatDateTime(license.createdAt),
                ),
                _DetailRow(
                  label: 'Atualizada em',
                  value: AdminFormatters.formatDateTime(license.updatedAt),
                ),
              ],
            ),
    );
  }
}

class _BillingReadOnlyCard extends StatelessWidget {
  const _BillingReadOnlyCard({required this.status});

  final AdminBillingCompanyStatus status;

  @override
  Widget build(BuildContext context) {
    final billing = status.billing;
    return AdminSurface(
      title: 'Assinatura/Billing',
      subtitle: 'Status do provider separado do status da licenca.',
      child: Column(
        children: [
          _DetailRow(
            label: 'Provider',
            value: billing.provider ?? 'Sem assinatura provider',
          ),
          _DetailRow(
            label: 'Status assinatura',
            value: _billingStatusLabel(billing.billingSubscriptionStatus),
          ),
          _DetailRow(
            label: 'Assinatura provider',
            value:
                billing.maskedProviderSubscriptionId ??
                'Sem assinatura provider',
          ),
          _DetailRow(
            label: 'Inicio do periodo',
            value: AdminFormatters.formatDate(billing.currentPeriodStart),
          ),
          _DetailRow(
            label: 'Fim do periodo',
            value: AdminFormatters.formatDate(billing.currentPeriodEnd),
          ),
          _DetailRow(
            label: 'Proxima cobranca',
            value: AdminFormatters.formatDate(billing.nextPaymentDate),
          ),
          _DetailRow(
            label: 'Cancelamento',
            value: billing.cancelAtPeriodEnd
                ? 'Cancelamento agendado'
                : 'Nao agendado',
          ),
          _DetailRow(
            label: 'Solicitado em',
            value: AdminFormatters.formatDateTime(billing.cancelRequestedAt),
          ),
          _DetailRow(
            label: 'Cancelada em',
            value: AdminFormatters.formatDateTime(billing.canceledAt),
          ),
        ],
      ),
    );
  }
}

class _EntitlementsCard extends StatelessWidget {
  const _EntitlementsCard({required this.plan});

  final String? plan;

  @override
  Widget build(BuildContext context) {
    final matrix = _planMatrix(plan);
    return AdminSurface(
      title: 'Entitlements',
      subtitle: 'Recursos liberados pelo plano ativo, sem usar pendingPlan.',
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _MiniMetric(label: 'Plano ativo', value: matrix.plan),
          _MiniMetric(label: 'Funcionarios', value: matrix.employees),
          _MiniMetric(label: 'Owner Web Panel', value: matrix.ownerWebPanel),
          _MiniMetric(label: 'Dispositivos', value: matrix.devices),
          _MiniMetric(label: 'Relatorios', value: matrix.reports),
          _MiniMetric(label: 'Compras/estoque', value: matrix.stock),
        ],
      ),
    );
  }
}

class _SecurityCard extends StatelessWidget {
  const _SecurityCard();

  @override
  Widget build(BuildContext context) {
    return const AdminSurface(
      title: 'Seguranca',
      subtitle: 'Separacao entre plano ativo e mudanca pendente.',
      child: Text(
        'O plano ativo vem de license.plan. pendingPlan nao libera recursos.',
      ),
    );
  }
}

class _PlaceholderActions extends StatelessWidget {
  const _PlaceholderActions({required this.companyId, required this.onApplied});

  final String companyId;
  final Future<void> Function() onApplied;

  @override
  Widget build(BuildContext context) {
    return AdminSurface(
      title: 'Proximos passos',
      subtitle:
          'Extensao emergencial e reconciliacao de billing seguem dry-run, motivo, confirmacao explicita e auditoria. Demais acoes permanecem placeholder.',
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          FilledButton.icon(
            onPressed: () => _openEmergencyExtension(context),
            icon: const Icon(Icons.event_available_rounded),
            label: const Text('Extensao emergencial'),
          ),
          const _PlaceholderButton(
            label: 'Trocar plano',
            icon: Icons.swap_horiz_rounded,
          ),
          OutlinedButton.icon(
            onPressed: () => _openLicenseStatusAction(
              context,
              action: _LicenseStatusAction.suspend,
            ),
            icon: const Icon(Icons.lock_rounded),
            label: const Text('Suspender licenca'),
          ),
          OutlinedButton.icon(
            onPressed: () => _openLicenseStatusAction(
              context,
              action: _LicenseStatusAction.reactivate,
            ),
            icon: const Icon(Icons.lock_open_rounded),
            label: const Text('Reativar licenca'),
          ),
          OutlinedButton.icon(
            onPressed: () => _openBillingReconcile(context),
            icon: const Icon(Icons.receipt_long_rounded),
            label: const Text('Reconciliar Mercado Pago'),
          ),
        ],
      ),
    );
  }

  Future<void> _openEmergencyExtension(BuildContext context) async {
    final applied = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _EmergencyExtensionDialog(companyId: companyId),
    );
    if (applied == true) {
      await onApplied();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Extensao emergencial aplicada.')),
        );
      }
    }
  }

  Future<void> _openLicenseStatusAction(
    BuildContext context, {
    required _LicenseStatusAction action,
  }) async {
    final applied = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _LicenseStatusActionDialog(companyId: companyId, action: action),
    );
    if (applied == true) {
      await onApplied();
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(action.successMessage)));
      }
    }
  }

  Future<void> _openBillingReconcile(BuildContext context) async {
    final applied = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _BillingReconcileDialog(companyId: companyId),
    );
    if (applied == true) {
      await onApplied();
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Billing reconciliado.')));
      }
    }
  }
}

enum _LicenseStatusAction { suspend, reactivate }

extension _LicenseStatusActionText on _LicenseStatusAction {
  String get title {
    switch (this) {
      case _LicenseStatusAction.suspend:
        return 'Suspender licenca';
      case _LicenseStatusAction.reactivate:
        return 'Reativar licenca';
    }
  }

  String get expectedConfirmationText {
    switch (this) {
      case _LicenseStatusAction.suspend:
        return 'SUSPENDER';
      case _LicenseStatusAction.reactivate:
        return 'REATIVAR';
    }
  }

  String get confirmButtonLabel {
    switch (this) {
      case _LicenseStatusAction.suspend:
        return 'Confirmar suspensao';
      case _LicenseStatusAction.reactivate:
        return 'Confirmar reativacao';
    }
  }

  String get successMessage {
    switch (this) {
      case _LicenseStatusAction.suspend:
        return 'Licenca suspensa.';
      case _LicenseStatusAction.reactivate:
        return 'Licenca reativada.';
    }
  }
}

class _LicenseStatusActionDialog extends ConsumerStatefulWidget {
  const _LicenseStatusActionDialog({
    required this.companyId,
    required this.action,
  });

  final String companyId;
  final _LicenseStatusAction action;

  @override
  ConsumerState<_LicenseStatusActionDialog> createState() =>
      _LicenseStatusActionDialogState();
}

class _LicenseStatusActionDialogState
    extends ConsumerState<_LicenseStatusActionDialog> {
  final _reasonController = TextEditingController();
  final _noteController = TextEditingController();
  final _confirmationController = TextEditingController();
  AdminLicenseStatusActionDryRun? _dryRun;
  String? _error;
  bool _loadingDryRun = false;
  bool _submitting = false;

  @override
  void dispose() {
    _reasonController.dispose();
    _noteController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final expected =
        _dryRun?.expectedConfirmationText ??
        widget.action.expectedConfirmationText;
    final reasonFilled = _reasonController.text.trim().isNotEmpty;
    final confirmationMatches = _confirmationController.text.trim() == expected;
    final canSubmit =
        !_submitting &&
        _dryRun?.allowed == true &&
        reasonFilled &&
        confirmationMatches;

    return AlertDialog(
      title: Text(widget.action.title),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Esta acao altera somente o estado administrativo da licenca. Ela nao altera plano, pendingPlan, Mercado Pago, providerSubscriptionId ou currentPeriodEnd.',
              ),
              const SizedBox(height: 8),
              const Text(
                'license.plan continua sendo a fonte real do plano ativo; pendingPlan nao libera recursos.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _reasonController,
                decoration: const InputDecoration(
                  labelText: 'Motivo obrigatorio',
                ),
                minLines: 2,
                maxLines: 3,
                onChanged: (_) => setState(() => _dryRun = null),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _noteController,
                decoration: const InputDecoration(labelText: 'Nota opcional'),
                onChanged: (_) => setState(() => _dryRun = null),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _loadingDryRun ? null : _runDryRun,
                icon: _loadingDryRun
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.fact_check_rounded),
                label: const Text('Simular dry-run'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (_dryRun != null) ...[
                const SizedBox(height: 16),
                _LicenseStatusActionPreview(dryRun: _dryRun!),
                const SizedBox(height: 12),
                TextField(
                  controller: _confirmationController,
                  decoration: InputDecoration(
                    labelText: 'Texto de confirmacao',
                    helperText: confirmationMatches
                        ? 'Confirmacao correta.'
                        : 'Digite $expected para liberar a confirmacao.',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: canSubmit ? _submit : null,
          icon: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check_rounded),
          label: Text(widget.action.confirmButtonLabel),
        ),
      ],
    );
  }

  Future<void> _runDryRun() async {
    if (_reasonController.text.trim().isEmpty) {
      setState(() => _error = 'Informe o motivo da acao administrativa.');
      return;
    }
    setState(() {
      _loadingDryRun = true;
      _error = null;
      _dryRun = null;
      _confirmationController.clear();
    });
    try {
      final service = ref.read(adminApiServiceProvider);
      final result = widget.action == _LicenseStatusAction.suspend
          ? await service.dryRunLicenseSuspend(
              companyId: widget.companyId,
              reason: _reasonController.text,
              note: _noteController.text,
            )
          : await service.dryRunLicenseReactivate(
              companyId: widget.companyId,
              reason: _reasonController.text,
              note: _noteController.text,
            );
      if (mounted) {
        setState(() => _dryRun = result);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = _safeError(error));
      }
    } finally {
      if (mounted) {
        setState(() => _loadingDryRun = false);
      }
    }
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final service = ref.read(adminApiServiceProvider);
      if (widget.action == _LicenseStatusAction.suspend) {
        await service.applyLicenseSuspend(
          companyId: widget.companyId,
          reason: _reasonController.text,
          note: _noteController.text,
          confirmationText: _confirmationController.text,
        );
      } else {
        await service.applyLicenseReactivate(
          companyId: widget.companyId,
          reason: _reasonController.text,
          note: _noteController.text,
          confirmationText: _confirmationController.text,
        );
      }
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = _safeError(error));
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }
}

class _EmergencyExtensionDialog extends ConsumerStatefulWidget {
  const _EmergencyExtensionDialog({required this.companyId});

  final String companyId;

  @override
  ConsumerState<_EmergencyExtensionDialog> createState() =>
      _EmergencyExtensionDialogState();
}

class _EmergencyExtensionDialogState
    extends ConsumerState<_EmergencyExtensionDialog> {
  final _daysController = TextEditingController(text: '3');
  final _reasonController = TextEditingController();
  final _noteController = TextEditingController();
  final _confirmationController = TextEditingController();
  AdminLicenseExtensionDryRun? _dryRun;
  String? _error;
  bool _loadingDryRun = false;
  bool _submitting = false;

  @override
  void dispose() {
    _daysController.dispose();
    _reasonController.dispose();
    _noteController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final expected = _dryRun?.expectedConfirmationText ?? 'ESTENDER';
    final reasonFilled = _reasonController.text.trim().isNotEmpty;
    final days = int.tryParse(_daysController.text.trim());
    final daysValid = days != null && days >= 1 && days <= 7;
    final confirmationMatches = _confirmationController.text.trim() == expected;
    final canSubmit =
        !_submitting &&
        _dryRun?.allowed == true &&
        reasonFilled &&
        daysValid &&
        confirmationMatches;

    return AlertDialog(
      title: const Text('Extensao emergencial'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Esta acao nao troca o plano da empresa, nao altera Mercado Pago e nao usa pendingPlan como entitlement ativo.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _daysController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Dias',
                  helperText: 'Permitido: 1 a 7 dias.',
                ),
                onChanged: (_) => setState(() => _dryRun = null),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _reasonController,
                decoration: const InputDecoration(
                  labelText: 'Motivo obrigatorio',
                ),
                minLines: 2,
                maxLines: 3,
                onChanged: (_) => setState(() => _dryRun = null),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _noteController,
                decoration: const InputDecoration(labelText: 'Nota opcional'),
                onChanged: (_) => setState(() => _dryRun = null),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _loadingDryRun ? null : _runDryRun,
                icon: _loadingDryRun
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.fact_check_rounded),
                label: const Text('Simular dry-run'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (_dryRun != null) ...[
                const SizedBox(height: 16),
                _DryRunPreview(dryRun: _dryRun!),
                const SizedBox(height: 12),
                TextField(
                  controller: _confirmationController,
                  decoration: InputDecoration(
                    labelText: 'Texto de confirmacao',
                    helperText: confirmationMatches
                        ? 'Confirmacao correta.'
                        : 'Digite $expected para liberar a confirmacao.',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: canSubmit ? _submit : null,
          icon: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check_rounded),
          label: const Text('Confirmar extensao'),
        ),
      ],
    );
  }

  Future<void> _runDryRun() async {
    final days = int.tryParse(_daysController.text.trim());
    if (days == null || days < 1 || days > 7) {
      setState(() => _error = 'Informe dias entre 1 e 7.');
      return;
    }
    if (_reasonController.text.trim().isEmpty) {
      setState(() => _error = 'Informe o motivo da acao administrativa.');
      return;
    }
    setState(() {
      _loadingDryRun = true;
      _error = null;
      _dryRun = null;
      _confirmationController.clear();
    });
    try {
      final result = await ref
          .read(adminApiServiceProvider)
          .dryRunLicenseEmergencyExtension(
            companyId: widget.companyId,
            days: days,
            reason: _reasonController.text,
            note: _noteController.text,
          );
      if (mounted) {
        setState(() => _dryRun = result);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = _safeError(error));
      }
    } finally {
      if (mounted) {
        setState(() => _loadingDryRun = false);
      }
    }
  }

  Future<void> _submit() async {
    final days = int.tryParse(_daysController.text.trim());
    if (days == null) {
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(adminApiServiceProvider)
          .applyLicenseEmergencyExtension(
            companyId: widget.companyId,
            days: days,
            reason: _reasonController.text,
            note: _noteController.text,
            confirmationText: _confirmationController.text,
          );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = _safeError(error));
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }
}

class _BillingReconcileDialog extends ConsumerStatefulWidget {
  const _BillingReconcileDialog({required this.companyId});

  final String companyId;

  @override
  ConsumerState<_BillingReconcileDialog> createState() =>
      _BillingReconcileDialogState();
}

class _BillingReconcileDialogState
    extends ConsumerState<_BillingReconcileDialog> {
  final _reasonController = TextEditingController();
  final _noteController = TextEditingController();
  final _confirmationController = TextEditingController();
  AdminBillingReconcileDryRun? _dryRun;
  String? _error;
  bool _loadingDryRun = false;
  bool _submitting = false;

  @override
  void dispose() {
    _reasonController.dispose();
    _noteController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final expected = _dryRun?.expectedConfirmationText ?? 'RECONCILIAR';
    final reasonFilled = _reasonController.text.trim().isNotEmpty;
    final confirmationMatches = _confirmationController.text.trim() == expected;
    final canSubmit =
        !_submitting &&
        _dryRun?.allowed == true &&
        reasonFilled &&
        confirmationMatches;

    return AlertDialog(
      title: const Text('Reconciliar Mercado Pago'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Esta acao consulta/reconcilia o estado de billing pelo fluxo seguro existente. Ela nao forca troca manual de plano e nao edita providerSubscriptionId manualmente.',
              ),
              const SizedBox(height: 8),
              const Text(
                'license.plan continua sendo a fonte real de entitlement; pendingPlan nao libera recursos ate confirmacao segura.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _reasonController,
                decoration: const InputDecoration(
                  labelText: 'Motivo obrigatorio',
                ),
                minLines: 2,
                maxLines: 3,
                onChanged: (_) => setState(() => _dryRun = null),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _noteController,
                decoration: const InputDecoration(labelText: 'Nota opcional'),
                onChanged: (_) => setState(() => _dryRun = null),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _loadingDryRun ? null : _runDryRun,
                icon: _loadingDryRun
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.fact_check_rounded),
                label: const Text('Simular dry-run'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (_dryRun != null) ...[
                const SizedBox(height: 16),
                _BillingReconcilePreview(dryRun: _dryRun!),
                const SizedBox(height: 12),
                TextField(
                  controller: _confirmationController,
                  decoration: InputDecoration(
                    labelText: 'Texto de confirmacao',
                    helperText: confirmationMatches
                        ? 'Confirmacao correta.'
                        : 'Digite $expected para liberar a confirmacao.',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: canSubmit ? _submit : null,
          icon: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check_rounded),
          label: const Text('Confirmar reconciliacao'),
        ),
      ],
    );
  }

  Future<void> _runDryRun() async {
    if (_reasonController.text.trim().isEmpty) {
      setState(() => _error = 'Informe o motivo da acao administrativa.');
      return;
    }
    setState(() {
      _loadingDryRun = true;
      _error = null;
      _dryRun = null;
      _confirmationController.clear();
    });
    try {
      final result = await ref
          .read(adminApiServiceProvider)
          .dryRunBillingReconcile(
            companyId: widget.companyId,
            reason: _reasonController.text,
            note: _noteController.text,
          );
      if (mounted) {
        setState(() => _dryRun = result);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = _safeError(error));
      }
    } finally {
      if (mounted) {
        setState(() => _loadingDryRun = false);
      }
    }
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(adminApiServiceProvider)
          .applyBillingReconcile(
            companyId: widget.companyId,
            reason: _reasonController.text,
            note: _noteController.text,
            confirmationText: _confirmationController.text,
          );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = _safeError(error));
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }
}

class _DryRunPreview extends StatelessWidget {
  const _DryRunPreview({required this.dryRun});

  final AdminLicenseExtensionDryRun dryRun;

  @override
  Widget build(BuildContext context) {
    final proposed = dryRun.proposedChange;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(dryRun.summary),
          const SizedBox(height: 8),
          Text('Confirmacao exigida: ${dryRun.expectedConfirmationText}'),
          if (proposed != null) ...[
            const SizedBox(height: 8),
            Text(
              'expiresAt: ${proposed['expiresAtBefore'] ?? 'sem data'} -> ${proposed['expiresAtAfter'] ?? 'nao disponivel'}',
            ),
            Text(
              'Plano: ${proposed['planBefore']} -> ${proposed['planAfter']}',
            ),
            Text(
              'PendingPlan: ${proposed['pendingPlanBefore'] ?? 'nenhum'} -> ${proposed['pendingPlanAfter'] ?? 'nenhum'}',
            ),
          ],
          if (dryRun.risks.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('Riscos/garantias:'),
            ...dryRun.risks.map((risk) => Text('- $risk')),
          ],
          if (dryRun.blockers.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Bloqueios:',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            ...dryRun.blockers.map((blocker) => Text('- $blocker')),
          ],
        ],
      ),
    );
  }
}

class _LicenseStatusActionPreview extends StatelessWidget {
  const _LicenseStatusActionPreview({required this.dryRun});

  final AdminLicenseStatusActionDryRun dryRun;

  @override
  Widget build(BuildContext context) {
    final proposed = dryRun.proposedChange;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(dryRun.summary),
          const SizedBox(height: 8),
          Text('Confirmacao exigida: ${dryRun.expectedConfirmationText}'),
          if (proposed != null) ...[
            const SizedBox(height: 8),
            Text(
              'Status: ${proposed['statusBefore'] ?? 'nao disponivel'} -> ${proposed['statusAfter'] ?? 'nao disponivel'}',
            ),
            Text(
              'Plano: ${proposed['planBefore']} -> ${proposed['planAfter']}',
            ),
            Text(
              'PendingPlan: ${proposed['pendingPlanBefore'] ?? 'nenhum'} -> ${proposed['pendingPlanAfter'] ?? 'nenhum'}',
            ),
            Text(
              'currentPeriodEnd: ${proposed['currentPeriodEndBefore'] ?? 'sem data'} -> ${proposed['currentPeriodEndAfter'] ?? 'sem data'}',
            ),
          ],
          if (dryRun.risks.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('Riscos/garantias:'),
            ...dryRun.risks.map((risk) => Text('- $risk')),
          ],
          if (dryRun.blockers.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Bloqueios:',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            ...dryRun.blockers.map((blocker) => Text('- $blocker')),
          ],
        ],
      ),
    );
  }
}

class _BillingReconcilePreview extends StatelessWidget {
  const _BillingReconcilePreview({required this.dryRun});

  final AdminBillingReconcileDryRun dryRun;

  @override
  Widget build(BuildContext context) {
    final current = dryRun.currentBillingStatus;
    final provider = dryRun.providerCheckSummary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(dryRun.summary),
          const SizedBox(height: 8),
          Text('Confirmacao exigida: ${dryRun.expectedConfirmationText}'),
          if (current != null) ...[
            const SizedBox(height: 8),
            const Text('Status atual seguro:'),
            Text('Plano ativo: ${_previewValue(current['plan'])}'),
            Text('PendingPlan: ${_previewValue(current['pendingPlan'])}'),
            Text('Status: ${_previewValue(current['status'])}'),
            Text(
              'Assinatura provider: ${_previewValue(current['maskedProviderSubscriptionId'])}',
            ),
          ],
          if (provider != null) ...[
            const SizedBox(height: 8),
            const Text('Resumo provider:'),
            Text(
              'Provider: ${_previewValue(provider['provider'] ?? provider['billingProvider'])}',
            ),
            Text(
              'Referencia: ${_previewValue(provider['maskedProviderSubscriptionId'] ?? provider['providerSubscriptionId'])}',
            ),
            Text('Consulta externa: ${_previewValue(provider['consulted'])}'),
          ],
          if (dryRun.pendingCheckoutSessions.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('Sessoes pendentes:'),
            ...dryRun.pendingCheckoutSessions
                .take(4)
                .map(
                  (session) => Text(
                    '- ${_previewValue(session['plan'])} / ${_previewValue(session['status'])} / ${_previewValue(session['maskedProviderReference'] ?? session['providerReference'])}',
                  ),
                ),
          ],
          if (dryRun.likelyActions.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('Acoes provaveis:'),
            ...dryRun.likelyActions.map((action) => Text('- $action')),
          ],
          if (dryRun.risks.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('Riscos/garantias:'),
            ...dryRun.risks.map((risk) => Text('- $risk')),
          ],
          if (dryRun.blockers.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Bloqueios:',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            ...dryRun.blockers.map((blocker) => Text('- $blocker')),
          ],
        ],
      ),
    );
  }
}

class _BillingAdminHistorySection extends StatelessWidget {
  const _BillingAdminHistorySection({
    required this.logs,
    required this.onRefresh,
  });

  final List<AdminBillingAuditLog> logs;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return AdminSurface(
      title: 'Historico administrativo',
      subtitle:
          'Acoes feitas por platform admin. Eventos do provider aparecem em "Eventos de billing".',
      trailing: TextButton.icon(
        onPressed: onRefresh,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Atualizar historico'),
      ),
      child: logs.isEmpty
          ? const _EmptyState(
              message: 'Nenhuma acao administrativa de licenca registrada.',
            )
          : Column(
              children: logs
                  .map((log) => _BillingAdminHistoryTile(log: log))
                  .toList(growable: false),
            ),
    );
  }
}

class _BillingAdminHistoryTile extends StatelessWidget {
  const _BillingAdminHistoryTile({required this.log});

  final AdminBillingAuditLog log;

  @override
  Widget build(BuildContext context) {
    final actor = _billingAuditActorLabel(log);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.admin_panel_settings_rounded),
      title: Text(_billingAuditActionLabel(log.action)),
      subtitle: Text(
        [
          AdminFormatters.formatDateTime(log.createdAt),
          'Ator: $actor',
          'Motivo: ${_safeShort(log.reason)}',
          _billingAuditChangeSummary(log),
        ].join('\n'),
      ),
      isThreeLine: true,
      trailing: TextButton.icon(
        onPressed: () => _showBillingAuditDetails(context, log),
        icon: const Icon(Icons.visibility_rounded),
        label: const Text('Ver detalhes'),
      ),
    );
  }
}

class _BillingEventsSection extends StatelessWidget {
  const _BillingEventsSection({required this.events});

  final List<AdminBillingEvent> events;

  @override
  Widget build(BuildContext context) {
    return AdminSurface(
      title: 'Eventos de billing',
      subtitle: 'Payload sanitizado pelo backend e novamente no admin_web.',
      child: events.isEmpty
          ? const _EmptyState(message: 'Nenhum evento de billing encontrado.')
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Criado em')),
                  DataColumn(label: Text('Provider')),
                  DataColumn(label: Text('Evento')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Provider event')),
                  DataColumn(label: Text('Processado em')),
                  DataColumn(label: Text('Erro')),
                  DataColumn(label: Text('Detalhes')),
                ],
                rows: events
                    .map(
                      (event) => DataRow(
                        cells: [
                          DataCell(
                            Text(
                              AdminFormatters.formatDateTime(event.createdAt),
                            ),
                          ),
                          DataCell(Text(event.provider)),
                          DataCell(Text(event.eventType)),
                          DataCell(Text(event.status)),
                          DataCell(
                            Text(_maskIdentifier(event.providerEventId)),
                          ),
                          DataCell(
                            Text(
                              AdminFormatters.formatDateTime(event.processedAt),
                            ),
                          ),
                          DataCell(Text(_safeShort(event.errorMessage))),
                          DataCell(
                            TextButton.icon(
                              onPressed: () => _showSafeDetails(
                                context,
                                title: 'Evento de billing',
                                value: event.payload,
                              ),
                              icon: const Icon(Icons.visibility_rounded),
                              label: const Text('Detalhes'),
                            ),
                          ),
                        ],
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
    );
  }
}

class _CheckoutSessionsSection extends StatelessWidget {
  const _CheckoutSessionsSection({required this.sessions});

  final List<AdminBillingCheckoutSession> sessions;

  @override
  Widget build(BuildContext context) {
    return AdminSurface(
      title: 'Sessoes de checkout',
      subtitle: 'Tentativas de contratacao/alteracao sem URLs sensiveis.',
      child: sessions.isEmpty
          ? const _EmptyState(message: 'Nenhuma sessao de checkout encontrada.')
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Plano')),
                  DataColumn(label: Text('Ciclo')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Provider')),
                  DataColumn(label: Text('Referencia')),
                  DataColumn(label: Text('Criada em')),
                  DataColumn(label: Text('Atualizada em')),
                ],
                rows: sessions
                    .map(
                      (session) => DataRow(
                        cells: [
                          DataCell(
                            Text(AdminFormatters.formatPlan(session.plan)),
                          ),
                          DataCell(
                            Text(session.billingCycle ?? 'Nao informado'),
                          ),
                          DataCell(Text(_checkoutStatusLabel(session.status))),
                          DataCell(Text(session.provider ?? 'Nao informado')),
                          DataCell(
                            Text(_maskIdentifier(session.providerReference)),
                          ),
                          DataCell(
                            Text(
                              AdminFormatters.formatDateTime(session.createdAt),
                            ),
                          ),
                          DataCell(
                            Text(
                              AdminFormatters.formatDateTime(session.updatedAt),
                            ),
                          ),
                        ],
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
    );
  }
}

class _InvoicesSection extends StatelessWidget {
  const _InvoicesSection({required this.invoices});

  final List<AdminBillingInvoiceSummary> invoices;

  @override
  Widget build(BuildContext context) {
    return AdminSurface(
      title: 'Faturas',
      subtitle: invoices.isEmpty
          ? 'Faturas administrativas serao exibidas aqui quando o endpoint estiver disponivel.'
          : 'Ultimas faturas retornadas pelo status administrativo.',
      child: invoices.isEmpty
          ? const _EmptyState(
              message:
                  'Faturas administrativas serao exibidas aqui quando o endpoint estiver disponivel.',
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Periodo')),
                  DataColumn(label: Text('Valor')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Provider')),
                  DataColumn(label: Text('Invoice provider')),
                  DataColumn(label: Text('Vencimento')),
                  DataColumn(label: Text('Pago em')),
                  DataColumn(label: Text('URL')),
                ],
                rows: invoices
                    .map(
                      (invoice) => DataRow(
                        cells: [
                          DataCell(
                            Text(
                              '${AdminFormatters.formatDate(invoice.periodStart)} - ${AdminFormatters.formatDate(invoice.periodEnd)}',
                            ),
                          ),
                          DataCell(
                            Text(
                              '${invoice.currency} ${(invoice.amountCents / 100).toStringAsFixed(2)}',
                            ),
                          ),
                          DataCell(Text(invoice.status)),
                          DataCell(Text(invoice.provider)),
                          DataCell(
                            Text(_maskIdentifier(invoice.providerInvoiceId)),
                          ),
                          DataCell(
                            Text(AdminFormatters.formatDate(invoice.dueAt)),
                          ),
                          DataCell(
                            Text(AdminFormatters.formatDate(invoice.paidAt)),
                          ),
                          DataCell(
                            Text(invoice.invoiceUrl ?? 'Nao disponivel'),
                          ),
                        ],
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
    );
  }
}

class _Filters extends StatefulWidget {
  const _Filters({
    required this.searchController,
    required this.filter,
    required this.onApply,
    required this.onClear,
  });

  final TextEditingController searchController;
  final _LicenseListFilter filter;
  final ValueChanged<_LicenseListFilter> onApply;
  final VoidCallback onClear;

  @override
  State<_Filters> createState() => _FiltersState();
}

class _FiltersState extends State<_Filters> {
  late _LicenseListFilter _filter = widget.filter;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 280,
          child: TextField(
            controller: widget.searchController,
            decoration: const InputDecoration(
              labelText: 'Buscar empresa',
              prefixIcon: Icon(Icons.search_rounded),
            ),
            onSubmitted: (_) => widget.onApply(_filter),
          ),
        ),
        DropdownButton<_LicenseListFilter>(
          value: _filter,
          items: const [
            DropdownMenuItem(
              value: _LicenseListFilter.all,
              child: Text('Todas'),
            ),
            DropdownMenuItem(
              value: _LicenseListFilter.free,
              child: Text('FREE'),
            ),
            DropdownMenuItem(
              value: _LicenseListFilter.basic,
              child: Text('BASIC'),
            ),
            DropdownMenuItem(value: _LicenseListFilter.pro, child: Text('PRO')),
            DropdownMenuItem(
              value: _LicenseListFilter.active,
              child: Text('Ativas'),
            ),
            DropdownMenuItem(
              value: _LicenseListFilter.pendingPlan,
              child: Text('Com pendingPlan'),
            ),
            DropdownMenuItem(
              value: _LicenseListFilter.cancelScheduled,
              child: Text('Cancelamento agendado'),
            ),
            DropdownMenuItem(
              value: _LicenseListFilter.billingError,
              child: Text('Com erro de billing'),
            ),
          ],
          onChanged: (value) {
            if (value != null) {
              setState(() => _filter = value);
            }
          },
        ),
        FilledButton.icon(
          onPressed: () => widget.onApply(_filter),
          icon: const Icon(Icons.filter_alt_rounded),
          label: const Text('Aplicar'),
        ),
        TextButton(onPressed: widget.onClear, child: const Text('Limpar')),
      ],
    );
  }
}

class _ReadOnlyBanner extends StatelessWidget {
  const _ReadOnlyBanner();

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
      child: Text(
        'Modo seguro/read-only: license.plan e a fonte de verdade; pendingPlan aparece apenas como mudanca pendente. Acoes reais entram apenas em fase posterior.',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: scheme.onSecondaryContainer,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _PlaceholderButton extends StatelessWidget {
  const _PlaceholderButton({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: _placeholderMessage,
      child: OutlinedButton.icon(
        onPressed: () {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text(_placeholderMessage)));
        },
        icon: Icon(icon),
        label: Text('$label (placeholder)'),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text(label));
  }
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(child: Text(message, textAlign: TextAlign.center)),
    );
  }
}

class _PaginationBar extends StatelessWidget {
  const _PaginationBar({
    required this.pagination,
    required this.onPrevious,
    required this.onNext,
  });

  final AdminPaginationMeta pagination;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Pagina ${pagination.page}: ${pagination.count} de ${pagination.total} licencas.',
          ),
        ),
        IconButton(
          tooltip: 'Anterior',
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        IconButton(
          tooltip: 'Proxima',
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }
}

class _PlanEntitlementSummary {
  const _PlanEntitlementSummary({
    required this.plan,
    required this.employees,
    required this.ownerWebPanel,
    required this.devices,
    required this.reports,
    required this.stock,
  });

  final String plan;
  final String employees;
  final String ownerWebPanel;
  final String devices;
  final String reports;
  final String stock;
}

_PlanEntitlementSummary _planMatrix(String? plan) {
  switch ((plan ?? 'FREE').trim().toUpperCase()) {
    case 'PRO':
      return const _PlanEntitlementSummary(
        plan: 'PRO',
        employees: '100',
        ownerWebPanel: 'Liberado',
        devices: '100',
        reports: 'Avancados',
        stock: 'Liberado',
      );
    case 'BASIC':
      return const _PlanEntitlementSummary(
        plan: 'BASIC',
        employees: '0',
        ownerWebPanel: 'Nao liberado',
        devices: '1',
        reports: 'Padrao',
        stock: 'Liberado',
      );
    default:
      return const _PlanEntitlementSummary(
        plan: 'FREE',
        employees: '0',
        ownerWebPanel: 'Nao liberado',
        devices: '1',
        reports: 'Basico',
        stock: 'Nao liberado',
      );
  }
}

String? _planFilter(_LicenseListFilter filter) {
  switch (filter) {
    case _LicenseListFilter.free:
      return 'FREE';
    case _LicenseListFilter.basic:
      return 'BASIC';
    case _LicenseListFilter.pro:
      return 'PRO';
    case _:
      return null;
  }
}

String? _statusFilter(_LicenseListFilter filter) {
  return filter == _LicenseListFilter.active ? 'ACTIVE' : null;
}

bool _matchesLocalFilter(
  AdminBillingCompanySummary item,
  _LicenseListFilter filter,
) {
  switch (filter) {
    case _LicenseListFilter.pendingPlan:
      return item.pendingPlan != null;
    case _LicenseListFilter.cancelScheduled:
      return item.cancelAtPeriodEnd;
    case _LicenseListFilter.billingError:
      return _isBillingError(item.billingSubscriptionStatus);
    case _:
      return true;
  }
}

bool _isBillingError(String? status) {
  final value = status?.trim().toLowerCase() ?? '';
  return value.contains('error') ||
      value.contains('fail') ||
      value.contains('past_due') ||
      value.contains('rejected') ||
      value.contains('cancelled');
}

String _billingStatusLabel(String? status) {
  final value = status?.trim();
  if (value == null || value.isEmpty) {
    return 'Sem assinatura provider';
  }
  switch (value.toLowerCase()) {
    case 'authorized':
      return 'Assinatura autorizada';
    case 'pending':
      return 'Assinatura pendente';
    case 'paused':
      return 'Assinatura pausada';
    case 'cancelled':
    case 'cancelled_local':
      return 'Assinatura cancelada';
    case 'cancelled_local_period_end':
      return 'Cancelamento agendado';
    case 'past_due':
      return 'Pagamento em atraso';
    default:
      return value;
  }
}

String _checkoutStatusLabel(String status) {
  switch (status.trim().toLowerCase()) {
    case 'pending':
    case 'created':
      return 'Tentativa pendente';
    case 'completed':
      return 'Concluida';
    case 'rejected':
      return 'Rejeitada';
    case 'expired':
      return 'Expirada';
    case 'cancelled':
    case 'canceled':
      return 'Cancelada';
    default:
      return status;
  }
}

String _maskIdentifier(String? value) {
  final text = value?.trim();
  if (text == null || text.isEmpty) {
    return 'Nao informado';
  }
  if (text.contains('...') || text.length <= 12) {
    return text;
  }
  return '${text.substring(0, 4)}...${text.substring(text.length - 4)}';
}

String _safeShort(String? value) {
  final sanitized = sanitizeAdminBillingValue(value);
  final text = sanitized?.toString().trim();
  if (text == null || text.isEmpty) {
    return 'Nenhum';
  }
  return text.length > 80 ? '${text.substring(0, 80)}...' : text;
}

String _previewValue(Object? value) {
  final sanitized = sanitizeAdminBillingValue(value);
  final text = sanitized?.toString().trim();
  if (text == null || text.isEmpty || text == 'null') {
    return 'Nao disponivel';
  }
  return _maskIdentifier(text);
}

String _billingAuditActionLabel(String action) {
  switch (action.trim().toLowerCase()) {
    case 'license.emergency_extension':
      return 'Extensao emergencial';
    case 'billing.reconcile':
      return 'Reconciliacao de billing';
    case 'billing.reconcile.failed':
      return 'Falha na reconciliacao de billing';
    case 'license.suspend':
      return 'Suspensao de licenca';
    case 'license.reactivate':
      return 'Reativacao de licenca';
    default:
      return action.trim().isEmpty ? 'Acao administrativa' : action;
  }
}

String _billingAuditActorLabel(AdminBillingAuditLog log) {
  final name = log.actorName?.trim();
  if (name != null && name.isNotEmpty) {
    return name;
  }
  final email = log.actorEmail?.trim();
  if (email != null && email.isNotEmpty) {
    return email;
  }
  return _maskIdentifier(log.actorUserId);
}

String _billingAuditChangeSummary(AdminBillingAuditLog log) {
  final before = log.before ?? const <String, dynamic>{};
  final after = log.after ?? const <String, dynamic>{};
  final candidates = <String>[
    'status',
    'billingSubscriptionStatus',
    'expiresAt',
    'currentPeriodEnd',
  ];
  for (final key in candidates) {
    final beforeValue = before[key]?.toString();
    final afterValue = after[key]?.toString();
    if (beforeValue != afterValue && afterValue != null) {
      return '$key: ${_previewValue(beforeValue)} -> ${_previewValue(afterValue)}';
    }
  }
  return 'Alteracao administrativa registrada.';
}

void _showSafeDetails(
  BuildContext context, {
  required String title,
  required Object? value,
}) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: SelectableText(formatSafeLicenseBillingDetails(value ?? {})),
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

void _showBillingAuditDetails(BuildContext context, AdminBillingAuditLog log) {
  _showSafeDetails(
    context,
    title: 'Historico administrativo',
    value: {
      'aviso': 'Dados sensiveis sao omitidos por seguranca.',
      'acao': _billingAuditActionLabel(log.action),
      'motivo': log.reason,
      'ator': _billingAuditActorLabel(log),
      'criadoEm': log.createdAt?.toIso8601String(),
      'before': log.before,
      'after': log.after,
      'metadata': log.metadata,
      'ipAddress': log.ipAddress,
      'userAgent': log.userAgent,
    },
  );
}

String formatSafeLicenseBillingDetails(Object? value) {
  return formatSanitizedAdminJson(_dropSensitiveBillingKeys(value));
}

Object? _dropSensitiveBillingKeys(Object? value) {
  final sanitized = sanitizeAdminBillingValue(value);
  if (sanitized is List) {
    return sanitized.map(_dropSensitiveBillingKeys).toList(growable: false);
  }
  if (sanitized is Map) {
    final safe = <String, Object?>{};
    sanitized.forEach((key, rawValue) {
      final keyText = key.toString();
      if (_isSensitiveBillingPreviewKey(keyText)) {
        safe['campo_sensivel_removido'] = '[redacted]';
        return;
      }
      safe[keyText] = _dropSensitiveBillingKeys(rawValue);
    });
    return safe;
  }
  return sanitized;
}

bool _isSensitiveBillingPreviewKey(String key) {
  final normalized = key.trim().toLowerCase().replaceAll(
    RegExp(r'[\s\-_]'),
    '',
  );
  if (normalized.startsWith('maskedprovider')) {
    return false;
  }
  return normalized.contains('authorization') ||
      normalized.contains('header') ||
      normalized.contains('token') ||
      normalized.contains('secret') ||
      normalized.contains('apikey') ||
      normalized.contains('providersubscriptionid') ||
      normalized.contains('providerreference') ||
      normalized.contains('providereventid') ||
      normalized.contains('card') ||
      normalized.contains('cvv') ||
      normalized.contains('securitycode');
}

String _safeError(Object error) {
  final text = error.toString();
  if (text.contains('Exception:')) {
    return text.split('Exception:').last.trim();
  }
  return text.length > 180 ? '${text.substring(0, 180)}...' : text;
}
