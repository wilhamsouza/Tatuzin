import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/admin_providers.dart';
import '../../../core/models/admin_sync_center_models.dart';
import '../../../core/utils/admin_formatters.dart';
import '../../../core/widgets/admin_surface.dart';

class DevicesPage extends ConsumerStatefulWidget {
  const DevicesPage({super.key});

  @override
  ConsumerState<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends ConsumerState<DevicesPage> {
  late final TextEditingController _searchController;
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
    final query = AdminSyncCenterCompaniesQuery(
      page: _page,
      pageSize: 20,
      search: _searchController.text,
      status: 'all',
    );
    final companiesAsync = ref.watch(adminSyncCenterCompaniesProvider(query));
    return companiesAsync.when(
      data: (result) => SingleChildScrollView(
        child: AdminSurface(
          title: 'Dispositivos por empresa',
          subtitle:
              'Inventario read-only agregado por empresa. Abra a empresa para ver MOBILE_APP e ADMIN_WEB detalhados.',
          trailing: OutlinedButton.icon(
            onPressed: () =>
                ref.invalidate(adminSyncCenterCompaniesProvider(query)),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Atualizar'),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 320,
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    labelText: 'Buscar empresa',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                  onSubmitted: (_) => setState(() => _page = 1),
                ),
              ),
              const SizedBox(height: 16),
              if (result.items.isEmpty)
                const _EmptyState(message: 'Nenhuma empresa encontrada.')
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Empresa')),
                      DataColumn(label: Text('Plano')),
                      DataColumn(label: Text('Status sync')),
                      DataColumn(label: Text('OPEN')),
                      DataColumn(label: Text('Falhas')),
                      DataColumn(label: Text('Ultimo evento')),
                      DataColumn(label: Text('Acao')),
                    ],
                    rows: result.items
                        .map((company) {
                          return DataRow(
                            cells: [
                              DataCell(Text(company.companyName)),
                              DataCell(
                                Text(
                                  AdminFormatters.formatPlan(
                                    company.plan ?? 'FREE',
                                  ),
                                ),
                              ),
                              DataCell(Text(company.syncStatus)),
                              DataCell(Text('${company.openConflictCount}')),
                              DataCell(Text('${company.failedCount}')),
                              DataCell(
                                Text(
                                  AdminFormatters.formatDateTime(
                                    company.lastEventAt,
                                  ),
                                ),
                              ),
                              DataCell(
                                FilledButton.tonalIcon(
                                  onPressed: () => context.go(
                                    '/companies/${company.companyId}/sync',
                                  ),
                                  icon: const Icon(Icons.devices_rounded),
                                  label: const Text('Ver dispositivos'),
                                ),
                              ),
                            ],
                          );
                        })
                        .toList(growable: false),
                  ),
                ),
            ],
          ),
        ),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => AdminSurface(
        title: 'Nao foi possivel carregar dispositivos',
        subtitle: _safeError(error),
        child: FilledButton.tonalIcon(
          onPressed: () =>
              ref.invalidate(adminSyncCenterCompaniesProvider(query)),
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Tentar novamente'),
        ),
      ),
    );
  }
}

String _safeError(Object error) {
  final message = error.toString();
  if (message.contains('Exception:')) {
    return message.split('Exception:').last.trim();
  }
  return message;
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
