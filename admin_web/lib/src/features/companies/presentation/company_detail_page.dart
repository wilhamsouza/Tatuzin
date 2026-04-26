import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/admin_providers.dart';
import '../../../core/models/admin_models.dart';
import '../../../core/network/admin_api_client.dart';
import '../../../core/utils/admin_formatters.dart';
import '../../../core/widgets/admin_surface.dart';
import '../../../core/widgets/license_editor_dialog.dart';

class CompanyDetailPage extends ConsumerWidget {
  const CompanyDetailPage({super.key, required this.companyId});

  final String companyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(adminCompanyDetailProvider(companyId));
    return detail.when(
      data: (payload) => _CompanyDetailContent(payload: payload),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => AdminSurface(
        title: 'Nao foi possivel carregar o detalhe da empresa',
        subtitle: error.toString(),
        child: const SizedBox.shrink(),
      ),
    );
  }
}

class _CompanyDetailContent extends ConsumerWidget {
  const _CompanyDetailContent({required this.payload});

  final AdminCompanyDetail payload;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final company = payload.company;
    final license = company.license;

    final companySurface = AdminSurface(
      title: company.name,
      subtitle: company.legalName,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DetailRow(label: 'Tenant', value: company.slug),
          _DetailRow(
            label: 'Documento',
            value: company.documentNumber ?? 'Nao informado',
          ),
          _DetailRow(
            label: 'Criada em',
            value: AdminFormatters.formatDateTime(company.createdAt),
          ),
          _DetailRow(
            label: 'Atualizada em',
            value: AdminFormatters.formatDateTime(company.updatedAt),
          ),
        ],
      ),
    );

    final licenseSurface = AdminSurface(
      title: 'Licenca atual',
      subtitle: 'Plano, validade e controle cloud da empresa.',
      trailing: license == null
          ? null
          : FilledButton.tonalIcon(
              onPressed: () => _editLicense(context, ref, license),
              icon: const Icon(Icons.edit_rounded),
              label: const Text('Editar'),
            ),
      child: license == null
          ? Text(
              'Esta empresa ainda nao possui licenca cadastrada.',
              style: Theme.of(context).textTheme.bodyMedium,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DetailRow(
                  label: 'Plano',
                  value: AdminFormatters.formatPlan(license.plan),
                ),
                _DetailRow(
                  label: 'Status',
                  value: AdminFormatters.formatLicenseStatus(license.status),
                ),
                _DetailRow(
                  label: 'Inicio',
                  value: AdminFormatters.formatDate(license.startsAt),
                ),
                _DetailRow(
                  label: 'Expira em',
                  value: AdminFormatters.formatDate(license.expiresAt),
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
                  label: 'Maximo de dispositivos',
                  value: license.maxDevices?.toString() ?? 'Nao definido',
                ),
              ],
            ),
    );

    final membershipsSurface = AdminSurface(
      title: 'Memberships',
      subtitle: 'Usuarios com acesso remoto a esta empresa.',
      child: Column(
        children: payload.memberships.map((membership) {
          return ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(membership.userName),
            subtitle: Text(
              '${membership.userEmail} - ${AdminFormatters.formatMembershipRole(membership.role)}',
            ),
            trailing: Wrap(
              spacing: 8,
              children: [
                if (membership.isDefault) const Chip(label: Text('Padrao')),
                if (membership.userIsPlatformAdmin)
                  const Chip(label: Text('Platform admin')),
              ],
            ),
          );
        }).toList(),
      ),
    );

    final sessionsSurface = AdminSurface(
      title: 'Sessoes e dispositivos',
      subtitle:
          'Inventario minimo das sessoes cloud ativas e historicas da empresa.',
      child: payload.sessions.isEmpty
          ? Text(
              'Nenhuma sessao registrada para esta empresa ate agora.',
              style: Theme.of(context).textTheme.bodyMedium,
            )
          : Column(
              children: payload.sessions.map((session) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.devices_other_rounded),
                  title: Text(session.deviceLabel ?? session.clientInstanceId),
                  subtitle: Text(
                    '${session.userName} - ${_sessionClientLabel(session)} - ${_sessionStatusLabel(session.status)}',
                  ),
                  trailing: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Ultimo acesso ${AdminFormatters.formatDateTime(session.lastSeenAt)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (session.status == 'active')
                        FilledButton.tonalIcon(
                          onPressed: () =>
                              _revokeSession(context, ref, session),
                          icon: const Icon(Icons.block_rounded),
                          label: const Text('Revogar'),
                        ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );

    final healthSurface = AdminSurface(
      title: 'Saude remota',
      subtitle: 'Volume de espelhos remotos registrados para a empresa.',
      child: Column(
        children: [
          _CountRow(label: 'Categorias', value: company.counts.categories),
          _CountRow(label: 'Produtos', value: company.counts.products),
          _CountRow(label: 'Clientes', value: company.counts.customers),
          _CountRow(label: 'Fornecedores', value: company.counts.suppliers),
          _CountRow(label: 'Compras', value: company.counts.purchases),
          _CountRow(label: 'Vendas', value: company.counts.sales),
          _CountRow(
            label: 'Eventos financeiros',
            value: company.counts.financialEvents,
          ),
          _CountRow(
            label: 'Eventos de caixa',
            value: company.counts.cashEvents,
          ),
          const Divider(height: 24),
          _CountRow(
            label: 'Total remoto',
            value: company.counts.totalRemoteRecords,
            emphasize: true,
          ),
        ],
      ),
    );

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 1200) {
                return Column(
                  children: [
                    companySurface,
                    const SizedBox(height: 24),
                    licenseSurface,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: companySurface),
                  const SizedBox(width: 24),
                  Expanded(child: licenseSurface),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 1200) {
                return Column(
                  children: [
                    membershipsSurface,
                    const SizedBox(height: 24),
                    sessionsSurface,
                    const SizedBox(height: 24),
                    healthSurface,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      children: [
                        membershipsSurface,
                        const SizedBox(height: 24),
                        sessionsSurface,
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(flex: 2, child: healthSurface),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  String _sessionClientLabel(AdminDeviceSession session) {
    switch (session.clientType) {
      case 'mobile_app':
        return 'App mobile';
      case 'admin_web':
        return 'Admin web';
      default:
        return session.clientType;
    }
  }

  String _sessionStatusLabel(String status) {
    switch (status) {
      case 'active':
        return 'Ativa';
      case 'revoked':
        return 'Revogada';
      case 'expired':
        return 'Expirada';
      default:
        return status;
    }
  }

  Future<void> _editLicense(
    BuildContext context,
    WidgetRef ref,
    AdminLicenseSnapshot license,
  ) async {
    final edit = await showLicenseEditorDialog(
      context: context,
      license: license,
    );
    if (edit == null || !context.mounted) {
      return;
    }

    try {
      await ref
          .read(adminApiServiceProvider)
          .updateLicense(
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _revokeSession(
    BuildContext context,
    WidgetRef ref,
    AdminDeviceSession session,
  ) async {
    try {
      await ref.read(adminApiServiceProvider).revokeSession(session.id);
      ref.read(adminRefreshTickProvider.notifier).state++;
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sessao revogada com sucesso.')),
      );
    } on AdminApiException catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
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
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _CountRow extends StatelessWidget {
  const _CountRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final int value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            '$value',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: emphasize ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
