import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/admin_providers.dart';
import '../../../core/models/admin_plan_models.dart';
import '../../../core/widgets/admin_surface.dart';

const _futureActionMessage =
    'Acao administrativa sera implementada em fase posterior com dry-run, confirmacao explicita e auditoria.';

class PlansPage extends ConsumerWidget {
  const PlansPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plansAsync = ref.watch(adminPlansOverviewProvider);
    return plansAsync.when(
      data: (overview) => RefreshIndicator(
        onRefresh: () async => ref.invalidate(adminPlansOverviewProvider),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Header(overview: overview),
              const SizedBox(height: 16),
              if (overview.items.isEmpty)
                const AdminSurface(
                  title: 'Planos',
                  child: _EmptyState(
                    message: 'Nenhum plano retornado pelo backend.',
                  ),
                )
              else ...[
                _PlanCards(plans: overview.items),
                const SizedBox(height: 16),
                _FeatureMatrix(overview: overview),
                const SizedBox(height: 16),
                _LimitsMatrix(plans: overview.items),
                const SizedBox(height: 16),
                _UsageSection(overview: overview),
                const SizedBox(height: 16),
                const _PlaceholderActions(),
              ],
            ],
          ),
        ),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => AdminSurface(
        title: 'Nao foi possivel carregar planos',
        subtitle: _safeError(error),
        trailing: FilledButton.tonalIcon(
          onPressed: () => ref.invalidate(adminPlansOverviewProvider),
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Tentar novamente'),
        ),
        child: const Text(
          'Erro amigavel: nenhum payload sensivel foi exibido.',
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.overview});

  final AdminPlansOverview overview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AdminSurface(
      title: 'Planos e recursos',
      subtitle:
          'Referencia administrativa read-only dos planos e entitlements.',
      trailing: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: () => context.go('/licenses'),
            icon: const Icon(Icons.workspace_premium_rounded),
            label: const Text('Ver licencas'),
          ),
          OutlinedButton.icon(
            onPressed: () => ref.invalidate(adminPlansOverviewProvider),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Atualizar'),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _ReadOnlyNotice(),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _Metric(
                label: 'Total de planos',
                value: _numberOrUnavailable(overview.usageSummary.totalPlans),
              ),
              _Metric(
                label: 'Empresas FREE',
                value: _numberOrUnavailable(
                  overview.usageSummary.companiesByPlan['FREE'],
                ),
              ),
              _Metric(
                label: 'Empresas BASIC',
                value: _numberOrUnavailable(
                  overview.usageSummary.companiesByPlan['BASIC'],
                ),
              ),
              _Metric(
                label: 'Empresas PRO',
                value: _numberOrUnavailable(
                  overview.usageSummary.companiesByPlan['PRO'],
                ),
              ),
              _Metric(
                label: 'Planos com empresas ativas',
                value: _numberOrUnavailable(
                  overview.usageSummary.plansWithActiveCompanies,
                ),
              ),
              _Metric(
                label: 'Empresas com pendingPlan',
                value: _numberOrUnavailable(
                  overview.usageSummary.pendingPlanCount,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlanCards extends StatelessWidget {
  const _PlanCards({required this.plans});

  final List<AdminPlanCatalogItem> plans;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1120
            ? 3
            : constraints.maxWidth >= 760
            ? 2
            : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: plans.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            childAspectRatio: columns == 1 ? 1.35 : 1.05,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemBuilder: (context, index) => _PlanCard(plan: plans[index]),
        );
      },
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan});

  final AdminPlanCatalogItem plan;

  @override
  Widget build(BuildContext context) {
    return AdminSurface(
      title: '${plan.key} - ${plan.name}',
      subtitle: plan.description ?? 'Descricao nao disponivel nesta versao.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(label: Text(_priceLabel(plan))),
              Chip(label: Text('Status: ${_statusLabel(plan.status)}')),
              Chip(label: Text(plan.isPublic ? 'Publico' : 'Interno')),
            ],
          ),
          const SizedBox(height: 12),
          _Line(
            label: 'Dispositivos',
            value: _limitLabel(plan.entitlements.limits.maxDevices),
          ),
          _Line(
            label: 'Funcionarios',
            value: _limitLabel(plan.entitlements.limits.maxEmployees),
          ),
          _Line(
            label: 'Empresas usando',
            value: _numberOrUnavailable(plan.usage.companiesCount),
          ),
          const SizedBox(height: 8),
          for (final feature in plan.featuresSummary.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, size: 16),
                  const SizedBox(width: 6),
                  Expanded(child: Text(feature)),
                ],
              ),
            ),
          if (plan.observations.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              plan.observations.first,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _FeatureMatrix extends StatelessWidget {
  const _FeatureMatrix({required this.overview});

  final AdminPlansOverview overview;

  @override
  Widget build(BuildContext context) {
    final plans = _plansInOrder(overview.items);
    return AdminSurface(
      title: 'Matriz de features',
      subtitle:
          'Linhas derivadas do FeatureKey real. A matriz usa o plano ativo; pendingPlan nao libera recurso.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(label: Text('Incluido')),
              Chip(label: Text('Nao incluido')),
              Chip(
                label: Text('Parcial: nao ha regra parcial no contrato atual'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('FeatureKey')),
                DataColumn(label: Text('Descricao')),
                DataColumn(label: Text('FREE')),
                DataColumn(label: Text('BASIC')),
                DataColumn(label: Text('PRO')),
                DataColumn(label: Text('Plano minimo')),
              ],
              rows: overview.features
                  .map(
                    (feature) => DataRow(
                      cells: [
                        DataCell(Text(feature.key)),
                        DataCell(Text(_featureLabel(feature.key))),
                        ...plans.map(
                          (plan) => DataCell(
                            _FeatureState(
                              included: plan.hasFeature(feature.key),
                            ),
                          ),
                        ),
                        DataCell(
                          Text(feature.requiredPlan ?? 'Nao disponivel'),
                        ),
                      ],
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        ],
      ),
    );
  }
}

class _LimitsMatrix extends StatelessWidget {
  const _LimitsMatrix({required this.plans});

  final List<AdminPlanCatalogItem> plans;

  @override
  Widget build(BuildContext context) {
    final orderedPlans = _plansInOrder(plans);
    return AdminSurface(
      title: 'Limites por plano',
      subtitle: 'Limites reais retornados pelo contrato de entitlements.',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Limite')),
            DataColumn(label: Text('FREE')),
            DataColumn(label: Text('BASIC')),
            DataColumn(label: Text('PRO')),
          ],
          rows: [
            DataRow(
              cells: [
                const DataCell(Text('Dispositivos')),
                ...orderedPlans.map(
                  (plan) => DataCell(
                    Text(_limitLabel(plan.entitlements.limits.maxDevices)),
                  ),
                ),
              ],
            ),
            DataRow(
              cells: [
                const DataCell(Text('Funcionarios')),
                ...orderedPlans.map(
                  (plan) => DataCell(
                    Text(_limitLabel(plan.entitlements.limits.maxEmployees)),
                  ),
                ),
              ],
            ),
            DataRow(
              cells: [
                const DataCell(Text('Periodos de relatorio')),
                ...orderedPlans.map(
                  (plan) => DataCell(
                    Text(
                      plan.entitlements.limits.reportPeriods.isEmpty
                          ? 'Nao disponivel'
                          : plan.entitlements.limits.reportPeriods
                                .map(_reportPeriodLabel)
                                .join(', '),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _UsageSection extends StatelessWidget {
  const _UsageSection({required this.overview});

  final AdminPlansOverview overview;

  @override
  Widget build(BuildContext context) {
    final plans = _plansInOrder(overview.items);
    return AdminSurface(
      title: 'Empresas por plano',
      subtitle:
          'Contagens agregadas por license.plan. Use Licencas para abrir empresas.',
      trailing: FilledButton.tonalIcon(
        onPressed: () => context.go('/licenses'),
        icon: const Icon(Icons.open_in_new_rounded),
        label: const Text('Abrir Licencas'),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Plano ativo')),
            DataColumn(label: Text('Empresas')),
            DataColumn(label: Text('Empresas ativas')),
            DataColumn(label: Text('Como pendingPlan')),
            DataColumn(label: Text('Acao')),
          ],
          rows: plans
              .map(
                (plan) => DataRow(
                  cells: [
                    DataCell(Text(plan.key)),
                    DataCell(
                      Text(_numberOrUnavailable(plan.usage.companiesCount)),
                    ),
                    DataCell(
                      Text(
                        _numberOrUnavailable(plan.usage.activeCompaniesCount),
                      ),
                    ),
                    DataCell(
                      Text(_numberOrUnavailable(plan.usage.pendingPlanCount)),
                    ),
                    DataCell(
                      TextButton.icon(
                        onPressed: () => context.go('/licenses'),
                        icon: const Icon(Icons.workspace_premium_rounded),
                        label: const Text('Ver licencas'),
                      ),
                    ),
                  ],
                ),
              )
              .toList(growable: false),
        ),
      ),
    );
  }
}

class _PlaceholderActions extends StatelessWidget {
  const _PlaceholderActions();

  @override
  Widget build(BuildContext context) {
    return const AdminSurface(
      title: 'Acoes futuras',
      subtitle:
          'Todas as acoes abaixo sao placeholders e nao chamam backend mutavel.',
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _PlaceholderButton(
            label: 'Editar preco',
            icon: Icons.payments_rounded,
          ),
          _PlaceholderButton(
            label: 'Editar recursos',
            icon: Icons.tune_rounded,
          ),
          _PlaceholderButton(
            label: 'Arquivar plano',
            icon: Icons.archive_rounded,
          ),
          _PlaceholderButton(label: 'Duplicar plano', icon: Icons.copy_rounded),
          _PlaceholderButton(
            label: 'Publicar/ocultar plano',
            icon: Icons.visibility_rounded,
          ),
        ],
      ),
    );
  }
}

class _FeatureState extends StatelessWidget {
  const _FeatureState({required this.included});

  final bool included;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          included ? Icons.check_circle_rounded : Icons.cancel_rounded,
          color: included ? Colors.green.shade700 : Colors.grey.shade500,
        ),
        const SizedBox(width: 6),
        Text(included ? 'Incluido' : 'Nao incluido'),
      ],
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
      message: _futureActionMessage,
      child: OutlinedButton.icon(
        onPressed: () {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text(_futureActionMessage)));
        },
        icon: Icon(icon),
        label: Text('$label (placeholder)'),
      ),
    );
  }
}

class _ReadOnlyNotice extends StatelessWidget {
  const _ReadOnlyNotice();

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
        'Alteracoes reais de planos serao implementadas em fase posterior com dry-run, confirmacao explicita e auditoria. license.plan e a fonte real; pendingPlan nao libera recursos.',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: scheme.onSecondaryContainer,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(child: Text(label)),
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

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(child: Text(message, textAlign: TextAlign.center)),
    );
  }
}

List<AdminPlanCatalogItem> _plansInOrder(List<AdminPlanCatalogItem> plans) {
  AdminPlanCatalogItem? find(String key) {
    for (final plan in plans) {
      if (plan.key.toUpperCase() == key) {
        return plan;
      }
    }
    return null;
  }

  return [
    'FREE',
    'BASIC',
    'PRO',
  ].map(find).whereType<AdminPlanCatalogItem>().toList(growable: false);
}

String _priceLabel(AdminPlanCatalogItem plan) {
  final price = plan.priceCents;
  if (price == null) {
    return 'Preco nao configurado nesta versao';
  }
  if (price == 0) {
    return 'Gratuito';
  }
  final amount = (price / 100).toStringAsFixed(2).replaceAll('.', ',');
  final cycle = plan.billingCycle == 'monthly' ? '/mes' : '';
  return '${plan.currency ?? 'BRL'} $amount$cycle';
}

String _featureLabel(String key) {
  const labels = {
    'sales': 'PDV e vendas',
    'cash': 'Caixa',
    'products': 'Produtos',
    'categories': 'Categorias',
    'customersBasic': 'Clientes basico',
    'fiadoCreateSale': 'Fiado no checkout',
    'fiadoManagement': 'Gestao de fiado',
    'supplies': 'Insumos',
    'costs': 'Custos',
    'suppliers': 'Fornecedores',
    'purchases': 'Compras',
    'inventoryBasic': 'Estoque basico',
    'inventoryAdvanced': 'Estoque avancado',
    'reportsDaily': 'Relatorio diario',
    'reportsBasic': 'Relatorios basicos',
    'reportsAdvanced': 'Relatorios avancados',
    'employees': 'Funcionarios PRO',
    'permissions': 'Papeis e permissoes',
    'multiDevice': 'Multi-dispositivo',
    'ownerWebPanel': 'Owner web',
    'commissions': 'Comissoes',
    'devicesManagement': 'Gestao de dispositivos',
  };
  return labels[key] ?? 'Nao reconhecida';
}

String _reportPeriodLabel(String period) {
  switch (period) {
    case 'daily':
      return 'diario';
    case 'weekly':
      return 'semanal';
    case 'monthly':
      return 'mensal';
    case 'yearly':
      return 'anual';
    case 'custom':
      return 'customizado';
    default:
      return period;
  }
}

String _limitLabel(int? value) {
  if (value == null) {
    return 'Nao disponivel';
  }
  return value.toString();
}

String _numberOrUnavailable(int? value) {
  return value == null ? 'Nao disponivel' : value.toString();
}

String _statusLabel(String status) {
  return status.toUpperCase() == 'ACTIVE' ? 'Ativo' : status;
}

String _safeError(Object error) {
  final text = error.toString();
  if (text.contains('Exception:')) {
    return text.split('Exception:').last.trim();
  }
  return text.length > 180 ? '${text.substring(0, 180)}...' : text;
}
