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
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final licenses = ref.watch(adminLicensesProvider);
    return licenses.when(
      data: (items) {
        final filtered = _filter == 'all'
            ? items
            : items.where((license) => license.status == _filter).toList();

        return AdminSurface(
          title: 'Licencas',
          subtitle: 'Controle comercial e cloud das empresas da plataforma.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _FilterChip(
                    label: 'Todas',
                    selected: _filter == 'all',
                    onTap: () => setState(() => _filter = 'all'),
                  ),
                  _FilterChip(
                    label: 'Ativas',
                    selected: _filter == 'active',
                    onTap: () => setState(() => _filter = 'active'),
                  ),
                  _FilterChip(
                    label: 'Trial',
                    selected: _filter == 'trial',
                    onTap: () => setState(() => _filter = 'trial'),
                  ),
                  _FilterChip(
                    label: 'Expiradas',
                    selected: _filter == 'expired',
                    onTap: () => setState(() => _filter = 'expired'),
                  ),
                  _FilterChip(
                    label: 'Suspensas',
                    selected: _filter == 'suspended',
                    onTap: () => setState(() => _filter = 'suspended'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
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
                  rows: filtered.map((license) {
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
            ],
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => AdminSurface(
        title: 'Nao foi possivel carregar as licencas',
        subtitle: error.toString(),
        child: const SizedBox.shrink(),
      ),
    );
  }

  Future<void> _editLicense(BuildContext context, AdminLicenseSnapshot license) async {
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
