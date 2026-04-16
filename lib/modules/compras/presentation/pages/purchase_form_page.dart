import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/providers/app_data_refresh_provider.dart';
import '../../../../app/core/utils/money_parser.dart';
import '../../../../app/core/utils/quantity_parser.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import '../../../fornecedores/presentation/providers/supplier_providers.dart';
import '../../../insumos/domain/entities/supply.dart';
import '../../../insumos/presentation/providers/supply_providers.dart';
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
                itemType: item.itemType,
                productId: item.productId,
                productVariantId: item.productVariantId,
                supplyId: item.supplyId,
                itemName: item.itemNameSnapshot,
                variantSku: item.variantSkuSnapshot,
                variantColorLabel: item.variantColorLabelSnapshot,
                variantSizeLabel: item.variantSizeLabelSnapshot,
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
    final suppliesAsync = ref.watch(activeSupplyOptionsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Editar compra' : 'Nova compra')),
      body: suppliersAsync.when(
        data: (suppliers) {
          return productsAsync.when(
            data: (products) => suppliesAsync.when(
              data: (supplies) => Form(
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
                    if (_items.any(
                      (item) => item.itemType == PurchaseItemType.supply,
                    )) ...[
                      const SizedBox(height: 16),
                      const AppSectionCard(
                        title: 'Compra local',
                        subtitle:
                            'Compras com insumo continuam operando normalmente, mas ainda nao sincronizam com o backend.',
                        child: Text(
                          'Compra com insumo salva localmente. A sincronizacao remota desse tipo de compra sera habilitada em fase futura.',
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    AppSectionCard(
                      title: 'Itens',
                      subtitle: _items.isEmpty
                          ? 'Adicione produtos à compra.'
                          : '${_items.length} ${_items.length == 1 ? 'item adicionado' : 'itens adicionados'}.',
                      child: _PurchaseItemsSection(
                        items: _items,
                        onAddItem: () => _openItemEditor(products, supplies),
                        onEditItem: (index) =>
                            _openItemEditor(products, supplies, index: index),
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
                            decoration: const InputDecoration(
                              labelText: 'Frete',
                            ),
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
                  child: Text('Falha ao carregar insumos: $error'),
                ),
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

  Future<void> _openItemEditor(
    List<Product> products,
    List<Supply> supplies, {
    int? index,
  }) async {
    final current = index == null ? null : _items[index];
    final edited = await showModalBottomSheet<_EditablePurchaseItem>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _PurchaseItemEditorSheetMixed(
        products: products,
        supplies: supplies,
        initialItem: current,
      ),
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
      final containsSupplyItems = _items.any(
        (item) => item.itemType == PurchaseItemType.supply,
      );
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
                itemType: item.itemType,
                productId: item.productId,
                productVariantId: item.productVariantId,
                supplyId: item.supplyId,
                variantSkuSnapshot: item.variantSku,
                variantColorLabelSnapshot: item.variantColorLabel,
                variantSizeLabelSnapshot: item.variantSizeLabel,
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
      if (containsSupplyItems) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Compra com insumo salva localmente. A sincronizacao remota sera habilitada em fase futura.',
            ),
          ),
        );
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
                label: const Text('Adicionar item'),
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
                    label: const Text('Adicionar item'),
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
                  label: const Text('Adicionar item'),
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
                        item.itemName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _Pill(
                            label: item.itemType.label,
                            color: item.itemType == PurchaseItemType.product
                                ? colorScheme.primaryContainer
                                : colorScheme.secondaryContainer,
                          ),
                          _Pill(
                            label: 'Unidade: ${item.unitMeasure}',
                            color: colorScheme.surfaceContainerHighest,
                          ),
                          if (item.variantSummary != null)
                            _Pill(
                              label: item.variantSummary!,
                              color: colorScheme.tertiaryContainer,
                            ),
                          if ((item.variantSku ?? '').trim().isNotEmpty)
                            _Pill(
                              label: 'SKU ${item.variantSku!.trim()}',
                              color: colorScheme.surfaceContainerHighest,
                            ),
                        ],
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
  const _PurchaseItemEditorSheet({required this.products});

  final List<Product> products;

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
  int? _selectedProductVariantId;

  @override
  void initState() {
    super.initState();
    const _EditablePurchaseItem? item = null;
    _selectedProductId = item?.productId;
    _searchController = TextEditingController(text: item?.itemName ?? '');
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
                    'Adicionar produto',
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
                          child: const Text('Adicionar item'),
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
      final canUseParentProduct =
          _selectedProductVariantId == null &&
          product.variants.where((variant) => variant.isActive).isEmpty;
      if (product.id == _selectedProductId &&
          (product.sellableVariantId == _selectedProductVariantId ||
              canUseParentProduct)) {
        return product;
      }
    }

    for (final product in _buildProductOptions(widget.products)) {
      if (product.id == _selectedProductId &&
          product.sellableVariantId == _selectedProductVariantId) {
        return product;
      }
    }
    return null;
  }

  List<Product> _buildProductOptions(List<Product> sourceProducts) {
    final options = <Product>[];
    for (final product in sourceProducts) {
      final activeVariants = product.variants
          .where((variant) => variant.isActive)
          .toList(growable: false);
      if (activeVariants.isEmpty) {
        options.add(product);
        continue;
      }

      for (final variant in activeVariants) {
        options.add(
          Product(
            id: product.id,
            uuid: product.uuid,
            name: product.name,
            description: product.description,
            categoryId: product.categoryId,
            categoryName: product.categoryName,
            barcode: product.barcode,
            primaryPhotoPath: product.primaryPhotoPath,
            productType: product.productType,
            niche: product.niche,
            catalogType: product.catalogType,
            modelName: product.modelName,
            variantLabel: product.variantLabel,
            baseProductId: product.baseProductId,
            baseProductName: product.baseProductName,
            variantAttributes: product.variantAttributes,
            variants: product.variants,
            modifierGroups: product.modifierGroups,
            sellableVariantId: variant.id,
            sellableVariantSku: variant.sku,
            sellableVariantColorLabel: variant.colorLabel,
            sellableVariantSizeLabel: variant.sizeLabel,
            sellableVariantPriceAdditionalCents: variant.priceAdditionalCents,
            unitMeasure: product.unitMeasure,
            costCents: product.costCents,
            manualCostCents: product.manualCostCents,
            costSource: product.costSource,
            variableCostSnapshotCents: product.variableCostSnapshotCents,
            estimatedGrossMarginCents: product.estimatedGrossMarginCents,
            estimatedGrossMarginPercentBasisPoints:
                product.estimatedGrossMarginPercentBasisPoints,
            lastCostUpdatedAt: product.lastCostUpdatedAt,
            salePriceCents: product.salePriceCents + variant.priceAdditionalCents,
            stockMil: variant.stockMil,
            isActive: product.isActive,
            createdAt: product.createdAt,
            updatedAt: product.updatedAt,
            deletedAt: product.deletedAt,
            remoteId: product.remoteId,
            syncStatus: product.syncStatus,
            lastSyncedAt: product.lastSyncedAt,
          ),
        );
      }
    }
    return options;
  }

  void _selectProduct(Product product) {
    setState(() {
      _selectedProductId = product.id;
      _selectedProductVariantId = product.sellableVariantId;
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
        itemType: PurchaseItemType.product,
        productId: product.id,
        supplyId: null,
        itemName: product.displayName,
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

class _PurchaseItemEditorSheetMixed extends StatefulWidget {
  const _PurchaseItemEditorSheetMixed({
    required this.products,
    required this.supplies,
    this.initialItem,
  });

  final List<Product> products;
  final List<Supply> supplies;
  final _EditablePurchaseItem? initialItem;

  @override
  State<_PurchaseItemEditorSheetMixed> createState() =>
      _PurchaseItemEditorSheetMixedState();
}

class _PurchaseItemEditorSheetMixedState
    extends State<_PurchaseItemEditorSheetMixed> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _searchController;
  late final TextEditingController _quantityController;
  late final TextEditingController _costController;
  late PurchaseItemType _selectedType;
  int? _selectedProductId;
  int? _selectedProductVariantId;
  int? _selectedSupplyId;

  @override
  void initState() {
    super.initState();
    final item = widget.initialItem;
    _selectedType = item?.itemType ?? PurchaseItemType.product;
    _selectedProductId = item?.productId;
    _selectedProductVariantId = item?.productVariantId;
    _selectedSupplyId = item?.supplyId;
    _searchController = TextEditingController(text: item?.itemName ?? '');
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
    final query = _searchController.text.trim().toLowerCase();
    final productOptions = _buildProductOptions(widget.products);
    final selectedProduct = _selectedProduct;
    final selectedSupply = _selectedSupply;
    final filteredProducts =
        productOptions.where((product) {
          if (query.isEmpty) {
            return true;
          }
          final barcode = product.barcode?.toLowerCase() ?? '';
          final modelName = product.modelName?.toLowerCase() ?? '';
          final variantLabel = product.variantLabel?.toLowerCase() ?? '';
          final variantSku = product.sellableVariantSku?.toLowerCase() ?? '';
          final variantColor =
              product.sellableVariantColorLabel?.toLowerCase() ?? '';
          final variantSize =
              product.sellableVariantSizeLabel?.toLowerCase() ?? '';
          return product.displayName.toLowerCase().contains(query) ||
              modelName.contains(query) ||
              variantLabel.contains(query) ||
              variantSku.contains(query) ||
              variantColor.contains(query) ||
              variantSize.contains(query) ||
              barcode.contains(query);
        }).toList()..sort(
          (a, b) => a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          ),
        );
    final filteredSupplies =
        widget.supplies.where((supply) {
          if (query.isEmpty) {
            return true;
          }
          final supplierName = supply.defaultSupplierName?.toLowerCase() ?? '';
          final sku = supply.sku?.toLowerCase() ?? '';
          return supply.name.toLowerCase().contains(query) ||
              supplierName.contains(query) ||
              sku.contains(query);
        }).toList()..sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );

    final quantityLabel = switch (_selectedType) {
      PurchaseItemType.product =>
        selectedProduct == null
            ? 'Quantidade'
            : 'Quantidade (${selectedProduct.unitMeasure})',
      PurchaseItemType.supply =>
        selectedSupply == null
            ? 'Quantidade'
            : 'Quantidade (${selectedSupply.purchaseUnitType})',
    };

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
          height: MediaQuery.of(context).size.height * 0.9,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.initialItem == null
                        ? 'Adicionar item'
                        : 'Editar item da compra',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Escolha entre produto ou insumo e informe quantidade e custo unitario.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SegmentedButton<PurchaseItemType>(
                    segments: const [
                      ButtonSegment<PurchaseItemType>(
                        value: PurchaseItemType.product,
                        icon: Icon(Icons.inventory_2_outlined),
                        label: Text('Produto'),
                      ),
                      ButtonSegment<PurchaseItemType>(
                        value: PurchaseItemType.supply,
                        icon: Icon(Icons.scale_outlined),
                        label: Text('Insumo'),
                      ),
                    ],
                    selected: {_selectedType},
                    onSelectionChanged: (selection) {
                      setState(() {
                        _selectedType = selection.first;
                        _selectedProductId =
                            _selectedType == PurchaseItemType.product
                            ? _selectedProductId
                            : null;
                        _selectedProductVariantId =
                            _selectedType == PurchaseItemType.product
                            ? _selectedProductVariantId
                            : null;
                        _selectedSupplyId =
                            _selectedType == PurchaseItemType.supply
                            ? _selectedSupplyId
                            : null;
                        _searchController.clear();
                        _costController.clear();
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      labelText: _selectedType == PurchaseItemType.product
                          ? 'Buscar produto'
                          : 'Buscar insumo',
                      hintText: _selectedType == PurchaseItemType.product
                          ? 'Digite nome, modelo, variacao ou codigo'
                          : 'Digite nome, fornecedor ou sku',
                      prefixIcon: const Icon(Icons.search_rounded),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 16),
                  if (selectedProduct != null) ...[
                    _SelectedPurchaseProductCard(product: selectedProduct),
                    const SizedBox(height: 16),
                  ],
                  if (selectedSupply != null) ...[
                    _SelectedPurchaseSupplyCard(supply: selectedSupply),
                    const SizedBox(height: 16),
                  ],
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final quantityField = TextFormField(
                        controller: _quantityController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(labelText: quantityLabel),
                        validator: (value) {
                          final hasSelection =
                              _selectedType == PurchaseItemType.product
                              ? _selectedProduct != null
                              : _selectedSupply != null;
                          if (!hasSelection) {
                            return _selectedType == PurchaseItemType.product
                                ? 'Selecione um produto'
                                : 'Selecione um insumo';
                          }
                          if (QuantityParser.parseToMil(value ?? '') <= 0) {
                            return 'Informe uma quantidade valida';
                          }
                          return null;
                        },
                      );
                      if (constraints.maxWidth < 480) {
                        return Column(
                          children: [
                            quantityField,
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _costController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Custo unitario',
                              ),
                            ),
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: quantityField),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _costController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Custo unitario',
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _selectedType == PurchaseItemType.product
                        ? 'Produtos disponiveis'
                        : 'Insumos disponiveis',
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
                      child: _selectedType == PurchaseItemType.product
                          ? _ProductSelectionList(
                              products: filteredProducts,
                              selectedProductId: _selectedProductId,
                              selectedProductVariantId:
                                  _selectedProductVariantId,
                              onSelect: _selectProduct,
                            )
                          : _SupplySelectionList(
                              supplies: filteredSupplies,
                              selectedSupplyId: _selectedSupplyId,
                              onSelect: _selectSupply,
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

  Supply? get _selectedSupply {
    if (_selectedSupplyId == null) {
      return null;
    }
    for (final supply in widget.supplies) {
      if (supply.id == _selectedSupplyId) {
        return supply;
      }
    }
    return null;
  }

  List<Product> _buildProductOptions(List<Product> sourceProducts) {
    final options = <Product>[];
    for (final product in sourceProducts) {
      final activeVariants = product.variants
          .where((variant) => variant.isActive)
          .toList(growable: false);
      if (activeVariants.isEmpty) {
        options.add(product);
        continue;
      }

      for (final variant in activeVariants) {
        options.add(
          Product(
            id: product.id,
            uuid: product.uuid,
            name: product.name,
            description: product.description,
            categoryId: product.categoryId,
            categoryName: product.categoryName,
            barcode: product.barcode,
            primaryPhotoPath: product.primaryPhotoPath,
            productType: product.productType,
            niche: product.niche,
            catalogType: product.catalogType,
            modelName: product.modelName,
            variantLabel: product.variantLabel,
            baseProductId: product.baseProductId,
            baseProductName: product.baseProductName,
            variantAttributes: product.variantAttributes,
            variants: product.variants,
            modifierGroups: product.modifierGroups,
            sellableVariantId: variant.id,
            sellableVariantSku: variant.sku,
            sellableVariantColorLabel: variant.colorLabel,
            sellableVariantSizeLabel: variant.sizeLabel,
            sellableVariantPriceAdditionalCents: variant.priceAdditionalCents,
            unitMeasure: product.unitMeasure,
            costCents: product.costCents,
            manualCostCents: product.manualCostCents,
            costSource: product.costSource,
            variableCostSnapshotCents: product.variableCostSnapshotCents,
            estimatedGrossMarginCents: product.estimatedGrossMarginCents,
            estimatedGrossMarginPercentBasisPoints:
                product.estimatedGrossMarginPercentBasisPoints,
            lastCostUpdatedAt: product.lastCostUpdatedAt,
            salePriceCents: product.salePriceCents + variant.priceAdditionalCents,
            stockMil: variant.stockMil,
            isActive: product.isActive,
            createdAt: product.createdAt,
            updatedAt: product.updatedAt,
            deletedAt: product.deletedAt,
            remoteId: product.remoteId,
            syncStatus: product.syncStatus,
            lastSyncedAt: product.lastSyncedAt,
          ),
        );
      }
    }
    return options;
  }

  void _selectProduct(Product product) {
    setState(() {
      _selectedProductId = product.id;
      _selectedProductVariantId = product.sellableVariantId;
      _selectedSupplyId = null;
      _searchController.text = product.displayName;
      if (MoneyParser.parseToCents(_costController.text) == 0) {
        _costController.text = AppFormatters.currencyInputFromCents(
          product.costCents,
        );
      }
    });
  }

  void _selectSupply(Supply supply) {
    setState(() {
      _selectedSupplyId = supply.id;
      _selectedProductId = null;
      _selectedProductVariantId = null;
      _searchController.text = supply.name;
      if (MoneyParser.parseToCents(_costController.text) == 0) {
        _costController.text = AppFormatters.currencyInputFromCents(
          supply.lastPurchasePriceCents,
        );
      }
    });
  }

  void _saveItem() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final quantityMil = QuantityParser.parseToMil(_quantityController.text);
    final unitCostCents = MoneyParser.parseToCents(_costController.text);
    if (_selectedType == PurchaseItemType.product) {
      final product = _buildProductOptions(widget.products).firstWhere((item) {
        return item.id == _selectedProductId &&
            item.sellableVariantId == _selectedProductVariantId;
      });
      Navigator.of(context).pop(
        _EditablePurchaseItem(
          itemType: PurchaseItemType.product,
          productId: product.id,
          productVariantId: product.sellableVariantId,
          supplyId: null,
          itemName: product.name,
          variantSku: product.sellableVariantSku,
          variantColorLabel: product.sellableVariantColorLabel,
          variantSizeLabel: product.sellableVariantSizeLabel,
          unitMeasure: product.unitMeasure,
          quantityMil: quantityMil,
          unitCostCents: unitCostCents,
        ),
      );
      return;
    }

    final supply = widget.supplies.firstWhere((item) {
      return item.id == _selectedSupplyId;
    });
    Navigator.of(context).pop(
      _EditablePurchaseItem(
        itemType: PurchaseItemType.supply,
        productId: null,
        supplyId: supply.id,
        itemName: supply.name,
        unitMeasure: supply.purchaseUnitType,
        quantityMil: quantityMil,
        unitCostCents: unitCostCents,
      ),
    );
  }
}

class _ProductSelectionList extends StatelessWidget {
  const _ProductSelectionList({
    required this.products,
    required this.selectedProductId,
    required this.selectedProductVariantId,
    required this.onSelect,
  });

  final List<Product> products;
  final int? selectedProductId;
  final int? selectedProductVariantId;
  final ValueChanged<Product> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    if (products.isEmpty) {
      return Center(
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
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(8),
      itemCount: products.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final product = products[index];
        final isSelected =
            product.id == selectedProductId &&
            product.sellableVariantId == selectedProductVariantId;
        return Material(
          color: isSelected
              ? colorScheme.secondaryContainer
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => onSelect(product),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.displayName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            'Unidade ${product.unitMeasure}',
                            if ((product.sellableVariantSku ?? '').trim().isNotEmpty)
                              'SKU ${product.sellableVariantSku!.trim()}',
                            'Saldo ${AppFormatters.quantityFromMil(product.stockMil)}',
                            'Custo ${AppFormatters.currencyFromCents(product.costCents)}',
                          ].join(' | '),
                          maxLines: 2,
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
          ),
        );
      },
    );
  }
}

class _SupplySelectionList extends StatelessWidget {
  const _SupplySelectionList({
    required this.supplies,
    required this.selectedSupplyId,
    required this.onSelect,
  });

  final List<Supply> supplies;
  final int? selectedSupplyId;
  final ValueChanged<Supply> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    if (supplies.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Nenhum insumo encontrado para esta busca.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(8),
      itemCount: supplies.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final supply = supplies[index];
        final isSelected = supply.id == selectedSupplyId;
        return Material(
          color: isSelected
              ? colorScheme.secondaryContainer
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => onSelect(supply),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    isSelected
                        ? Icons.check_circle_rounded
                        : Icons.scale_outlined,
                    color: isSelected
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          supply.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Compra em ${supply.purchaseUnitType} | Ultimo preco ${AppFormatters.currencyFromCents(supply.lastPurchasePriceCents)}',
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
          ),
        );
      },
    );
  }
}

class _SelectedPurchaseSupplyCard extends StatelessWidget {
  const _SelectedPurchaseSupplyCard({required this.supply});

  final Supply supply;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(Icons.scale_outlined, color: colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    supply.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Compra em ${supply.purchaseUnitType} | uso em ${supply.unitType} | fator ${supply.normalizedConversionFactor}',
                    maxLines: 2,
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

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _EditablePurchaseItem {
  const _EditablePurchaseItem({
    required this.itemType,
    required this.productId,
    this.productVariantId,
    required this.supplyId,
    required this.itemName,
    this.variantSku,
    this.variantColorLabel,
    this.variantSizeLabel,
    required this.unitMeasure,
    required this.quantityMil,
    required this.unitCostCents,
  });

  final PurchaseItemType itemType;
  final int? productId;
  final int? productVariantId;
  final int? supplyId;
  final String itemName;
  final String? variantSku;
  final String? variantColorLabel;
  final String? variantSizeLabel;
  final String unitMeasure;
  final int quantityMil;
  final int unitCostCents;

  String? get variantSummary {
    final labels = <String>[
      if ((variantSizeLabel ?? '').trim().isNotEmpty) variantSizeLabel!.trim(),
      if ((variantColorLabel ?? '').trim().isNotEmpty)
        variantColorLabel!.trim(),
    ];
    if (labels.isEmpty) {
      return null;
    }
    return labels.join(' / ');
  }

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
