import 'package:flutter/material.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/utils/money_parser.dart';

class CashCountPage extends StatefulWidget {
  const CashCountPage({super.key});

  @override
  State<CashCountPage> createState() => _CashCountPageState();
}

class _CashCountPageState extends State<CashCountPage> {
  final Map<String, TextEditingController> _controllers =
      <String, TextEditingController>{
        '200,00': TextEditingController(),
        '100,00': TextEditingController(),
        '50,00': TextEditingController(),
        '20,00': TextEditingController(),
        '10,00': TextEditingController(),
        '5,00': TextEditingController(),
        '2,00': TextEditingController(),
        '1,00': TextEditingController(),
      };

  final TextEditingController _coinsController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _coinsController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalCents = _calculateTotalCents();

    return Scaffold(
      appBar: AppBar(title: const Text('Contagem de caixa')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Contagem manual',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Preencha as quantidades por cedula e informe moedas em valor total. Esta tela ja deixa o fluxo pronto para conciliacao futura.',
                  ),
                  const SizedBox(height: 16),
                  Text(
                    AppFormatters.currencyFromCents(totalCents),
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cedulas',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  for (final entry in _controllers.entries) ...[
                    _CountField(
                      label: 'Cedula ${entry.key}',
                      controller: entry.value,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                  ],
                  _CountField(
                    label: 'Moedas (valor total)',
                    controller: _coinsController,
                    onChanged: (_) => setState(() {}),
                    isCurrency: true,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Observacoes',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _notesController,
                    minLines: 3,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      hintText:
                          'Divergencias, troco separado, observacoes da contagem',
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.tonal(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Fluxo visual da contagem preparado para a proxima fase.',
                          ),
                        ),
                      );
                    },
                    child: const Text('Registrar observacao da contagem'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  int _calculateTotalCents() {
    var total = 0;
    for (final entry in _controllers.entries) {
      final quantity = int.tryParse(entry.value.text.trim()) ?? 0;
      total += MoneyParser.parseToCents(entry.key) * quantity;
    }
    total += MoneyParser.parseToCents(_coinsController.text);
    return total;
  }
}

class _CountField extends StatelessWidget {
  const _CountField({
    required this.label,
    required this.controller,
    required this.onChanged,
    this.isCurrency = false,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final bool isCurrency;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        hintText: isCurrency ? '0,00' : '0',
      ),
    );
  }
}
