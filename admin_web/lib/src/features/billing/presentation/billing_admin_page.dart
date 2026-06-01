import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/admin_providers.dart';
import '../../../core/models/admin_billing_models.dart';
import '../../../core/models/admin_models.dart';
import '../../../core/utils/admin_formatters.dart';
import '../../../core/widgets/admin_surface.dart';

class BillingAdminPage extends ConsumerStatefulWidget {
  const BillingAdminPage({super.key});

  @override
  ConsumerState<BillingAdminPage> createState() => _BillingAdminPageState();
}

class _BillingAdminPageState extends ConsumerState<BillingAdminPage> {
  late final TextEditingController _searchController;
  late final TextEditingController _statusController;
  late final TextEditingController _providerController;
  String? _plan;
  bool? _hasProviderSubscription;
  int _page = 1;
  int _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _statusController = TextEditingController();
    _providerController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _statusController.dispose();
    _providerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = AdminBillingCompaniesQuery(
      page: _page,
      pageSize: _pageSize,
      search: _searchController.text,
      plan: _plan,
      status: _statusController.text,
      provider: _providerController.text,
      hasProviderSubscription: _hasProviderSubscription,
    );
    final companiesAsync = ref.watch(adminBillingCompaniesProvider(query));

    return companiesAsync.when(
      data: (result) => AdminSurface(
        title: 'Billing',
        subtitle:
            'Console interno restrito para suporte administrativo de billing.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _PlatformOnlyNotice(),
            const SizedBox(height: 20),
            _BillingFilters(
              searchController: _searchController,
              statusController: _statusController,
              providerController: _providerController,
              plan: _plan,
              hasProviderSubscription: _hasProviderSubscription,
              pageSize: _pageSize,
              onApply:
                  ({
                    required plan,
                    required hasProviderSubscription,
                    required pageSize,
                  }) {
                    setState(() {
                      _plan = plan;
                      _hasProviderSubscription = hasProviderSubscription;
                      _pageSize = pageSize;
                      _page = 1;
                    });
                  },
              onClear: () {
                _searchController.clear();
                _statusController.clear();
                _providerController.clear();
                setState(() {
                  _plan = null;
                  _hasProviderSubscription = null;
                  _pageSize = 20;
                  _page = 1;
                });
              },
            ),
            const SizedBox(height: 20),
            if (result.items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Text('Nenhuma empresa encontrada para os filtros.'),
              )
            else
              _BillingCompaniesTable(
                companies: result.items,
                onOpen: (companyId) => context.go('/billing/$companyId'),
              ),
            const SizedBox(height: 20),
            _PaginationBar(
              pagination: result.pagination,
              itemLabel: 'empresas',
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
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => AdminSurface(
        title: 'Nao foi possivel carregar o Billing',
        subtitle: error.toString(),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonal(
            onPressed: () =>
                ref.invalidate(adminBillingCompaniesProvider(query)),
            child: const Text('Tentar novamente'),
          ),
        ),
      ),
    );
  }
}

class _PlatformOnlyNotice extends StatelessWidget {
  const _PlatformOnlyNotice();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Text(
              'Billing restrito. Esta area preserva acoes administrativas reais. Para consulta segura/read-only, use Licencas.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onErrorContainer,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          FilledButton.tonalIcon(
            onPressed: () => context.go('/licenses'),
            icon: const Icon(Icons.workspace_premium_rounded),
            label: const Text('Ir para Licencas read-only'),
          ),
        ],
      ),
    );
  }
}

class _BillingCompaniesTable extends StatelessWidget {
  const _BillingCompaniesTable({required this.companies, required this.onOpen});

  final List<AdminBillingCompanySummary> companies;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Empresa')),
          DataColumn(label: Text('Plano')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Provider')),
          DataColumn(label: Text('Assinatura provider')),
          DataColumn(label: Text('Provider ID mascarado')),
          DataColumn(label: Text('Próxima cobrança')),
          DataColumn(label: Text('Cancelamento')),
          DataColumn(label: Text('Pendente')),
          DataColumn(label: Text('Ação')),
        ],
        rows: companies
            .map((company) {
              void openCompany() => onOpen(company.companyId);
              return DataRow(
                cells: [
                  DataCell(
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.open_in_new_rounded, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              company.companyName,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          company.companyId,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    onTap: openCompany,
                  ),
                  DataCell(
                    Text(AdminFormatters.formatPlan(company.plan)),
                    onTap: openCompany,
                  ),
                  DataCell(Text(company.licenseStatus ?? 'Não informado')),
                  DataCell(
                    Text(company.billingProvider ?? 'Sem provider'),
                    onTap: openCompany,
                  ),
                  DataCell(
                    Text(company.hasProviderSubscription ? 'Sim' : 'Não'),
                  ),
                  DataCell(
                    Text(
                      company.maskedProviderSubscriptionId ??
                          (company.hasProviderSubscription
                              ? '[mascarado]'
                              : 'Sem assinatura'),
                    ),
                  ),
                  DataCell(
                    Text(AdminFormatters.formatDate(company.nextPaymentDate)),
                  ),
                  DataCell(
                    Text(company.cancelAtPeriodEnd ? 'Agendado' : 'Não'),
                  ),
                  DataCell(
                    Text(company.pendingPlan ?? 'Nenhum'),
                    onTap: openCompany,
                  ),
                  DataCell(
                    FilledButton.tonalIcon(
                      onPressed: openCompany,
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label: const Text('Abrir'),
                    ),
                  ),
                ],
              );
            })
            .toList(growable: false),
      ),
    );
  }
}

class _BillingFilters extends StatefulWidget {
  const _BillingFilters({
    required this.searchController,
    required this.statusController,
    required this.providerController,
    required this.plan,
    required this.hasProviderSubscription,
    required this.pageSize,
    required this.onApply,
    required this.onClear,
  });

  final TextEditingController searchController;
  final TextEditingController statusController;
  final TextEditingController providerController;
  final String? plan;
  final bool? hasProviderSubscription;
  final int pageSize;
  final void Function({
    required String? plan,
    required bool? hasProviderSubscription,
    required int pageSize,
  })
  onApply;
  final VoidCallback onClear;

  @override
  State<_BillingFilters> createState() => _BillingFiltersState();
}

class _BillingFiltersState extends State<_BillingFilters> {
  late String? _plan = widget.plan;
  late bool? _hasProviderSubscription = widget.hasProviderSubscription;
  late int _pageSize = widget.pageSize;

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
            onSubmitted: (_) => _apply(),
          ),
        ),
        SizedBox(
          width: 140,
          child: DropdownButtonFormField<String?>(
            initialValue: _plan,
            decoration: const InputDecoration(labelText: 'Plano'),
            items: const [
              DropdownMenuItem<String?>(value: null, child: Text('Todos')),
              DropdownMenuItem<String?>(value: 'FREE', child: Text('FREE')),
              DropdownMenuItem<String?>(value: 'BASIC', child: Text('BASIC')),
              DropdownMenuItem<String?>(value: 'PRO', child: Text('PRO')),
            ],
            onChanged: (value) => setState(() => _plan = value),
          ),
        ),
        SizedBox(
          width: 160,
          child: TextField(
            decoration: const InputDecoration(labelText: 'Status'),
            controller: widget.statusController,
          ),
        ),
        SizedBox(
          width: 180,
          child: TextField(
            decoration: const InputDecoration(labelText: 'Provider'),
            controller: widget.providerController,
          ),
        ),
        SizedBox(
          width: 230,
          child: DropdownButtonFormField<bool?>(
            initialValue: _hasProviderSubscription,
            decoration: const InputDecoration(labelText: 'Assinatura provider'),
            items: const [
              DropdownMenuItem<bool?>(value: null, child: Text('Todas')),
              DropdownMenuItem<bool?>(value: true, child: Text('Com vínculo')),
              DropdownMenuItem<bool?>(value: false, child: Text('Sem vínculo')),
            ],
            onChanged: (value) =>
                setState(() => _hasProviderSubscription = value),
          ),
        ),
        SizedBox(
          width: 140,
          child: DropdownButtonFormField<int>(
            initialValue: _pageSize,
            decoration: const InputDecoration(labelText: 'Por página'),
            items: const [
              DropdownMenuItem(value: 10, child: Text('10')),
              DropdownMenuItem(value: 20, child: Text('20')),
              DropdownMenuItem(value: 50, child: Text('50')),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() => _pageSize = value);
              }
            },
          ),
        ),
        FilledButton.icon(
          onPressed: _apply,
          icon: const Icon(Icons.filter_alt_rounded),
          label: const Text('Aplicar'),
        ),
        TextButton(onPressed: widget.onClear, child: const Text('Limpar')),
      ],
    );
  }

  void _apply() {
    widget.onApply(
      plan: _plan,
      hasProviderSubscription: _hasProviderSubscription,
      pageSize: _pageSize,
    );
  }
}

class _PaginationBar extends StatelessWidget {
  const _PaginationBar({
    required this.pagination,
    required this.itemLabel,
    required this.onPrevious,
    required this.onNext,
  });

  final AdminPaginationMeta pagination;
  final String itemLabel;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          'Página ${pagination.page} • ${pagination.count} de ${pagination.total} $itemLabel',
        ),
        OutlinedButton.icon(
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left_rounded),
          label: const Text('Anterior'),
        ),
        OutlinedButton.icon(
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right_rounded),
          label: const Text('Próxima'),
        ),
      ],
    );
  }
}
