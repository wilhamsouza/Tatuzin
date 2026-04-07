import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/admin_providers.dart';
import '../../../core/utils/admin_formatters.dart';
import '../../../core/widgets/admin_surface.dart';

class CompaniesPage extends ConsumerWidget {
  const CompaniesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final companies = ref.watch(adminCompaniesProvider);
    return companies.when(
      data: (items) => AdminSurface(
        title: 'Empresas',
        subtitle: 'Tenants cadastrados na plataforma, com visao de licenca e dados remotos.',
        child: SingleChildScrollView(
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
            rows: items.map((company) {
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
                    _StatusBadge(status: company.license?.status ?? 'without_license'),
                  ),
                  DataCell(Text(AdminFormatters.formatDate(company.license?.expiresAt))),
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
                      onPressed: () => context.go('/companies/${company.id}'),
                      child: const Text('Abrir'),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => AdminSurface(
        title: 'Nao foi possivel carregar as empresas',
        subtitle: error.toString(),
        child: const SizedBox.shrink(),
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
