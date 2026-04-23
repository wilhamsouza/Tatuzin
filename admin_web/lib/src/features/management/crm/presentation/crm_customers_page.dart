import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/admin_providers.dart';
import '../../../../core/models/admin_crm_models.dart';
import '../../../../core/models/admin_models.dart';
import '../../../../core/utils/admin_formatters.dart';
import '../../../../core/widgets/admin_surface.dart';

class CrmCustomersPage extends ConsumerStatefulWidget {
  const CrmCustomersPage({
    super.key,
    this.initialCompanyId,
    this.initialSearch,
    this.initialTag,
  });

  final String? initialCompanyId;
  final String? initialSearch;
  final String? initialTag;

  @override
  ConsumerState<CrmCustomersPage> createState() => _CrmCustomersPageState();
}

class _CrmCustomersPageState extends ConsumerState<CrmCustomersPage> {
  static const _pageSize = 20;

  late final TextEditingController _searchController;
  late final TextEditingController _tagController;
  String? _selectedCompanyId;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _selectedCompanyId = widget.initialCompanyId;
    _searchController = TextEditingController(text: widget.initialSearch ?? '');
    _tagController = TextEditingController(text: widget.initialTag ?? '');
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final companiesAsync = ref.watch(adminManagementCompanyOptionsProvider);

    return companiesAsync.when(
      data: (companies) {
        if (companies.isEmpty) {
          return const AdminSurface(
            title: 'Sem empresas para CRM',
            subtitle:
                'O CRM cloud-first aparece aqui quando houver empresa consolidada no backend.',
            child: SizedBox.shrink(),
          );
        }

        final effectiveCompanyId = _resolveCompanyId(companies);
        final query = AdminCrmCustomersQuery(
          companyId: effectiveCompanyId,
          page: _page,
          pageSize: _pageSize,
          search: _searchController.text.trim(),
          tag: _tagController.text.trim(),
        );
        final customersAsync = ref.watch(adminCrmCustomersProvider(query));

        return customersAsync.when(
          data: (customers) => SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CrmCustomersScopePanel(
                  companies: companies,
                  selectedCompanyId: effectiveCompanyId,
                  searchController: _searchController,
                  tagController: _tagController,
                  onCompanyChanged: (value) {
                    setState(() {
                      _selectedCompanyId = value;
                      _page = 1;
                    });
                  },
                  onApply: () {
                    setState(() => _page = 1);
                    ref.read(adminRefreshTickProvider.notifier).state++;
                  },
                ),
                const SizedBox(height: 24),
                _CrmCustomersHeader(
                  company: companies.firstWhere(
                    (company) => company.id == effectiveCompanyId,
                  ),
                  result: customers,
                  currentPage: _page,
                ),
                const SizedBox(height: 24),
                AdminSurface(
                  title: 'Clientes com contexto comercial',
                  subtitle:
                      'Leitura cloud-first com customer master remoto, resumo comercial consolidado e observacao operacional simples.',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('Cliente')),
                            DataColumn(label: Text('Contato')),
                            DataColumn(label: Text('Receita')),
                            DataColumn(label: Text('Fiado recebido')),
                            DataColumn(label: Text('Tarefas')),
                            DataColumn(label: Text('Ultimo movimento')),
                            DataColumn(label: Text('Tags')),
                            DataColumn(label: Text('Acoes')),
                          ],
                          rows: customers.items.map((customer) {
                            return DataRow(
                              onSelectChanged: (_) => _openCustomer(
                                context,
                                companyId: effectiveCompanyId,
                                customerId: customer.id,
                              ),
                              cells: [
                                DataCell(
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        customer.name,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        customer.operationalNotes ??
                                            'Sem observacao operacional',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    [
                                          if ((customer.phone ?? '').isNotEmpty)
                                            customer.phone!,
                                          if ((customer.address ?? '')
                                              .isNotEmpty)
                                            customer.address!,
                                        ].join(' | ').isEmpty
                                        ? 'Sem contato'
                                        : [
                                            if ((customer.phone ?? '')
                                                .isNotEmpty)
                                              customer.phone!,
                                            if ((customer.address ?? '')
                                                .isNotEmpty)
                                              customer.address!,
                                          ].join(' | '),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    AdminFormatters.formatCurrencyFromCents(
                                      customer
                                          .commercialSummary
                                          .totalRevenueCents,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    AdminFormatters.formatCurrencyFromCents(
                                      customer
                                          .commercialSummary
                                          .totalFiadoPaymentsCents,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    '${customer.commercialSummary.openTasksCount} aberta(s) | ${customer.commercialSummary.overdueTasksCount} atrasada(s)',
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    _latestMovementLabel(
                                      customer.commercialSummary,
                                    ),
                                  ),
                                ),
                                DataCell(Text(_formatTags(customer.tags))),
                                DataCell(
                                  FilledButton.tonal(
                                    onPressed: () => _openCustomer(
                                      context,
                                      companyId: effectiveCompanyId,
                                      customerId: customer.id,
                                    ),
                                    child: const Text('Abrir'),
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 20),
                      _PaginationBar(
                        pagination: customers.pagination,
                        onPrevious: customers.pagination.hasPrevious
                            ? () => setState(() => _page--)
                            : null,
                        onNext: customers.pagination.hasNext
                            ? () => setState(() => _page++)
                            : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => AdminSurface(
            title: 'Nao foi possivel carregar os clientes do CRM',
            subtitle: error.toString(),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonal(
                onPressed: () =>
                    ref.read(adminRefreshTickProvider.notifier).state++,
                child: const Text('Tentar novamente'),
              ),
            ),
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => AdminSurface(
        title: 'Nao foi possivel carregar as empresas',
        subtitle: error.toString(),
        child: const SizedBox.shrink(),
      ),
    );
  }

  String _resolveCompanyId(List<AdminCompanySummary> companies) {
    final requestedCompanyId = _selectedCompanyId ?? widget.initialCompanyId;
    for (final company in companies) {
      if (company.id == requestedCompanyId) {
        return company.id;
      }
    }
    return companies.first.id;
  }

  void _openCustomer(
    BuildContext context, {
    required String companyId,
    required String customerId,
  }) {
    context.go('/management/crm/customers/$customerId?companyId=$companyId');
  }

  String _formatTags(List<AdminCrmTag> tags) {
    if (tags.isEmpty) {
      return 'Sem tags';
    }
    return tags.map((tag) => tag.label).join(', ');
  }

  String _latestMovementLabel(AdminCrmCommercialSummary summary) {
    final candidates = [
      summary.lastCrmEventAt,
      summary.lastFiadoPaymentAt,
      summary.lastSaleAt,
    ].whereType<DateTime>().toList(growable: false);

    if (candidates.isEmpty) {
      return 'Sem movimento';
    }

    candidates.sort((left, right) => right.compareTo(left));
    return AdminFormatters.formatDateTime(candidates.first);
  }
}

class _CrmCustomersScopePanel extends StatelessWidget {
  const _CrmCustomersScopePanel({
    required this.companies,
    required this.selectedCompanyId,
    required this.searchController,
    required this.tagController,
    required this.onCompanyChanged,
    required this.onApply,
  });

  final List<AdminCompanySummary> companies;
  final String selectedCompanyId;
  final TextEditingController searchController;
  final TextEditingController tagController;
  final ValueChanged<String> onCompanyChanged;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    return AdminSurface(
      title: 'CRM cloud-first por empresa',
      subtitle:
          'Selecione a empresa consolidada, procure clientes e filtre por tag sem misturar com a operacao local do app.',
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          SizedBox(
            width: 280,
            child: DropdownButtonFormField<String>(
              initialValue: selectedCompanyId,
              decoration: const InputDecoration(labelText: 'Empresa'),
              items: companies
                  .map(
                    (company) => DropdownMenuItem<String>(
                      value: company.id,
                      child: Text(company.name),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  onCompanyChanged(value);
                }
              },
            ),
          ),
          SizedBox(
            width: 240,
            child: TextField(
              controller: searchController,
              decoration: const InputDecoration(
                labelText: 'Buscar cliente',
                hintText: 'Nome, telefone, endereco ou observacao operacional',
              ),
              onSubmitted: (_) => onApply(),
            ),
          ),
          SizedBox(
            width: 180,
            child: TextField(
              controller: tagController,
              decoration: const InputDecoration(
                labelText: 'Tag',
                hintText: 'vip',
              ),
              onSubmitted: (_) => onApply(),
            ),
          ),
          FilledButton.icon(
            onPressed: onApply,
            icon: const Icon(Icons.search_rounded),
            label: const Text('Atualizar'),
          ),
        ],
      ),
    );
  }
}

class _CrmCustomersHeader extends StatelessWidget {
  const _CrmCustomersHeader({
    required this.company,
    required this.result,
    required this.currentPage,
  });

  final AdminCompanySummary company;
  final AdminPaginatedResult<AdminCrmCustomerSummary> result;
  final int currentPage;

  @override
  Widget build(BuildContext context) {
    final customersWithAttention = result.items
        .where((customer) => customer.commercialSummary.overdueTasksCount > 0)
        .length;

    return AdminSurface(
      title: company.name,
      subtitle:
          'Customer master remoto com contexto comercial lido no admin web e sem transformar a observacao operacional em CRM pesado.',
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _MutedPill(
            label: '${result.pagination.total} cliente(s) encontrados',
          ),
          _MutedPill(
            label: 'Pagina $currentPage de ${_lastPage(result.pagination)}',
          ),
          _MutedPill(
            label: '$customersWithAttention cliente(s) com tarefa atrasada',
          ),
          _MutedPill(label: 'Empresa ${company.slug}'),
        ],
      ),
    );
  }

  int _lastPage(AdminPaginationMeta pagination) {
    if (pagination.pageSize <= 0) {
      return 1;
    }
    final pages = (pagination.total / pagination.pageSize).ceil();
    return pages <= 0 ? 1 : pages;
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
        Text(
          'Mostrando ${pagination.count} de ${pagination.total} registro(s)',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const Spacer(),
        OutlinedButton.icon(
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left_rounded),
          label: const Text('Anterior'),
        ),
        const SizedBox(width: 12),
        FilledButton.tonalIcon(
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right_rounded),
          label: const Text('Proxima'),
        ),
      ],
    );
  }
}

class _MutedPill extends StatelessWidget {
  const _MutedPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}
