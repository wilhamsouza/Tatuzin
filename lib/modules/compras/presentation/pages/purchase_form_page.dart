import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/providers/app_data_refresh_provider.dart';
import '../../../../app/core/utils/money_parser.dart';
import '../../../../app/core/utils/quantity_parser.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import '../../../fornecedores/presentation/providers/supplier_providers.dart';
import '../../../produtos/domain/entities/product.dart';
import '../../../produtos/presentation/providers/product_providers.dart';
import '../../../vendas/domain/entities/sale_enums.dart';
import '../../domain/entities/purchase.dart';
import '../../domain/entities/purchase_detail.dart';
import '../../domain/entities/purchase_item.dart';
import '../providers/purchase_providers.dart';
import '../widgets/purchase_summary.dart';

class PurchaseFormArgs {
  const PurchaseFormArgs({this.initialDetail, this.preselectedSupplierId});

  final PurchaseDetail? initialDetail;
  final int? preselectedSupplierId;
}

class PurchaseFormPage extends ConsumerStatefulWidget {
  const PurchaseFormPage({super.key, this.args});

  final PurchaseFormArgs? args;

  @override
  ConsumerState<PurchaseFormPage> createState() => _PurchaseFormPageState();
}

class _PurchaseFormPageState extends ConsumerState<PurchaseFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _documentController;
  late final TextEditingController _notesController;
  late final TextEditingController _discountController;
  late final TextEditingController _surchargeController;
  late final TextEditingController _freightController;
  late final TextEditingController _initialPaidController;
  late DateTime _purchasedAt;
  DateTime? _dueDate;
  int? _selectedSupplierId;
  PaymentMethod? _selectedPaymentMethod;
  bool _isSaving = false;
  late List<_EditablePurchaseItem> _items;

  PurchaseDetail? get _initialDetail => widget.args?.initialDetail;
  bool get _isEditing => _initialDetail != null;

  @override
  void initState() {
    super.initState();
    final purchase = _initialDetail?.purchase;
    _documentController = TextEditingController(
      text: purchase?.documentNumber ?? '',
    );
    _notesController = TextEditingController(text: purchase?.notes ?? '');
    _discountController = TextEditingController(
      text: AppFormatters.currencyInputFromCents(purchase?.discountCents ?? 0),
    );
    _surchargeController = TextEditingController(
      text: AppFormatters.currencyInputFromCents(purchase?.surchargeCents ?? 0),
    );
    _freightController = TextEditingController(
      text: AppFormatters.currencyInputFromCents(purchase?.freightCents ?? 0),
    );
    _initialPaidController = TextEditingController(
      text: AppFormatters.currencyInputFromCents(
        purchase?.paidAmountCents ?? 0,
      ),
    );
    _purchasedAt = purchase?.purchasedAt ?? DateTime.now();
    _dueDate = purchase?.dueDate;
    _selectedSupplierId =
        purchase?.supplierId ?? widget.args?.preselectedSupplierId;
    _selectedPaymentMethod = purchase?.paymentMethod;
    _items =
        _initialDetail?.items
            .map(
              (item) => _EditablePurchaseItem(
                productId: item.productId,
                productName: item.productNameSnapshot,
                unitMeasure: item.unitMeasureSnapshot,
                quantityMil: item.quantityMil,
                unitCostCents: item.unitCostCents,
              ),
            )
            .toList() ??
        <_EditablePurchaseItem>[];
    _discountController.addListener(_refreshComputedTotals);
    _surchargeController.addListener(_refreshComputedTotals);
    _freightController.addListener(_refreshComputedTotals);
    _initialPaidController.addListener(_refreshComputedTotals);
  }

  @override
  void dispose() {
    _discountController.removeListener(_refreshComputedTotals);
    _surchargeController.removeListener(_refreshComputedTotals);
    _freightController.removeListener(_refreshComputedTotals);
    _initialPaidController.removeListener(_refreshComputedTotals);
    _documentController.dispose();
    _notesController.dispose();
    _discountController.dispose();
    _surchargeController.dispose();
    _freightController.dispose();
    _initialPaidController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final suppliersAsync = ref.watch(supplierOptionsProvider);
    final productsAsync = ref.watch(productCatalogProvider);

    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Editar compra' : 'Nova compra')),
      body: suppliersAsync.when(
        data: (suppliers) {
          return productsAsync.when(
            data: (products) => Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                children: [
                  AppSectionCard(
                    title: 'Fornecedor',
                    subtitle: 'Selecione quem está fornecendo os itens.',
                    child: Column(
                      children: [
                        DropdownButtonFormField<int>(
                          initialValue: _selectedSupplierId,
                          items: [
                            for (final supplier in suppliers)
                              DropdownMenuItem<int>(
                                value: supplier.id,
                                child: Text(
                                  supplier.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Fornecedor',
                          ),
                          validator: (value) {
                            if (value == null) {
                              return 'Selecione um fornecedor';
                            }
                            return null;
                          },
                          onChanged: (value) {
                            setState(() => _selectedSupplierId = value);
                          },
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _pickPurchaseDate(context),
                                icon: const Icon(Icons.event_outlined),
                                label: Text(
                                  'Compra em ${AppFormatters.shortDate(_purchasedAt)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _pickDueDate(context),
                                icon: const Icon(Icons.schedule_outlined),
                                label: Text(
                                  _dueDate == null
                                      ? 'Sem vencimento'
                                      : 'Vence ${AppFormatters.shortDate(_dueDate!)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _documentController,
                          decoration: const InputDecoration(
                            labelText: 'Número do documento',
                            hintText: 'Opcional',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  AppSectionCard(
                    title: 'Itens',
                    subtitle: _items.isEmpty
                        ? 'Adicione produtos à compra.'
                        : '${_items.length} ${_items.length == 1 ? 'item adicionado' : 'itens adicionados'}.',
                    child: _PurchaseItemsSection(
                      items: _items,
                      onAddItem: () => _openItemEditor(products),
                      onEditItem: (index) =>
                          _openItemEditor(products, index: index),
                      onRemoveItem: (index) {
                        setState(() => _items.removeAt(index));
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  AppSectionCard(
                    title: 'Resumo financeiro',
                    subtitle: 'Os totais são recalculados automaticamente.',
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _discountController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Desconto',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _surchargeController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Acréscimo',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _freightController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(labelText: 'Frete'),
                        ),
                        const SizedBox(height: 18),
                        PurchaseSummary(
                          subtotalCents: _subtotalCents,
                          discountCents: _discountCents,
                          surchargeCents: _surchargeCents,
                          freightCents: _freightCents,
                          finalAmountCents: _finalAmountCents,
                          paidAmountCents: _initialPaidCents,
                          pendingAmountCents: _pendingAmountCents,
                          compact: true,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  AppSectionCard(
                    title: 'Pagamento',
                    subtitle:
                        'Compras à vista registram saída no caixa. Compras a prazo não movimentam o caixa agora.',
                    child: Column(
                      children: [
                        DropdownButtonFormField<PaymentMethod?>(
                          initialValue: _selectedPaymentMethod,
                          items: const [
                            DropdownMenuItem<PaymentMethod?>(
                              value: null,
                              child: Text('A prazo / sem pagamento agora'),
                            ),
                            DropdownMenuItem<PaymentMethod?>(
                              value: PaymentMethod.cash,
                              child: Text('Dinheiro'),
                            ),
                            DropdownMenuItem<PaymentMethod?>(
                              value: PaymentMethod.pix,
                              child: Text('Pix'),
                            ),
                            DropdownMenuItem<PaymentMethod?>(
                              value: PaymentMethod.card,
                              child: Text('Cartão'),
                            ),
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Forma de pagamento',
                          ),
                          onChanged: (value) {
                            setState(() => _selectedPaymentMethod = value);
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _initialPaidController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Valor pago agora',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  AppSectionCard(
                    title: 'Observações',
                    subtitle: 'Registre detalhes importantes da compra.',
                    child: TextFormField(
                      controller: _notesController,
                      decoration: const InputDecoration(
                        labelText: 'Observação',
                        hintText: 'Opcional',
                      ),
                      minLines: 3,
                      maxLines: 5,
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _isSaving ? null : _save,
                    icon: const Icon(Icons.check_circle_outline_rounded),
                    label: Text(
                      _isEditing ? 'Salvar compra' : 'Confirmar compra',
                    ),
                  ),
                ],
              ),
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Falha ao carregar produtos: $error'),
              ),
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

  int get _subtotalCents =>
      _items.fold<int>(0, (total, item) => total + item.subtotalCents);
  int get _discountCents => MoneyParser.parseToCents(_discountController.text);
  int get _surchargeCents =>
      MoneyParser.parseToCents(_surchargeController.text);
  int get _freightCents => MoneyParser.parseToCents(_freightController.text);
  int get _initialPaidCents =>
      MoneyParser.parseToCents(_initialPaidController.text);
  int get _finalAmountCents =>
      _subtotalCents - _discountCents + _surchargeCents + _freightCents;
  int get _pendingAmountCents => _finalAmountCents - _initialPaidCents;

  void _refreshComputedTotals() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> _pickPurchaseDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _purchasedAt,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _purchasedAt = picked);
    }
  }

  Future<void> _pickDueDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? _purchasedAt,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _dueDate = picked);
    }
  }

  Future<void> _openItemEditor(List<Product> products, {int? index}) async {
    final current = index == null ? null : _items[index];
    final edited = await showModalBottomSheet<_EditablePurchaseItem>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          _PurchaseItemEditorSheet(products: products, initialItem: current),
    );

    if (edited == null) {
      return;
    }

    setState(() {
      if (index == null) {
        _items.add(edited);
      } else {
        _items[index] = edited;
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_selectedSupplierId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Selecione um fornecedor.')));
      return;
    }
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Adicione ao menos um item.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final repository = ref.read(purchaseRepositoryProvider);
      final input = PurchaseUpsertInput(
        supplierId: _selectedSupplierId!,
        documentNumber: _documentController.text,
        notes: _notesController.text,
        purchasedAt: _purchasedAt,
        dueDate: _dueDate,
        paymentMethod: _selectedPaymentMethod,
        items: _items
            .map(
              (item) => PurchaseItemInput(
                productId: item.productId,
                quantityMil: item.quantityMil,
                unitCostCents: item.unitCostCents,
              ),
            )
            .toList(),
        discountCents: _discountCents,
        surchargeCents: _surchargeCents,
        freightCents: _freightCents,
        initialPaidAmountCents: _initialPaidCents,
      );

      if (_isEditing) {
        await repository.update(_initialDetail!.purchase.id, input);
      } else {
        await repository.create(input);
      }

      ref.invalidate(purchaseListProvider);
      ref.read(appDataRefreshProvider.notifier).state++;

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
      ).showSnackBar(SnackBar(content: Text('Falha ao salvar compra: $error')));
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }
}

class _PurchaseItemsSection extends StatelessWidget {
  const _PurchaseItemsSection({
    required this.items,
    required this.onAddItem,
    required this.onEditItem,
    required this.onRemoveItem,
  });

  final List<_EditablePurchaseItem> items;
  final VoidCallback onAddItem;
  final ValueChanged<int> onEditItem;
  final ValueChanged<int> onRemoveItem;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (items.isEmpty) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.playlist_add_circle_outlined,
                color: colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text(
                'Adicione produtos à compra',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Selecione o produto, informe quantidade e custo unitário para montar a compra corretamente.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onAddItem,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Adicionar produto'),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final summary = Text(
              '${items.length} ${items.length == 1 ? 'item lançado' : 'itens lançados'} nesta compra',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            );

            if (constraints.maxWidth < 440) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  summary,
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: onAddItem,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Adicionar produto'),
                  ),
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: summary),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: onAddItem,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Adicionar produto'),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        for (var index = 0; index < items.length; index++) ...[
          _PurchaseItemTile(
            item: items[index],
            onEdit: () => onEditItem(index),
            onRemove: () => onRemoveItem(index),
          ),
          if (index < items.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _PurchaseItemTile extends StatelessWidget {
  const _PurchaseItemTile({
    required this.item,
    required this.onEdit,
    required this.onRemove,
  });

  final _EditablePurchaseItem item;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.productName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          child: Text(
                            'Unidade: ${item.unitMeasure}',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Editar item',
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: 'Remover item',
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final stats = [
                  _ItemStat(
                    label: 'Quantidade',
                    value: AppFormatters.quantityFromMil(item.quantityMil),
                  ),
                  _ItemStat(
                    label: 'Custo unitário',
                    value: AppFormatters.currencyFromCents(item.unitCostCents),
                  ),
                  _ItemStat(
                    label: 'Subtotal',
                    value: AppFormatters.currencyFromCents(item.subtotalCents),
                    emphasize: true,
                  ),
                ];

                if (constraints.maxWidth < 420) {
                  return Column(
                    children: [
                      for (var index = 0; index < stats.length; index++) ...[
                        if (index > 0) const SizedBox(height: 10),
                        stats[index],
                      ],
                    ],
                  );
                }

                return Row(
                  children: [
                    for (var index = 0; index < stats.length; index++) ...[
                      if (index > 0) const SizedBox(width: 12),
                      Expanded(child: stats[index]),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PurchaseItemEditorSheet extends StatefulWidget {
  const _PurchaseItemEditorSheet({required this.products, this.initialItem});

  final List<Product> products;
  final _EditablePurchaseItem? initialItem;

  @override
  State<_PurchaseItemEditorSheet> createState() =>
      _PurchaseItemEditorSheetState();
}

class _PurchaseItemEditorSheetState extends State<_PurchaseItemEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _searchController;
  late final TextEditingController _quantityController;
  late final TextEditingController _costController;
  int? _selectedProductId;

  @override
  void initState() {
    super.initState();
    final item = widget.initialItem;
    _selectedProductId = item?.productId;
    _searchController = TextEditingController(text: item?.productName ?? '');
    _quantityController = TextEditingController(
      text: item == null
          ? '1'
          : AppFormatters.quantityFromMil(item.quantityMil),
    );
    _costController = TextEditingController(
      text: AppFormatters.currencyInputFromCents(item?.unitCostCents ?? 0),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _quantityController.dispose();
    _costController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final selectedProduct = _selectedProduct;
    final query = _searchController.text.trim().toLowerCase();
    final filteredProducts =
        widget.products.where((product) {
          if (query.isEmpty) {
            return true;
          }
          final barcode = product.barcode?.toLowerCase() ?? '';
          final modelName = product.modelName?.toLowerCase() ?? '';
          final variantLabel = product.variantLabel?.toLowerCase() ?? '';
          return product.displayName.toLowerCase().contains(query) ||
              modelName.contains(query) ||
              variantLabel.contains(query) ||
              barcode.contains(query);
        }).toList()..sort(
          (a, b) => a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          ),
        );

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Material(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.88,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.initialItem == null
                        ? 'Adicionar produto'
                        : 'Editar item da compra',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Busque um produto, informe quantidade e custo unitário.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    decoration: const InputDecoration(
                      labelText: 'Buscar produto',
                      hintText: 'Digite nome, modelo, variação ou código',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 16),
                  if (selectedProduct != null) ...[
                    _SelectedPurchaseProductCard(product: selectedProduct),
                    const SizedBox(height: 16),
                  ],
                  LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth < 480) {
                        return Column(
                          children: [
                            TextFormField(
                              controller: _quantityController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                labelText: selectedProduct == null
                                    ? 'Quantidade'
                                    : 'Quantidade (${selectedProduct.unitMeasure})',
                              ),
                              validator: (value) {
                                if (_selectedProductId == null) {
                                  return 'Selecione um produto';
                                }
                                if (QuantityParser.parseToMil(value ?? '') <=
                                    0) {
                                  return 'Informe uma quantidade válida';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _costController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Custo unitário',
                              ),
                            ),
                          ],
                        );
                      }

                      return Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _quantityController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                labelText: selectedProduct == null
                                    ? 'Quantidade'
                                    : 'Quantidade (${selectedProduct.unitMeasure})',
                              ),
                              validator: (value) {
                                if (_selectedProductId == null) {
                                  return 'Selecione um produto';
                                }
                                if (QuantityParser.parseToMil(value ?? '') <=
                                    0) {
                                  return 'Informe uma quantidade válida';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _costController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Custo unitário',
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Produtos disponíveis',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: colorScheme.outlineVariant),
                      ),
                      child: filteredProducts.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  'Nenhum produto encontrado para esta busca.',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.all(8),
                              itemCount: filteredProducts.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 6),
                              itemBuilder: (context, index) {
                                final product = filteredProducts[index];
                                final isSelected =
                                    product.id == _selectedProductId;
                                return Material(
                                  color: isSelected
                                      ? colorScheme.secondaryContainer
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(16),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: () => _selectProduct(product),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 10,
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            isSelected
                                                ? Icons.check_circle_rounded
                                                : Icons.inventory_2_outlined,
                                            color: isSelected
                                                ? colorScheme.primary
                                                : colorScheme.onSurfaceVariant,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  product.displayName,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: theme
                                                      .textTheme
                                                      .titleSmall
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  'Unidade ${product.unitMeasure} • Custo ${AppFormatters.currencyFromCents(product.costCents)}',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: theme
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        color: colorScheme
                                                            .onSurfaceVariant,
                                                      ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancelar'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: _saveItem,
                          child: Text(
                            widget.initialItem == null
                                ? 'Adicionar item'
                                : 'Salvar item',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Product? get _selectedProduct {
    if (_selectedProductId == null) {
      return null;
    }
    for (final product in widget.products) {
      if (product.id == _selectedProductId) {
        return product;
      }
    }
    return null;
  }

  void _selectProduct(Product product) {
    setState(() {
      _selectedProductId = product.id;
      if (MoneyParser.parseToCents(_costController.text) == 0) {
        _costController.text = AppFormatters.currencyInputFromCents(
          product.costCents,
        );
      }
    });
  }

  void _saveItem() {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final product = widget.products.firstWhere((item) {
      return item.id == _selectedProductId;
    });
    Navigator.of(context).pop(
      _EditablePurchaseItem(
        productId: product.id,
        productName: product.displayName,
        unitMeasure: product.unitMeasure,
        quantityMil: QuantityParser.parseToMil(_quantityController.text),
        unitCostCents: MoneyParser.parseToCents(_costController.text),
      ),
    );
  }
}

class _SelectedPurchaseProductCard extends StatelessWidget {
  const _SelectedPurchaseProductCard({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(Icons.inventory_2_rounded, color: colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Unidade ${product.unitMeasure} • Estoque ${AppFormatters.quantityFromMil(product.stockMil)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditablePurchaseItem {
  const _EditablePurchaseItem({
    required this.productId,
    required this.productName,
    required this.unitMeasure,
    required this.quantityMil,
    required this.unitCostCents,
  });

  final int productId;
  final String productName;
  final String unitMeasure;
  final int quantityMil;
  final int unitCostCents;

  int get subtotalCents => ((quantityMil * unitCostCents) / 1000).round();
}

class _ItemStat extends StatelessWidget {
  const _ItemStat({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: emphasize
                  ? theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    )
                  : theme.textTheme.titleSmall,
            ),
          ],
        ),
      ),
    );
  }
}
