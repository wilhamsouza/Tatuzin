import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/admin_providers.dart';
import '../../../core/models/admin_models.dart';
import '../../../core/network/admin_api_client.dart';
import '../../../core/utils/admin_formatters.dart';
import '../../../core/widgets/admin_surface.dart';
import '../../../core/widgets/license_editor_dialog.dart';

class LicensesPage extends ConsumerStatefulWidget {
  const LicensesPage({super.key});

  @override
  ConsumerState<LicensesPage> createState() => _LicensesPageState();
}

class _LicensesPageState extends ConsumerState<LicensesPage> {
  late final TextEditingController _searchController;
  String? _status;
  bool? _syncEnabled;
  String _sortBy = 'updatedAt';
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
    final query = AdminLicensesQuery(
      page: _page,
      pageSize: _pageSize,
      search: _searchController.text,
      status: _status,
      syncEnabled: _syncEnabled,
      sortBy: _sortBy,
      sortDirection: _sortDirection,
    );
    final licensesAsync = ref.watch(adminLicensesProvider(query));

    return licensesAsync.when(
      data: (result) {
        return AdminSurface(
          title: 'Licencas',
          subtitle: 'Controle comercial e cloud das empresas da plataforma.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _LicensesFilters(
                searchController: _searchController,
                status: _status,
                syncEnabled: _syncEnabled,
                sortBy: _sortBy,
                sortDirection: _sortDirection,
                pageSize: _pageSize,
                onApply: _applyFilters,
                onClear: _clearFilters,
              ),
              const SizedBox(height: 20),
              if (result.items.isEmpty)
                const _EmptyState(message: 'Nenhuma licenca encontrada para os filtros.')
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Empresa')),
                      DataColumn(label: Text('Plano')),
                      DataColumn(label: Text('Status')),
                      DataColumn(label: Text('Inicio')),
                      DataColumn(label: Text('Expira em')),
                      DataColumn(label: Text('Sync')),
                      DataColumn(label: Text('Max devices')),
                      DataColumn(label: Text('Acao')),
                    ],
                    rows: result.items.map((license) {
                      return DataRow(
                        cells: [
                          DataCell(
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(license.companyName),
                                Text(
                                  license.companySlug,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          DataCell(Text(AdminFormatters.formatPlan(license.plan))),
                          DataCell(_StatusBadge(status: license.status)),
                          DataCell(Text(AdminFormatters.formatDate(license.startsAt))),
                          DataCell(Text(AdminFormatters.formatDate(license.expiresAt))),
                          DataCell(
                            Text(
                              AdminFormatters.formatBool(
                                license.syncEnabled,
                                yes: 'Habilitada',
                                no: 'Desativada',
                              ),
                            ),
                          ),
                          DataCell(Text(license.maxDevices?.toString() ?? 'Livre')),
                          DataCell(
                            FilledButton.tonal(
                              onPressed: () => _editLicense(context, license),
                              child: const Text('Editar'),
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
                itemLabel: 'licencas',
                onPrevious: result.pagination.hasPrevious
                    ? () => setState(() => _page--)
                    : null,
                onNext: result.pagination.hasNext
                    ? () => setState(() => _page++)
                    : null,
              ),
            ],
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => AdminSurface(
        title: 'Nao foi possivel carregar as licencas',
        subtitle: error.toString(),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonal(
            onPressed: () => ref.invalidate(adminLicensesProvider(query)),
            child: const Text('Tentar novamente'),
          ),
        ),
      ),
    );
  }

  Future<void> _editLicense(
    BuildContext context,
    AdminLicenseSnapshot license,
  ) async {
    final edit = await showLicenseEditorDialog(context: context, license: license);
    if (edit == null || !context.mounted) {
      return;
    }

    try {
      await ref.read(adminApiServiceProvider).updateLicense(
            companyId: license.companyId,
            plan: edit.plan,
            status: edit.status,
            startsAt: edit.startsAt,
            expiresAt: edit.expiresAt,
            syncEnabled: edit.syncEnabled,
            maxDevices: edit.maxDevices,
          );
      ref.read(adminRefreshTickProvider.notifier).state++;
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Licenca atualizada com sucesso.')),
      );
    } on AdminApiException catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    }
  }

  void _applyFilters({
    required String? status,
    required bool? syncEnabled,
    required String sortBy,
    required String sortDirection,
    required int pageSize,
  }) {
    setState(() {
      _status = status;
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
      _status = null;
      _syncEnabled = null;
      _sortBy = 'updatedAt';
      _sortDirection = 'desc';
      _pageSize = 20;
      _page = 1;
    });
  }
}

class _LicensesFilters extends StatefulWidget {
  const _LicensesFilters({
    required this.searchController,
    required this.status,
    required this.syncEnabled,
    required this.sortBy,
    required this.sortDirection,
    required this.pageSize,
    required this.onApply,
    required this.onClear,
  });

  final TextEditingController searchController;
  final String? status;
  final bool? syncEnabled;
  final String sortBy;
  final String sortDirection;
  final int pageSize;
  final void Function({
    required String? status,
    required bool? syncEnabled,
    required String sortBy,
    required String sortDirection,
    required int pageSize,
  })
  onApply;
  final VoidCallback onClear;

  @override
  State<_LicensesFilters> createState() => _LicensesFiltersState();
}

class _LicensesFiltersState extends State<_LicensesFilters> {
  late String? _status;
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
  void didUpdateWidget(covariant _LicensesFilters oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status ||
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
                  hintText: 'Nome ou tenant',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
                onSubmitted: (_) => _apply(),
              ),
            ),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _FilterChip(
                  label: 'Todas',
                  selected: _status == null,
                  onTap: () => setState(() => _status = null),
                ),
                _FilterChip(
                  label: 'Ativas',
                  selected: _status == 'active',
                  onTap: () => setState(() => _status = 'active'),
                ),
                _FilterChip(
                  label: 'Trial',
                  selected: _status == 'trial',
                  onTap: () => setState(() => _status = 'trial'),
                ),
                _FilterChip(
                  label: 'Expiradas',
                  selected: _status == 'expired',
                  onTap: () => setState(() => _status = 'expired'),
                ),
                _FilterChip(
                  label: 'Suspensas',
                  selected: _status == 'suspended',
                  onTap: () => setState(() => _status = 'suspended'),
                ),
              ],
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
              width: 170,
              child: DropdownButtonFormField<bool?>(
                initialValue: _syncEnabled,
                decoration: const InputDecoration(labelText: 'Sync'),
                items: const [
                  DropdownMenuItem<bool?>(value: null, child: Text('Todas')),
                  DropdownMenuItem<bool?>(value: true, child: Text('Habilitada')),
                  DropdownMenuItem<bool?>(
                    value: false,
                    child: Text('Desativada'),
                  ),
                ],
                onChanged: (value) => setState(() => _syncEnabled = value),
              ),
            ),
            SizedBox(
              width: 180,
              child: DropdownButtonFormField<String>(
                initialValue: _sortBy,
                decoration: const InputDecoration(labelText: 'Ordenar por'),
                items: const [
                  DropdownMenuItem(
                    value: 'updatedAt',
                    child: Text('Atualizacao'),
                  ),
                  DropdownMenuItem(
                    value: 'expiresAt',
                    child: Text('Expiracao'),
                  ),
                  DropdownMenuItem(
                    value: 'companyName',
                    child: Text('Empresa'),
                  ),
                  DropdownMenuItem(value: 'status', child: Text('Status')),
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
            TextButton(
              onPressed: widget.onClear,
              child: const Text('Limpar'),
            ),
          ],
        ),
      ],
    );
  }

  void _apply() {
    widget.onApply(
      status: _status,
      syncEnabled: _syncEnabled,
      sortBy: _sortBy,
      sortDirection: _sortDirection,
      pageSize: _pageSize,
    );
  }

  void _syncFromWidget() {
    _status = widget.status;
    _syncEnabled = widget.syncEnabled;
    _sortBy = widget.sortBy;
    _sortDirection = widget.sortDirection;
    _pageSize = widget.pageSize;
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
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
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
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
