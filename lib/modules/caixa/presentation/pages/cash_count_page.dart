import 'package:flutter/material.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/utils/money_parser.dart';
import '../../../../app/core/widgets/app_page_header.dart';
import '../../../../app/core/widgets/app_section_card.dart';

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
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Contagem do caixa')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 120),
        children: [
          const AppPageHeader(
            title: 'Contagem manual',
            subtitle:
                'Preencha o dinheiro físico para conferir o caixa com rapidez.',
            badgeLabel: 'Dinheiro em caixa',
            badgeIcon: Icons.calculate_outlined,
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total contado',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        AppFormatters.currencyFromCents(totalCents),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_filledFieldsCount()} campos',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          AppSectionCard(
            title: 'Cédulas e moedas',
            subtitle:
                'Informe a quantidade por cédula e o valor total das moedas.',
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                for (final entry in _controllers.entries) ...[
                  _CountField(
                    label: 'Cédula ${entry.key}',
                    controller: entry.value,
                    amountCents: MoneyParser.parseToCents(entry.key),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 10),
                ],
                _CountField(
                  label: 'Moedas',
                  controller: _coinsController,
                  onChanged: (_) => setState(() {}),
                  isCurrency: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          AppSectionCard(
            title: 'Observações',
            subtitle:
                'Use apenas se houver divergência ou contexto importante.',
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _notesController,
              minLines: 3,
              maxLines: 5,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText:
                    'Ex.: troco separado, valor reservado, diferença observada',
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colorScheme.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Total contado',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Text(
                      AppFormatters.currencyFromCents(totalCents),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Contagem registrada visualmente. A conciliação entra na próxima fase.',
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.check_circle_outline_rounded),
                    label: const Text('Concluir contagem'),
                  ),
                ),
              ],
            ),
          ),
        ),
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

  int _filledFieldsCount() {
    final noteCounts = _controllers.values
        .where((controller) => controller.text.trim().isNotEmpty)
        .length;
    final coinsFilled = _coinsController.text.trim().isNotEmpty ? 1 : 0;
    return noteCounts + coinsFilled;
  }
}

class _CountField extends StatelessWidget {
  const _CountField({
    required this.label,
    required this.controller,
    required this.onChanged,
    this.isCurrency = false,
    this.amountCents,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final bool isCurrency;
  final int? amountCents;

  @override
  Widget build(BuildContext context) {
    final quantity = int.tryParse(controller.text.trim()) ?? 0;
    final subtotalCents = isCurrency
        ? MoneyParser.parseToCents(controller.text)
        : (amountCents ?? 0) * quantity;
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  isCurrency
                      ? 'Informe o valor total'
                      : 'Subtotal ${AppFormatters.currencyFromCents(subtotalCents)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 92,
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              keyboardType: isCurrency
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : TextInputType.number,
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                hintText: isCurrency ? '0,00' : '0',
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
