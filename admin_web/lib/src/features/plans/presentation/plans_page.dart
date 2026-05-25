import 'package:flutter/material.dart';

import '../../../core/widgets/admin_surface.dart';

class PlansPage extends StatelessWidget {
  const PlansPage({super.key});

  static const _plans = <_PlanConfig>[
    _PlanConfig(
      key: 'FREE',
      price: 'R\$ 0',
      maxDevices: '1',
      maxEmployees: '0',
      reportPeriods: 'Diario',
      features: {
        'PDV e caixa': true,
        'Produtos e categorias': true,
        'Clientes basico': true,
        'Fiado gestao': false,
        'Compras e fornecedores': false,
        'Estoque avancado': false,
        'Relatorios avancados': false,
        'Funcionarios': false,
        'Owner Web': false,
      },
    ),
    _PlanConfig(
      key: 'BASIC',
      price: 'Contrato',
      maxDevices: '1',
      maxEmployees: '0',
      reportPeriods: 'Diario, semanal, mensal',
      features: {
        'PDV e caixa': true,
        'Produtos e categorias': true,
        'Clientes basico': true,
        'Fiado gestao': true,
        'Compras e fornecedores': true,
        'Estoque avancado': true,
        'Relatorios avancados': false,
        'Funcionarios': false,
        'Owner Web': false,
      },
    ),
    _PlanConfig(
      key: 'PRO',
      price: 'Contrato',
      maxDevices: '100',
      maxEmployees: '100',
      reportPeriods: 'Diario, semanal, mensal, anual, custom',
      features: {
        'PDV e caixa': true,
        'Produtos e categorias': true,
        'Clientes basico': true,
        'Fiado gestao': true,
        'Compras e fornecedores': true,
        'Estoque avancado': true,
        'Relatorios avancados': true,
        'Funcionarios': true,
        'Owner Web': true,
      },
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminSurface(
            title: 'Planos read-only',
            subtitle:
                'Matriz visual baseada no contrato de entitlements FREE/BASIC/PRO. Nenhum salvamento real esta habilitado.',
            trailing: Tooltip(
              message:
                  'Edicao real sera implementada em fase posterior com dry-run, confirmacao e auditoria.',
              child: OutlinedButton.icon(
                onPressed: null,
                icon: const Icon(Icons.edit_rounded),
                label: const Text('Editar plano'),
              ),
            ),
            child: const _ReadOnlyNotice(),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1100
                  ? 3
                  : constraints.maxWidth >= 720
                  ? 2
                  : 1;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _plans.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  childAspectRatio: 1.55,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemBuilder: (context, index) => _PlanCard(plan: _plans[index]),
              );
            },
          ),
          const SizedBox(height: 16),
          AdminSurface(
            title: 'Matriz de features',
            subtitle: 'Limites e modulos por plano.',
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Feature / Limite')),
                  DataColumn(label: Text('FREE')),
                  DataColumn(label: Text('BASIC')),
                  DataColumn(label: Text('PRO')),
                ],
                rows: [
                  _limitRow('Max dispositivos', (plan) => plan.maxDevices),
                  _limitRow('Max funcionarios', (plan) => plan.maxEmployees),
                  _limitRow(
                    'Periodos de relatorio',
                    (plan) => plan.reportPeriods,
                  ),
                  ..._plans.first.features.keys.map(
                    (feature) => DataRow(
                      cells: [
                        DataCell(Text(feature)),
                        ..._plans.map(
                          (plan) => DataCell(
                            Icon(
                              plan.features[feature] == true
                                  ? Icons.check_circle_rounded
                                  : Icons.cancel_rounded,
                              color: plan.features[feature] == true
                                  ? Colors.green.shade700
                                  : Colors.grey.shade500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static DataRow _limitRow(
    String label,
    String Function(_PlanConfig plan) read,
  ) {
    return DataRow(
      cells: [
        DataCell(Text(label)),
        ..._plans.map((plan) => DataCell(Text(read(plan)))),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan});

  final _PlanConfig plan;

  @override
  Widget build(BuildContext context) {
    return AdminSurface(
      title: plan.key,
      subtitle: plan.price,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Line(label: 'Dispositivos', value: plan.maxDevices),
          _Line(label: 'Funcionarios', value: plan.maxEmployees),
          _Line(label: 'Relatorios', value: plan.reportPeriods),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: null,
            icon: const Icon(Icons.edit_rounded),
            label: const Text('Editar placeholder'),
          ),
        ],
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
        'Nao e permitido salvar alteracoes reais ainda. A tela e apenas configuracao visual/read-only.',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: scheme.onSecondaryContainer,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _PlanConfig {
  const _PlanConfig({
    required this.key,
    required this.price,
    required this.maxDevices,
    required this.maxEmployees,
    required this.reportPeriods,
    required this.features,
  });

  final String key;
  final String price;
  final String maxDevices;
  final String maxEmployees;
  final String reportPeriods;
  final Map<String, bool> features;
}
