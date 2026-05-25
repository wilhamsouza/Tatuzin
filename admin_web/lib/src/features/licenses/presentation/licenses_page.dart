import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/admin_providers.dart';
import '../../../core/models/admin_billing_models.dart';
import '../../../core/models/admin_models.dart';
import '../../../core/utils/admin_formatters.dart';
import '../../../core/widgets/admin_surface.dart';

const _placeholderMessage =
    'Acao administrativa sera implementada em fase posterior com dry-run, confirmacao e auditoria.';

class LicensesPage extends ConsumerStatefulWidget {
  const LicensesPage({super.key});

  @override
  ConsumerState<LicensesPage> createState() => _LicensesPageState();
}

class _LicensesPageState extends ConsumerState<LicensesPage> {
  late final TextEditingController _searchController;
  String? _status;
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
    final query = AdminLicensesQuery(
      page: _page,
      pageSize: 20,
      search: _searchController.text,
      status: _status,
      sortBy: 'expiresAt',
      sortDirection: 'asc',
    );
    final licensesAsync = ref.watch(adminLicensesProvider(query));

    return licensesAsync.when(
      data: (result) => RefreshIndicator(
        onRefresh: () async => ref.invalidate(adminLicensesProvider(query)),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: AdminSurface(
            title: 'Licencas read-only',
            subtitle:
                'Consulta de planos, validade e status. Nenhuma alteracao real e enviada nesta fase.',
            trailing: OutlinedButton.icon(
              onPressed: () => ref.invalidate(adminLicensesProvider(query)),
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
                  status: _status,
                  onApply: (status) => setState(() {
                    _status = status;
                    _page = 1;
                  }),
                  onClear: () {
                    _searchController.clear();
                    setState(() {
                      _status = null;
                      _page = 1;
                    });
                  },
                ),
                const SizedBox(height: 16),
                if (result.items.isEmpty)
                  const _EmptyState(
                    message: 'Nenhuma licenca encontrada para os filtros.',
                  )
                else
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Empresa')),
                        DataColumn(label: Text('Plano atual')),
                        DataColumn(label: Text('Status')),
                        DataColumn(label: Text('Vencimento')),
                        DataColumn(label: Text('Renovacao')),
                        DataColumn(label: Text('Sync')),
                        DataColumn(label: Text('Acoes')),
                      ],
                      rows: result.items
                          .map((license) {
                            return DataRow(
                              cells: [
                                DataCell(
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(license.companyName),
                                      Text(
                                        license.companySlug,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                  onTap: () => context.go(
                                    '/licenses/${license.companyId}',
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    AdminFormatters.formatPlan(license.plan),
                                  ),
                                ),
                                DataCell(
                                  _StatusChip(
                                    label: _statusLabel(license.status),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    AdminFormatters.formatDate(
                                      license.expiresAt,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Text(_renewalLabel(license.expiresAt)),
                                ),
                                DataCell(
                                  Text(
                                    AdminFormatters.formatBool(
                                      license.syncEnabled,
                                      yes: 'Habilitada',
                                      no: 'Desativada',
                                    ),
                                  ),
                                ),
                                DataCell(
                                  FilledButton.tonalIcon(
                                    onPressed: () => context.go(
                                      '/licenses/${license.companyId}',
                                    ),
                                    icon: const Icon(Icons.open_in_new_rounded),
                                    label: const Text('Abrir'),
                                  ),
                                ),
                              ],
                            );
                          })
                          .toList(growable: false),
                    ),
                  ),
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
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => AdminSurface(
        title: 'Nao foi possivel carregar licencas',
        subtitle: _safeError(error),
        trailing: FilledButton.tonalIcon(
          onPressed: () => ref.invalidate(adminLicensesProvider(query)),
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Tentar novamente'),
        ),
        child: const Text('Revise a conexao e tente novamente.'),
      ),
    );
  }
}

class LicenseCompanyPage extends ConsumerWidget {
  const LicenseCompanyPage({super.key, required this.companyId});

  final String companyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final companyAsync = ref.watch(adminCompanyDetailProvider(companyId));
    final billingAsync = ref.watch(
      adminBillingCompanyStatusProvider(companyId),
    );

    return companyAsync.when(
      data: (detail) => RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(adminCompanyDetailProvider(companyId));
          ref.invalidate(adminBillingCompanyStatusProvider(companyId));
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CompanyLicenseHeader(company: detail.company),
              const SizedBox(height: 16),
              _LicenseDetailCard(license: detail.company.license),
              const SizedBox(height: 16),
              billingAsync.when(
                data: (status) => _BillingReadOnlyCard(status: status),
                loading: () => const AdminSurface(
                  title: 'Billing',
                  child: LinearProgressIndicator(),
                ),
                error: (error, _) => AdminSurface(
                  title: 'Billing',
                  subtitle: _safeError(error),
                  child: const Text(
                    'Status de billing indisponivel no momento.',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const _PlaceholderActions(),
            ],
          ),
        ),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => AdminSurface(
        title: 'Nao foi possivel carregar a licenca',
        subtitle: _safeError(error),
        child: FilledButton.tonalIcon(
          onPressed: () =>
              ref.invalidate(adminCompanyDetailProvider(companyId)),
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Tentar novamente'),
        ),
      ),
    );
  }
}

class _CompanyLicenseHeader extends StatelessWidget {
  const _CompanyLicenseHeader({required this.company});

  final AdminCompanySummary company;

  @override
  Widget build(BuildContext context) {
    return AdminSurface(
      title: company.name,
      subtitle: 'Licenca, renovacao e billing em modo read-only.',
      trailing: OutlinedButton.icon(
        onPressed: () => context.go('/companies/${company.id}'),
        icon: const Icon(Icons.business_rounded),
        label: const Text('Abrir empresa'),
      ),
      child: const _ReadOnlyBanner(),
    );
  }
}

class _LicenseDetailCard extends StatelessWidget {
  const _LicenseDetailCard({required this.license});

  final AdminLicenseSnapshot? license;

  @override
  Widget build(BuildContext context) {
    return AdminSurface(
      title: 'Contrato',
      subtitle: 'Dados da licenca administrativa.',
      child: license == null
          ? const _EmptyState(message: 'Empresa sem licenca cadastrada.')
          : Column(
              children: [
                _DetailRow(
                  label: 'Plano atual',
                  value: AdminFormatters.formatPlan(license!.plan),
                ),
                _DetailRow(
                  label: 'Status',
                  value: _statusLabel(license!.status),
                ),
                _DetailRow(
                  label: 'Inicio',
                  value: AdminFormatters.formatDate(license!.startsAt),
                ),
                _DetailRow(
                  label: 'Vencimento',
                  value: AdminFormatters.formatDate(license!.expiresAt),
                ),
                _DetailRow(
                  label: 'Renovacao',
                  value: _renewalLabel(license!.expiresAt),
                ),
                _DetailRow(
                  label: 'Max dispositivos',
                  value: license!.maxDevices?.toString() ?? 'Livre',
                ),
                _DetailRow(
                  label: 'Sync cloud',
                  value: AdminFormatters.formatBool(
                    license!.syncEnabled,
                    yes: 'Habilitada',
                    no: 'Desativada',
                  ),
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
      title: 'Billing status',
      subtitle: 'Provider e historico lidos sem alterar cobranca.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DetailRow(
            label: 'Provider',
            value: billing.provider ?? 'Nao informado',
          ),
          _DetailRow(
            label: 'Status billing',
            value: billing.billingSubscriptionStatus ?? 'Nao informado',
          ),
          _DetailRow(
            label: 'Pending plan',
            value:
                billing.pendingPlan ?? status.license?.pendingPlan ?? 'Nenhum',
          ),
          _DetailRow(
            label: 'Proxima cobranca',
            value: AdminFormatters.formatDate(
              billing.nextPaymentDate ?? status.license?.nextPaymentDate,
            ),
          ),
          _DetailRow(
            label: 'Fim do periodo',
            value: AdminFormatters.formatDate(
              billing.currentPeriodEnd ?? status.license?.currentPeriodEnd,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Historico',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          if (status.events.isEmpty && status.invoices.isEmpty)
            const Text('Nenhum evento de billing retornado pelo endpoint.')
          else ...[
            ...status.events
                .take(5)
                .map(
                  (event) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.receipt_long_rounded),
                    title: Text(event.eventType),
                    subtitle: Text(event.status),
                  ),
                ),
            ...status.invoices
                .take(5)
                .map(
                  (invoice) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.payments_rounded),
                    title: Text(invoice.status),
                    subtitle: Text(
                      '${invoice.currency} ${(invoice.amountCents / 100).toStringAsFixed(2)}',
                    ),
                  ),
                ),
          ],
        ],
      ),
    );
  }
}

class _PlaceholderActions extends StatelessWidget {
  const _PlaceholderActions();

  @override
  Widget build(BuildContext context) {
    return const AdminSurface(
      title: 'Acoes administrativas',
      subtitle:
          'Botoes visiveis como placeholder. Nenhuma acao real sera enviada.',
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _PlaceholderButton(
            label: 'Extensao emergencial',
            icon: Icons.event_available_rounded,
          ),
          _PlaceholderButton(
            label: 'Trocar plano',
            icon: Icons.swap_horiz_rounded,
          ),
          _PlaceholderButton(label: 'Suspender', icon: Icons.lock_rounded),
          _PlaceholderButton(label: 'Reativar', icon: Icons.lock_open_rounded),
        ],
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

class _Filters extends StatefulWidget {
  const _Filters({
    required this.searchController,
    required this.status,
    required this.onApply,
    required this.onClear,
  });

  final TextEditingController searchController;
  final String? status;
  final ValueChanged<String?> onApply;
  final VoidCallback onClear;

  @override
  State<_Filters> createState() => _FiltersState();
}

class _FiltersState extends State<_Filters> {
  late String? _status = widget.status;

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
            onSubmitted: (_) => widget.onApply(_status),
          ),
        ),
        DropdownButton<String?>(
          value: _status,
          items: const [
            DropdownMenuItem(value: null, child: Text('Todas')),
            DropdownMenuItem(value: 'active', child: Text('Ativas')),
            DropdownMenuItem(value: 'trial', child: Text('Trial')),
            DropdownMenuItem(value: 'expired', child: Text('Expiradas')),
            DropdownMenuItem(value: 'suspended', child: Text('Suspensas')),
          ],
          onChanged: (value) => setState(() => _status = value),
        ),
        FilledButton.icon(
          onPressed: () => widget.onApply(_status),
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
        'Modo seguro/read-only: acoes reais de licenca entram apenas em fase posterior com dry-run, confirmacao e auditoria.',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: scheme.onSecondaryContainer,
          fontWeight: FontWeight.w800,
        ),
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

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Text(message),
    );
  }
}

String _statusLabel(String? status) {
  return AdminFormatters.formatLicenseStatus(status);
}

String _renewalLabel(DateTime? expiresAt) {
  if (expiresAt == null) {
    return 'Nao informada';
  }
  final days = expiresAt.difference(DateTime.now()).inDays;
  if (days < 0) {
    return 'Vencida ha ${days.abs()} dias';
  }
  if (days <= 7) {
    return 'Vence em $days dias';
  }
  return 'Ativa por $days dias';
}

String _safeError(Object error) {
  final message = error.toString();
  if (message.contains('Exception:')) {
    return message.split('Exception:').last.trim();
  }
  return message;
}
