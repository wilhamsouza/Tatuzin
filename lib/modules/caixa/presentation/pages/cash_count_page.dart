import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../app/core/formatters/app_formatters.dart';
import '../../domain/entities/cash_closure_preview.dart';

class CashCountPage extends StatefulWidget {
  const CashCountPage({
    super.key,
    this.useLabel = 'Usar total na conferência',
    this.initialDraft,
    this.onDraftChanged,
  });
  final String useLabel;
  final Map<String, dynamic>? initialDraft;
  final ValueChanged<Map<String, dynamic>>? onDraftChanged;
  @override
  State<CashCountPage> createState() => _CashCountPageState();
}

class _CashCountPageState extends State<CashCountPage> {
  final _controllers = {
    for (final value in [20000, 10000, 5000, 2000, 1000, 500, 200, 100])
      value: TextEditingController(),
  };
  final _coins = TextEditingController();
  String? _error;
  @override
  void initState() {
    super.initState();
    final draft = widget.initialDraft;
    for (final entry in _controllers.entries) {
      entry.value.text =
          (draft?['quantities'] as Map?)?[entry.key.toString()] as String? ??
          '';
    }
    _coins.text = draft?['coins'] as String? ?? '';
  }

  void _changed(String _) {
    setState(() {});
    widget.onDraftChanged?.call({
      'quantities': {
        for (final entry in _controllers.entries)
          entry.key.toString(): entry.value.text,
      },
      'coins': _coins.text,
    });
  }

  CashCountResult? get _result {
    final coins = _coins.text.trim().isEmpty ? 0 : parseCashAmount(_coins.text);
    if (coins == null) return null;
    final quantities = <int, int>{};
    for (final entry in _controllers.entries) {
      final quantity = entry.value.text.isEmpty
          ? 0
          : int.tryParse(entry.value.text);
      if (quantity == null || quantity < 0 || quantity > 1000000) return null;
      quantities[entry.key] = quantity;
    }
    final result = CashCountResult(
      denominations: quantities,
      coinsCents: coins,
    );
    return result.isValid ? result : null;
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _coins.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Contar dinheiro')),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Informe a quantidade de cada cédula e o valor das moedas.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 16),
                for (final entry in _controllers.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextField(
                      controller: entry.value,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: _changed,
                      decoration: InputDecoration(
                        labelText:
                            'Quantidade de ${AppFormatters.currencyFromCents(entry.key)}',
                      ),
                    ),
                  ),
                TextField(
                  controller: _coins,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: _changed,
                  decoration: const InputDecoration(
                    labelText: 'Total em moedas (R\$)',
                    hintText: '0,00',
                  ),
                ),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Total contado: ${AppFormatters.currencyFromCents(_result?.totalCents ?? 0)}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: () {
                    final result = _result;
                    if (result == null) {
                      setState(
                        () => _error =
                            'Confira as quantidades e o valor das moedas.',
                      );
                      return;
                    }
                    Navigator.of(context).pop(result);
                  },
                  child: Text(widget.useLabel),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
