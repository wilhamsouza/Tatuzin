import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/admin_providers.dart';
import '../../../core/models/admin_models.dart';
import '../../../core/utils/admin_formatters.dart';
import '../../../core/widgets/admin_surface.dart';

class CompaniesPage extends ConsumerStatefulWidget {
  const CompaniesPage({super.key});

  @override
  ConsumerState<CompaniesPage> createState() => _CompaniesPageState();
}

class _CompaniesPageState extends ConsumerState<CompaniesPage> {
  late final TextEditingController _searchController;
  bool? _isActive;
  String? _licenseStatus;
  bool? _syncEnabled;
  String _sortBy = 'createdAt';
  String _sortDirection = 'desc';
  int _page = 1;
  int _pageSize = 20;

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
    final query = AdminCompaniesQuery(
      page: _page,
      pageSize: _pageSize,
      search: _searchController.text,
      isActive: _isActive,
      licenseStatus: _licenseStatus,
      syncEnabled: _syncEnabled,
      sortBy: _sortBy,
      sortDirection: _sortDirection,
    );
    final companiesAsync = ref.watch(adminCompaniesProvider(query));

    return companiesAsync.when(
      data: (result) => AdminSurface(
        title: 'Empresas',
        subtitle:
            'Tenants cadastrados na plataforma, com visao de licenca e dados remotos.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CompaniesFilters(
              searchController: _searchController,
              isActive: _isActive,
              licenseStatus: _licenseStatus,
              syncEnabled: _syncEnabled,
              sortBy: _sortBy,
              sortDirection: _sortDirection,
              pageSize: _pageSize,
              onApply: _applyFilters,
              onClear: _clearFilters,
            ),
            const SizedBox(height: 20),
            if (result.items.isEmpty)
              const _EmptyState(
                message: 'Nenhuma empresa encontrada para os filtros.',
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Empresa')),
                    DataColumn(label: Text('Tenant')),
                    DataColumn(label: Text('Plano')),
                    DataColumn(label: Text('Status')),
                    DataColumn(label: Text('Validade')),
                    DataColumn(label: Text('Sync')),
                    DataColumn(label: Text('Usuarios')),
                    DataColumn(label: Text('Acao')),
                  ],
                  rows: result.items.map((company) {
                    return DataRow(
                      cells: [
                        DataCell(
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(company.name),
                              if ((company.documentNumber ?? '').isNotEmpty)
                                Text(
                                  company.documentNumber!,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                            ],
                          ),
                        ),
                        DataCell(Text(company.slug)),
                        DataCell(Text(company.license?.plan ?? 'Sem licenca')),
                        DataCell(
                          _StatusBadge(
                            status:
                                company.license?.status ?? 'without_license',
                          ),
                        ),
                        DataCell(
                          Text(
                            AdminFormatters.formatDate(
                              company.license?.expiresAt,
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            AdminFormatters.formatBool(
                              company.license?.syncEnabled == true,
                              yes: 'Habilitada',
                              no: 'Desativada',
                            ),
                          ),
                        ),
                        DataCell(Text('${company.counts.memberships}')),
                        DataCell(
                          FilledButton.tonal(
                            onPressed: () =>
                                context.go('/companies/${company.id}'),
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
        title: 'Nao foi possivel carregar as empresas',
        subtitle: error.toString(),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonal(
            onPressed: () => ref.invalidate(adminCompaniesProvider(query)),
            child: const Text('Tentar novamente'),
          ),
        ),
      ),
    );
  }

  void _applyFilters({
    required bool? isActive,
    required String? licenseStatus,
    required bool? syncEnabled,
    required String sortBy,
    required String sortDirection,
    required int pageSize,
  }) {
    setState(() {
      _isActive = isActive;
      _licenseStatus = licenseStatus;
      _syncEnabled = syncEnabled;
      _sortBy = sortBy;
      _sortDirection = sortDirection;
      _pageSize = pageSize;
      _page = 1;
    });
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _isActive = null;
      _licenseStatus = null;
      _syncEnabled = null;
      _sortBy = 'createdAt';
      _sortDirection = 'desc';
      _pageSize = 20;
      _page = 1;
    });
  }
}

class _CompaniesFilters extends StatefulWidget {
  const _CompaniesFilters({
    required this.searchController,
    required this.isActive,
    required this.licenseStatus,
    required this.syncEnabled,
    required this.sortBy,
    required this.sortDirection,
    required this.pageSize,
    required this.onApply,
    required this.onClear,
  });

  final TextEditingController searchController;
  final bool? isActive;
  final String? licenseStatus;
  final bool? syncEnabled;
  final String sortBy;
  final String sortDirection;
  final int pageSize;
  final void Function({
    required bool? isActive,
    required String? licenseStatus,
    required bool? syncEnabled,
    required String sortBy,
    required String sortDirection,
    required int pageSize,
  })
  onApply;
  final VoidCallback onClear;

  @override
  State<_CompaniesFilters> createState() => _CompaniesFiltersState();
}

class _CompaniesFiltersState extends State<_CompaniesFilters> {
  late bool? _isActive;
  late String? _licenseStatus;
  late bool? _syncEnabled;
  late String _sortBy;
  late String _sortDirection;
  late int _pageSize;

  @override
  void initState() {
    super.initState();
    _syncFromWidget();
  }

  @override
  void didUpdateWidget(covariant _CompaniesFilters oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive ||
        oldWidget.licenseStatus != widget.licenseStatus ||
        oldWidget.syncEnabled != widget.syncEnabled ||
        oldWidget.sortBy != widget.sortBy ||
        oldWidget.sortDirection != widget.sortDirection ||
        oldWidget.pageSize != widget.pageSize) {
      _syncFromWidget();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
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
                  hintText: 'Nome, tenant, razao social ou documento',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
                onSubmitted: (_) => _apply(),
              ),
            ),
            SizedBox(
              width: 160,
              child: DropdownButtonFormField<bool?>(
                initialValue: _isActive,
                decoration: const InputDecoration(labelText: 'Ativa'),
                items: const [
                  DropdownMenuItem<bool?>(value: null, child: Text('Todas')),
                  DropdownMenuItem<bool?>(value: true, child: Text('Ativas')),
                  DropdownMenuItem<bool?>(
                    value: false,
                    child: Text('Inativas'),
                  ),
                ],
                onChanged: (value) => setState(() => _isActive = value),
              ),
            ),
            SizedBox(
              width: 180,
              child: DropdownButtonFormField<String?>(
                initialValue: _licenseStatus,
                decoration: const InputDecoration(labelText: 'Licenca'),
                items: const [
                  DropdownMenuItem<String?>(value: null, child: Text('Todas')),
                  DropdownMenuItem<String?>(
                    value: 'trial',
                    child: Text('Trial'),
                  ),
                  DropdownMenuItem<String?>(
                    value: 'active',
                    child: Text('Ativa'),
                  ),
                  DropdownMenuItem<String?>(
                    value: 'suspended',
                    child: Text('Suspensa'),
                  ),
                  DropdownMenuItem<String?>(
                    value: 'expired',
                    child: Text('Expirada'),
                  ),
                  DropdownMenuItem<String?>(
                    value: 'without_license',
                    child: Text('Sem licenca'),
                  ),
                ],
                onChanged: (value) => setState(() => _licenseStatus = value),
              ),
            ),
            SizedBox(
              width: 170,
              child: DropdownButtonFormField<bool?>(
                initialValue: _syncEnabled,
                decoration: const InputDecoration(labelText: 'Sync'),
                items: const [
                  DropdownMenuItem<bool?>(value: null, child: Text('Todas')),
                  DropdownMenuItem<bool?>(
                    value: true,
                    child: Text('Habilitada'),
                  ),
                  DropdownMenuItem<bool?>(
                    value: false,
                    child: Text('Desativada'),
                  ),
                ],
                onChanged: (value) => setState(() => _syncEnabled = value),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 180,
              child: DropdownButtonFormField<String>(
                initialValue: _sortBy,
                decoration: const InputDecoration(labelText: 'Ordenar por'),
                items: const [
                  DropdownMenuItem(value: 'createdAt', child: Text('Criacao')),
                  DropdownMenuItem(
                    value: 'updatedAt',
                    child: Text('Atualizacao'),
                  ),
                  DropdownMenuItem(value: 'name', child: Text('Nome')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _sortBy = value);
                  }
                },
              ),
            ),
            SizedBox(
              width: 160,
              child: DropdownButtonFormField<String>(
                initialValue: _sortDirection,
                decoration: const InputDecoration(labelText: 'Direcao'),
                items: const [
                  DropdownMenuItem(value: 'asc', child: Text('Crescente')),
                  DropdownMenuItem(value: 'desc', child: Text('Decrescente')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _sortDirection = value);
                  }
                },
              ),
            ),
            SizedBox(
              width: 140,
              child: DropdownButtonFormField<int>(
                initialValue: _pageSize,
                decoration: const InputDecoration(labelText: 'Por pagina'),
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
        ),
      ],
    );
  }

  void _apply() {
    widget.onApply(
      isActive: _isActive,
      licenseStatus: _licenseStatus,
      syncEnabled: _syncEnabled,
      sortBy: _sortBy,
      sortDirection: _sortDirection,
      pageSize: _pageSize,
    );
  }

  void _syncFromWidget() {
    _isActive = widget.isActive;
    _licenseStatus = widget.licenseStatus;
    _syncEnabled = widget.syncEnabled;
    _sortBy = widget.sortBy;
    _sortDirection = widget.sortDirection;
    _pageSize = widget.pageSize;
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
          'Pagina ${pagination.page} • ${pagination.count} de ${pagination.total} $itemLabel',
        ),
        OutlinedButton.icon(
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left_rounded),
          label: const Text('Anterior'),
        ),
        OutlinedButton.icon(
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right_rounded),
          label: const Text('Proxima'),
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
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AdminFormatters.statusBackgroundColor(context, status),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        AdminFormatters.formatLicenseStatus(status),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: AdminFormatters.statusColor(context, status),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
