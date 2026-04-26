import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/session/auth_provider.dart';
import '../../../../app/core/widgets/app_input.dart';
import '../../../../app/core/widgets/app_main_drawer.dart';
import '../../../../app/core/widgets/app_page_header.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import '../../../../app/core/widgets/app_status_badge.dart';
import '../providers/admin_providers.dart';

class AdminPage extends ConsumerWidget {
  const AdminPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authStatus = ref.watch(authStatusProvider);
    final overviewAsync = ref.watch(adminOverviewProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Admin interno')),
      drawer: const AppMainDrawer(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          const AppPageHeader(
            title: 'Admin interno de apoio',
            subtitle:
                'Superficie interna e provisoria para suporte no app. O painel administrativo principal do Tatuzin fica no admin web.',
            badgeLabel: 'Uso interno',
            badgeIcon: Icons.admin_panel_settings_rounded,
            emphasized: true,
          ),
          const SizedBox(height: 18),
          const AppSectionCard(
            title: 'Superficie principal',
            subtitle:
                'Esta tela nao substitui o painel administrativo oficial da plataforma.',
            child: Text(
              'Use o admin web como interface principal para operacao administrativa. Esta area interna permanece apenas como apoio temporario para suporte e homologacao dentro do app.',
            ),
          ),
          const SizedBox(height: 18),
          if (!authStatus.isRemoteAuthenticated || !authStatus.isPlatformAdmin)
            AppSectionCard(
              title: 'Acesso restrito',
              subtitle:
                  'Esta area interna exige sessao remota com perfil administrativo de suporte.',
              child: Text(
                !authStatus.isRemoteAuthenticated
                    ? 'Faca login remoto para usar este apoio interno.'
                    : 'Seu usuario atual nao possui acesso ao admin interno.',
              ),
            )
          else
            overviewAsync.when(
              data: (overview) => Column(
                children: [
                  _AdminOverviewSection(overview: overview),
                  const SizedBox(height: 18),
                  _SyncOverviewSection(overview: overview),
                  const SizedBox(height: 18),
                  _AuditOverviewSection(overview: overview),
                  const SizedBox(height: 18),
                  AppSectionCard(
                    title: 'Empresas e licencas',
                    subtitle:
                        'Consulta interna e resumida de tenants, licencas e capacidade cloud por empresa.',
                    child: Column(
                      children: overview.companies
                          .map(
                            (company) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _CompanyTile(
                                company: company,
                                onTap: () =>
                                    _openCompanyDetail(context, ref, company),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
              ),
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => AppSectionCard(
                title: 'Falha ao carregar o painel',
                subtitle:
                    'Nao foi possivel consultar os dados administrativos.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(error.toString()),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => ref.invalidate(adminOverviewProvider),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openCompanyDetail(
    BuildContext context,
    WidgetRef ref,
    AdminCompanySummary company,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return Consumer(
          builder: (context, ref, _) {
            final detailAsync = ref.watch(
              adminCompanyDetailProvider(company.id),
            );
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.82,
              minChildSize: 0.45,
              maxChildSize: 0.95,
              builder: (context, scrollController) {
                return detailAsync.when(
                  data: (detail) => ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    children: [
                      Text(
                        detail.company.name,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        detail.company.legalName,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          AppStatusBadge(
                            label: detail.company.isActive
                                ? 'Empresa ativa'
                                : 'Empresa inativa',
                            tone: detail.company.isActive
                                ? AppStatusTone.success
                                : AppStatusTone.warning,
                            icon: detail.company.isActive
                                ? Icons.approval_rounded
                                : Icons.pause_circle_outline_rounded,
                          ),
                          if (detail.company.license != null)
                            AppStatusBadge(
                              label:
                                  'Licenca ${detail.company.license!.statusLabel}',
                              tone: _licenseTone(
                                detail.company.license!.status,
                              ),
                              icon: Icons.workspace_premium_rounded,
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      AppSectionCard(
                        title: 'Licenca atual',
                        subtitle:
                            'Controle de plano, validade e habilitacao cloud desta empresa.',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _DetailRow(
                              label: 'Plano',
                              value:
                                  detail.company.license?.plan ??
                                  'Nao definida',
                            ),
                            _DetailRow(
                              label: 'Status',
                              value:
                                  detail.company.license?.statusLabel ??
                                  'Sem licenca',
                            ),
                            _DetailRow(
                              label: 'Validade',
                              value: detail.company.license?.expiresAt == null
                                  ? 'Sem vencimento'
                                  : AppFormatters.shortDate(
                                      detail.company.license!.expiresAt!,
                                    ),
                            ),
                            _DetailRow(
                              label: 'Sync cloud',
                              value: detail.company.license?.syncEnabled == true
                                  ? 'Habilitada'
                                  : 'Desabilitada',
                            ),
                            if (detail.company.license?.maxDevices != null)
                              _DetailRow(
                                label: 'Limite de dispositivos',
                                value: detail.company.license!.maxDevices!
                                    .toString(),
                              ),
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: FilledButton.icon(
                                onPressed: () => _openLicenseEditor(
                                  context,
                                  ref,
                                  detail.company,
                                ),
                                icon: const Icon(Icons.edit_rounded),
                                label: const Text('Editar licenca'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      AppSectionCard(
                        title: 'Uso cloud por tenant',
                        subtitle:
                            'Resumo de entidades espelhadas no backend para este tenant.',
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _CountChip(
                              label:
                                  '${detail.company.counts.products} produtos',
                              icon: Icons.inventory_2_rounded,
                            ),
                            _CountChip(
                              label:
                                  '${detail.company.counts.customers} clientes',
                              icon: Icons.people_alt_rounded,
                            ),
                            _CountChip(
                              label:
                                  '${detail.company.counts.suppliers} fornecedores',
                              icon: Icons.local_shipping_outlined,
                            ),
                            _CountChip(
                              label:
                                  '${detail.company.counts.purchases} compras',
                              icon: Icons.shopping_bag_outlined,
                            ),
                            _CountChip(
                              label: '${detail.company.counts.sales} vendas',
                              icon: Icons.point_of_sale_rounded,
                            ),
                            _CountChip(
                              label:
                                  '${detail.company.counts.financialEvents} eventos financeiros',
                              icon: Icons.account_balance_wallet_outlined,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      AppSectionCard(
                        title: 'Memberships',
                        subtitle:
                            'Usuarios vinculados ao tenant e seus perfis operacionais.',
                        child: Column(
                          children: detail.memberships
                              .map(
                                (membership) => Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _MembershipTile(
                                    membership: membership,
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ],
                  ),
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(20),
                    children: [
                      Text(error.toString()),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () => ref.invalidate(
                          adminCompanyDetailProvider(company.id),
                        ),
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Tentar novamente'),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _openLicenseEditor(
    BuildContext context,
    WidgetRef ref,
    AdminCompanySummary company,
  ) async {
    final license = company.license;
    final planController = TextEditingController(
      text: license?.plan ?? 'trial',
    );
    final expiresAtController = TextEditingController(
      text: license?.expiresAt == null
          ? ''
          : AppFormatters.shortDate(license!.expiresAt!),
    );
    final maxDevicesController = TextEditingController(
      text: license?.maxDevices?.toString() ?? '',
    );
    var selectedStatus = license?.status ?? 'trial';
    var syncEnabled = license?.syncEnabled ?? true;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final controllerState = ref.watch(adminLicenseControllerProvider);
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                8,
                20,
                20 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  Text(
                    'Editar licenca',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    company.name,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 18),
                  AppInput(
                    controller: planController,
                    labelText: 'Plano',
                    hintText: 'trial, legacy, pro...',
                    prefixIcon: const Icon(Icons.workspace_premium_outlined),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: selectedStatus,
                    decoration: const InputDecoration(
                      labelText: 'Status da licenca',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'trial', child: Text('Trial')),
                      DropdownMenuItem(value: 'active', child: Text('Ativa')),
                      DropdownMenuItem(
                        value: 'suspended',
                        child: Text('Suspensa'),
                      ),
                      DropdownMenuItem(
                        value: 'expired',
                        child: Text('Expirada'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setModalState(() {
                        selectedStatus = value;
                      });
                    },
                  ),
                  const SizedBox(height: 14),
                  AppInput(
                    controller: expiresAtController,
                    labelText: 'Validade',
                    hintText: 'dd/mm/aaaa ou vazio',
                    prefixIcon: const Icon(Icons.event_outlined),
                  ),
                  const SizedBox(height: 14),
                  AppInput(
                    controller: maxDevicesController,
                    labelText: 'Limite de dispositivos',
                    hintText: 'Opcional',
                    keyboardType: TextInputType.number,
                    prefixIcon: const Icon(Icons.devices_rounded),
                  ),
                  const SizedBox(height: 14),
                  SwitchListTile.adaptive(
                    value: syncEnabled,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Sincronizacao cloud habilitada'),
                    subtitle: const Text(
                      'Quando desabilitada, o app continua local e a sync fica bloqueada.',
                    ),
                    onChanged: (value) {
                      setModalState(() {
                        syncEnabled = value;
                      });
                    },
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: controllerState.isLoading
                        ? null
                        : () async {
                            try {
                              final expiresAt = _parseDateInput(
                                expiresAtController.text,
                              );
                              final maxDevices = int.tryParse(
                                maxDevicesController.text.trim(),
                              );
                              await ref
                                  .read(adminLicenseControllerProvider.notifier)
                                  .updateLicense(
                                    companyId: company.id,
                                    plan: planController.text.trim().isEmpty
                                        ? 'trial'
                                        : planController.text.trim(),
                                    status: selectedStatus,
                                    expiresAt: expiresAt,
                                    syncEnabled: syncEnabled,
                                    maxDevices: maxDevices,
                                  );
                              if (!context.mounted) {
                                return;
                              }
                              Navigator.of(context).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Licenca de ${company.name} atualizada.',
                                  ),
                                ),
                              );
                            } catch (error) {
                              if (!context.mounted) {
                                return;
                              }
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(error.toString())),
                              );
                            }
                          },
                    icon: const Icon(Icons.save_outlined),
                    label: Text(
                      controllerState.isLoading
                          ? 'Salvando...'
                          : 'Salvar licenca',
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    planController.dispose();
    expiresAtController.dispose();
    maxDevicesController.dispose();
  }

  DateTime? _parseDateInput(String rawValue) {
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final iso = DateTime.tryParse(trimmed);
    if (iso != null) {
      return iso;
    }

    final parts = trimmed.split('/');
    if (parts.length == 3) {
      final day = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      final year = int.tryParse(parts[2]);
      if (day != null && month != null && year != null) {
        return DateTime(year, month, day);
      }
    }

    throw const FormatException(
      'Use uma data valida em dd/mm/aaaa ou no formato ISO.',
    );
  }

  static AppStatusTone _licenseTone(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return AppStatusTone.success;
      case 'trial':
        return AppStatusTone.info;
      case 'suspended':
        return AppStatusTone.warning;
      case 'expired':
        return AppStatusTone.danger;
      default:
        return AppStatusTone.neutral;
    }
  }
}

class _AdminOverviewSection extends StatelessWidget {
  const _AdminOverviewSection({required this.overview});

  final AdminOverview overview;

  @override
  Widget build(BuildContext context) {
    final statusCounts = overview.syncSummary.licenseStatusCounts;
    return AppSectionCard(
      title: 'Resumo administrativo',
      subtitle:
          'Visao minima de tenants licenciados para operacao cloud do Tatuzin.',
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _CountChip(
            label: '${overview.syncSummary.totalCompanies} empresa(s)',
            icon: Icons.apartment_rounded,
          ),
          _CountChip(
            label: '${statusCounts['active'] ?? 0} ativa(s)',
            icon: Icons.verified_rounded,
          ),
          _CountChip(
            label: '${statusCounts['trial'] ?? 0} trial',
            icon: Icons.hourglass_top_rounded,
          ),
          _CountChip(
            label: '${statusCounts['expired'] ?? 0} expirada(s)',
            icon: Icons.event_busy_rounded,
          ),
          _CountChip(
            label:
                '${overview.syncSummary.syncEnabledCompanies} com sync cloud',
            icon: Icons.cloud_done_outlined,
          ),
        ],
      ),
    );
  }
}

class _SyncOverviewSection extends StatelessWidget {
  const _SyncOverviewSection({required this.overview});

  final AdminOverview overview;

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      title: 'Saude de sync na cloud',
      subtitle:
          'Resumo simples por tenant para acompanhar o espelho remoto e a licenca.',
      child: Column(
        children: overview.syncSummary.companySummaries
            .take(8)
            .map(
              (summary) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              summary.companyName,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${summary.remoteRecordCount} registro(s) remotos espelhados',
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          AppStatusBadge(
                            label: summary.licenseStatus == null
                                ? 'Sem licenca'
                                : summary.licenseStatus!,
                            tone: AdminPage._licenseTone(
                              summary.licenseStatus ?? 'without_license',
                            ),
                            icon: Icons.shield_outlined,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            summary.syncEnabled ? 'Sync on' : 'Sync off',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _AuditOverviewSection extends StatelessWidget {
  const _AuditOverviewSection({required this.overview});

  final AdminOverview overview;

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      title: 'Auditoria administrativa',
      subtitle: 'Eventos recentes de licenciamento e administracao cloud.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _CountChip(
                label: '${overview.auditSummary.totalEvents} evento(s)',
                icon: Icons.history_toggle_off_rounded,
              ),
              ...overview.auditSummary.countsByAction.entries.map(
                (entry) => _CountChip(
                  label: '${entry.value} ${entry.key}',
                  icon: Icons.tune_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...overview.auditSummary.recentEvents
              .take(5)
              .map(
                (event) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.action,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${event.actorUserName} • ${event.targetCompanyName ?? 'escopo geral'}',
                        ),
                        if (event.createdAt != null) ...[
                          const SizedBox(height: 4),
                          Text(AppFormatters.shortDateTime(event.createdAt!)),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _CompanyTile extends StatelessWidget {
  const _CompanyTile({required this.company, required this.onTap});

  final AdminCompanySummary company;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final license = company.license;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              child: Text(company.name.characters.first.toUpperCase()),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    company.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(company.slug),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      AppStatusBadge(
                        label: company.isActive ? 'Ativa' : 'Inativa',
                        tone: company.isActive
                            ? AppStatusTone.success
                            : AppStatusTone.warning,
                        icon: Icons.business_rounded,
                      ),
                      if (license != null)
                        AppStatusBadge(
                          label: '${license.plan} • ${license.statusLabel}',
                          tone: AdminPage._licenseTone(license.status),
                          icon: Icons.workspace_premium_rounded,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${company.counts.products} prod.',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  '${company.counts.sales} vendas',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MembershipTile extends StatelessWidget {
  const _MembershipTile({required this.membership});

  final AdminMembershipSummary membership;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            child: Text(membership.userName.characters.first.toUpperCase()),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  membership.userName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(membership.userEmail),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    AppStatusBadge(
                      label: membership.role,
                      tone: AppStatusTone.info,
                      icon: Icons.badge_outlined,
                    ),
                    if (membership.isDefault)
                      const AppStatusBadge(
                        label: 'Padrao',
                        tone: AppStatusTone.neutral,
                        icon: Icons.star_outline,
                      ),
                    if (membership.userIsPlatformAdmin)
                      const AppStatusBadge(
                        label: 'Admin interno',
                        tone: AppStatusTone.warning,
                        icon: Icons.security_rounded,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, size: 18), const SizedBox(width: 8), Text(label)],
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
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
