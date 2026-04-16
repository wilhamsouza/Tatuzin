import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/utils/money_parser.dart';
import '../../../../app/core/utils/quantity_parser.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import '../../../fornecedores/presentation/providers/supplier_providers.dart';
import '../../domain/entities/supply.dart';
import '../../domain/entities/supply_cost_history_entry.dart';
import '../providers/supply_providers.dart';

class SupplyFormPage extends ConsumerStatefulWidget {
  const SupplyFormPage({super.key, this.initialSupply});

  final Supply? initialSupply;

  @override
  ConsumerState<SupplyFormPage> createState() => _SupplyFormPageState();
}

class _SupplyFormPageState extends ConsumerState<SupplyFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _skuController;
  late final TextEditingController _conversionFactorController;
  late final TextEditingController _lastPurchasePriceController;
  late final TextEditingController _averagePurchasePriceController;
  late final TextEditingController _currentStockController;
  late final TextEditingController _minimumStockController;

  late String _selectedUnitType;
  late String _selectedPurchaseUnitType;
  int? _selectedSupplierId;
  late bool _isActive;
  bool _isSaving = false;

  bool get _isEditing => widget.initialSupply != null;

  @override
  void initState() {
    super.initState();
    final supply = widget.initialSupply;
    _nameController = TextEditingController(text: supply?.name ?? '');
    _skuController = TextEditingController(text: supply?.sku ?? '');
    _conversionFactorController = TextEditingController(
      text: '${supply?.conversionFactor ?? 1}',
    );
    _lastPurchasePriceController = TextEditingController(
      text: AppFormatters.currencyInputFromCents(
        supply?.lastPurchasePriceCents ?? 0,
      ),
    );
    _averagePurchasePriceController = TextEditingController(
      text: supply?.averagePurchasePriceCents == null
          ? ''
          : AppFormatters.currencyInputFromCents(
              supply!.averagePurchasePriceCents!,
            ),
    );
    _currentStockController = TextEditingController(
      text: supply?.currentStockMil == null
          ? ''
          : AppFormatters.quantityFromMil(supply!.currentStockMil!),
    );
    _minimumStockController = TextEditingController(
      text: supply?.minimumStockMil == null
          ? ''
          : AppFormatters.quantityFromMil(supply!.minimumStockMil!),
    );
    _selectedUnitType = supply?.unitType ?? SupplyUnitTypes.unit;
    _selectedPurchaseUnitType =
        supply?.purchaseUnitType ?? SupplyUnitTypes.unit;
    _selectedSupplierId = supply?.defaultSupplierId;
    _isActive = supply?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _skuController.dispose();
    _conversionFactorController.dispose();
    _lastPurchasePriceController.dispose();
    _averagePurchasePriceController.dispose();
    _currentStockController.dispose();
    _minimumStockController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final suppliersAsync = ref.watch(supplierOptionsProvider);
    final costHistoryAsync = _isEditing
        ? ref.watch(supplyCostHistoryProvider(widget.initialSupply!.id))
        : null;

    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Editar insumo' : 'Novo insumo')),
      body: suppliersAsync.when(
        data: (suppliers) {
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nome',
                    hintText: 'Ex.: Mussarela, Embalagem P',
                  ),
                  textCapitalization: TextCapitalization.words,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Informe o nome do insumo';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _skuController,
                  decoration: const InputDecoration(
                    labelText: 'SKU',
                    hintText: 'Opcional',
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedPurchaseUnitType,
                        decoration: const InputDecoration(
                          labelText: 'Unidade de compra',
                        ),
                        items: _buildUnitItems(),
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          setState(() => _selectedPurchaseUnitType = value);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedUnitType,
                        decoration: const InputDecoration(
                          labelText: 'Unidade de uso',
                        ),
                        items: _buildUnitItems(),
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          setState(() => _selectedUnitType = value);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _conversionFactorController,
                  decoration: const InputDecoration(
                    labelText: 'Fator de conversao',
                    helperText:
                        'Ex.: compra em kg e usa em g = 1000. Se a unidade for a mesma, use 1.',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    final parsed = int.tryParse((value ?? '').trim());
                    if (parsed == null || parsed <= 0) {
                      return 'Informe um fator maior que zero';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _lastPurchasePriceController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Preco da ultima compra',
                    prefixText: 'R\$ ',
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _averagePurchasePriceController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Preco medio',
                    hintText: 'Opcional',
                    prefixText: 'R\$ ',
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int?>(
                  initialValue: _selectedSupplierId,
                  decoration: const InputDecoration(
                    labelText: 'Fornecedor padrao',
                  ),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('Sem fornecedor padrao'),
                    ),
                    for (final supplier in suppliers)
                      DropdownMenuItem<int?>(
                        value: supplier.id,
                        child: Text(supplier.name),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => _selectedSupplierId = value),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _currentStockController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Saldo operacional alvo',
                          hintText: 'Opcional ($_selectedUnitType)',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _minimumStockController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Estoque minimo',
                          hintText: 'Opcional ($_selectedUnitType)',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const AppSectionCard(
                  title: 'Estoque operacional',
                  subtitle:
                      'O saldo passa a ser derivado do ledger local de movimentacoes.',
                  child: Text(
                    'Ao salvar, o saldo informado vira um ajuste manual auditavel. Compras com insumo entram no estoque e vendas com ficha tecnica consomem o saldo automaticamente.',
                  ),
                ),
                const SizedBox(height: 16),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _isActive,
                  title: const Text('Insumo ativo'),
                  onChanged: (value) => setState(() => _isActive = value),
                ),
                if (costHistoryAsync != null) ...[
                  const SizedBox(height: 20),
                  AppSectionCard(
                    title: 'Historico de custo',
                    subtitle:
                        'Referencias manuais e atualizacoes automaticas vindas das compras.',
                    child: costHistoryAsync.when(
                      data: (entries) {
                        if (entries.isEmpty) {
                          return const Text(
                            'Nenhuma variacao de custo registrada ainda.',
                          );
                        }
                        return Column(
                          children: [
                            for (
                              var index = 0;
                              index < entries.length;
                              index++
                            ) ...[
                              _HistoryRow(entry: entries[index]),
                              if (index < entries.length - 1)
                                const Divider(height: 20),
                            ],
                          ],
                        );
                      },
                      loading: () =>
                          const LinearProgressIndicator(minHeight: 3),
                      error: (error, _) =>
                          Text('Falha ao carregar historico: $error'),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _isSaving ? null : _save,
                  child: Text(
                    _isEditing ? 'Salvar alteracoes' : 'Criar insumo',
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Falha ao carregar fornecedores: $error'),
          ),
        ),
      ),
    );
  }

  List<DropdownMenuItem<String>> _buildUnitItems() {
    return SupplyUnitTypes.values
        .map(
          (unit) => DropdownMenuItem<String>(
            value: unit,
            child: Text(_unitLabel(unit)),
          ),
        )
        .toList(growable: false);
  }

  String _unitLabel(String unit) {
    return switch (unit) {
      SupplyUnitTypes.kilogram => 'Quilograma (kg)',
      SupplyUnitTypes.gram => 'Grama (g)',
      SupplyUnitTypes.liter => 'Litro (l)',
      SupplyUnitTypes.milliliter => 'Mililitro (ml)',
      SupplyUnitTypes.box => 'Caixa (cx)',
      _ => 'Unidade (un)',
    };
  }

  int? _parseOptionalMil(String raw) {
    if (raw.trim().isEmpty) {
      return null;
    }
    return QuantityParser.parseToMil(raw);
  }

  int? _parseOptionalCents(String raw) {
    if (raw.trim().isEmpty) {
      return null;
    }
    return MoneyParser.parseToCents(raw);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSaving = true);
    try {
      final input = SupplyInput(
        name: _nameController.text,
        sku: _skuController.text,
        unitType: _selectedUnitType,
        purchaseUnitType: _selectedPurchaseUnitType,
        conversionFactor:
            int.tryParse(_conversionFactorController.text.trim()) ?? 1,
        lastPurchasePriceCents: MoneyParser.parseToCents(
          _lastPurchasePriceController.text,
        ),
        averagePurchasePriceCents: _parseOptionalCents(
          _averagePurchasePriceController.text,
        ),
        currentStockMil: _parseOptionalMil(_currentStockController.text),
        minimumStockMil: _parseOptionalMil(_minimumStockController.text),
        defaultSupplierId: _selectedSupplierId,
        isActive: _isActive,
      );

      final controller = ref.read(supplyActionControllerProvider.notifier);
      if (_isEditing) {
        await controller.updateSupply(
          supplyId: widget.initialSupply!.id,
          input: input,
        );
      } else {
        await controller.createSupply(input);
      }

      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Falha ao salvar insumo: $error')));
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry});

  final SupplyCostHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final averagePriceLabel = entry.averagePurchasePriceCents == null
        ? 'Sem media'
        : AppFormatters.currencyFromCents(entry.averagePurchasePriceCents!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                entry.eventType.label,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              AppFormatters.shortDateTime(entry.occurredAt),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            Text(entry.source.label),
            Text(
              'Ultimo: ${AppFormatters.currencyFromCents(entry.lastPurchasePriceCents)}',
            ),
            Text('Medio: $averagePriceLabel'),
            Text(
              'Compra em ${entry.purchaseUnitType} • fator ${entry.conversionFactor}',
            ),
          ],
        ),
        if (entry.purchaseId != null) ...[
          const SizedBox(height: 6),
          Text('Compra #${entry.purchaseId}'),
        ],
        if ((entry.changeSummary ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(entry.changeSummary!),
        ],
        if ((entry.notes ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(entry.notes!),
        ],
      ],
    );
  }
}
