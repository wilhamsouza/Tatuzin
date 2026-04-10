import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/routes/route_names.dart';
import '../../../carrinho/domain/entities/cart_item.dart';
import '../../../produtos/domain/entities/modifier_group.dart';
import '../../../produtos/domain/entities/modifier_option.dart';
import '../../../produtos/domain/entities/product.dart';
import '../../../produtos/presentation/providers/product_providers.dart';
import '../../../vendas/domain/entities/checkout_input.dart';
import '../../domain/entities/operational_order.dart';
import '../../domain/entities/operational_order_item_modifier.dart';
import '../../../vendas/domain/entities/sale_enums.dart';
import '../../../vendas/presentation/providers/sales_providers.dart';
import 'order_ticket_preview_page.dart';
import '../providers/order_providers.dart';

class OrderDetailPage extends ConsumerWidget {
  const OrderDetailPage({super.key, required this.orderId});

  final int orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orderAsync = ref.watch(operationalOrderDetailProvider(orderId));

    return Scaffold(
      appBar: AppBar(title: Text('Pedido #$orderId')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addItem(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Adicionar item'),
      ),
      body: orderAsync.when(
        data: (detail) {
          if (detail == null) {
            return const Center(child: Text('Pedido nao encontrado.'));
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Status: ${_statusLabel(detail.order.status)}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Atualizado em ${AppFormatters.shortDateTime(detail.order.updatedAt)}',
                      ),
                      if (detail.order.notes?.trim().isNotEmpty ?? false) ...[
                        const SizedBox(height: 6),
                        Text('Obs.: ${detail.order.notes!}'),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _LinkedSaleCard(orderId: orderId),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _openTicketPreview(context),
                      icon: const Icon(Icons.receipt_long_rounded),
                      label: const Text('Gerar ticket'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _canConvertToSale(detail)
                          ? () => _convertToSale(context, ref, detail)
                          : null,
                      icon: const Icon(Icons.point_of_sale_rounded),
                      label: Text(_convertButtonLabel(detail)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (detail.items.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('Nenhum item no pedido ainda.'),
                  ),
                )
              else
                ...detail.items.map((itemDetail) {
                  final item = itemDetail.item;
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.productNameSnapshot,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${AppFormatters.quantityFromMil(item.quantityMil)} x ${AppFormatters.currencyFromCents(item.unitPriceCents)}',
                          ),
                          if (item.baseProductId != null) ...[
                            const SizedBox(height: 4),
                            Text('Base vinculada: #${item.baseProductId}'),
                          ],
                          if (item.notes?.trim().isNotEmpty ?? false) ...[
                            const SizedBox(height: 4),
                            Text('Obs.: ${item.notes!}'),
                          ],
                          if (itemDetail.modifiers.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            ...itemDetail.modifiers.map(
                              (modifier) => Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Text(
                                  '- ${modifier.groupNameSnapshot ?? 'Grupo'}: ${modifier.optionNameSnapshot} (${modifier.adjustmentTypeSnapshot})',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              AppFormatters.currencyFromCents(
                                itemDetail.totalCents,
                              ),
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Itens: ${detail.itemsCount}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      Text(
                        AppFormatters.currencyFromCents(detail.totalCents),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text('Falha ao carregar pedido: $error')),
      ),
    );
  }

  Future<void> _addItem(BuildContext context, WidgetRef ref) async {
    final result = await showModalBottomSheet<_AddOrderItemResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _AddOrderItemSheet(),
    );
    if (result == null) {
      return;
    }

    try {
      await ref
          .read(addOperationalOrderItemControllerProvider.notifier)
          .addItemWithModifiers(
            orderId: orderId,
            product: result.product,
            quantityUnits: result.quantityUnits,
            notes: result.notes,
            modifiers: result.modifiers,
          );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Falha ao adicionar item: $error')),
        );
    }
  }

  void _openTicketPreview(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OrderTicketPreviewPage(orderId: orderId),
      ),
    );
  }

  Future<void> _convertToSale(
    BuildContext context,
    WidgetRef ref,
    OperationalOrderDetail detail,
  ) async {
    if (detail.items.isEmpty) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nao ha itens para converter em venda.')),
      );
      return;
    }

    if (detail.order.status == OperationalOrderStatus.canceled) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pedido cancelado nao pode ser convertido em venda.'),
        ),
      );
      return;
    }

    final linkedSaleId = await ref
        .read(operationalOrderRepositoryProvider)
        .findLinkedSaleId(orderId);
    if (linkedSaleId != null) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Este pedido ja foi convertido na venda #$linkedSaleId.',
            ),
          ),
        );
      context.pushNamed(
        AppRouteNames.saleReceipt,
        pathParameters: {'saleId': '$linkedSaleId'},
      );
      return;
    }

    if (detail.order.status == OperationalOrderStatus.delivered) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Pedido ja esta encerrado. Vincule a venda existente se necessario.',
          ),
        ),
      );
      return;
    }

    final confirmed = await _confirmConvertToSale(context, detail);
    if (confirmed != true) {
      return;
    }

    final paymentMethod = await _pickImmediatePaymentMethod(context);
    if (paymentMethod == null) {
      return;
    }

    final List<CartItem> cartItems = detail.items
        .map<CartItem>((entry) {
          final item = entry.item;
          final modifiers = entry.modifiers
              .map(
                (modifier) => CartItemModifier(
                  modifierGroupId: modifier.modifierGroupId,
                  modifierOptionId: modifier.modifierOptionId,
                  groupName: modifier.groupNameSnapshot ?? 'Modificador',
                  optionName: modifier.optionNameSnapshot,
                  adjustmentType: modifier.adjustmentTypeSnapshot,
                  priceDeltaCents: modifier.priceDeltaCents,
                  quantity: modifier.quantity,
                ),
              )
              .toList(growable: false);
          return CartItem(
            id: 'order_item_${item.id}',
            productId: item.productId,
            productName: item.productNameSnapshot,
            primaryPhotoPath: null,
            baseProductId: item.baseProductId,
            baseProductName: null,
            quantityMil: item.quantityMil,
            availableStockMil: item.quantityMil,
            unitPriceCents: item.unitPriceCents,
            unitMeasure: 'un',
            productType: 'unidade',
            modifiers: modifiers,
            notes: item.notes,
          );
        })
        .toList(growable: false);

    final checkoutInput = CheckoutInput(
      items: cartItems,
      saleType: SaleType.cash,
      paymentMethod: paymentMethod,
      operationalOrderId: orderId,
      notes: 'Venda originada do pedido operacional #$orderId.',
    );

    try {
      final sale = await ref
          .read(saleRepositoryProvider)
          .completeCashSale(input: checkoutInput);
      if (!context.mounted) {
        return;
      }
      ref.invalidate(operationalOrderDetailProvider(orderId));
      ref.invalidate(operationalOrdersProvider);
      context.pushNamed(
        AppRouteNames.saleReceipt,
        pathParameters: {'saleId': '${sale.saleId}'},
        extra: true,
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Falha ao converter: $error')));
    }
  }

  Future<bool?> _confirmConvertToSale(
    BuildContext context,
    OperationalOrderDetail detail,
  ) {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Confirmar conversao'),
          content: Text(
            'Gerar venda para o pedido #$orderId com ${detail.itemsCount} item(ns), total de ${AppFormatters.currencyFromCents(detail.totalCents)}?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Converter'),
            ),
          ],
        );
      },
    );
  }

  Future<PaymentMethod?> _pickImmediatePaymentMethod(
    BuildContext context,
  ) async {
    return showDialog<PaymentMethod>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Forma de pagamento'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('Dinheiro'),
                onTap: () => Navigator.of(context).pop(PaymentMethod.cash),
              ),
              ListTile(
                title: const Text('Pix'),
                onTap: () => Navigator.of(context).pop(PaymentMethod.pix),
              ),
              ListTile(
                title: const Text('Cartao'),
                onTap: () => Navigator.of(context).pop(PaymentMethod.card),
              ),
            ],
          ),
        );
      },
    );
  }

  String _statusLabel(OperationalOrderStatus status) {
    switch (status) {
      case OperationalOrderStatus.open:
        return 'Aberto';
      case OperationalOrderStatus.inPreparation:
        return 'Em preparo';
      case OperationalOrderStatus.ready:
        return 'Pronto';
      case OperationalOrderStatus.delivered:
        return 'Entregue';
      case OperationalOrderStatus.canceled:
        return 'Cancelado';
      case OperationalOrderStatus.draft:
        return 'Rascunho';
    }
  }

  bool _canConvertToSale(OperationalOrderDetail detail) {
    return detail.items.isNotEmpty &&
        detail.order.status != OperationalOrderStatus.canceled &&
        detail.order.status != OperationalOrderStatus.delivered;
  }

  String _convertButtonLabel(OperationalOrderDetail detail) {
    if (detail.items.isEmpty) {
      return 'Sem itens';
    }
    if (detail.order.status == OperationalOrderStatus.canceled) {
      return 'Pedido cancelado';
    }
    if (detail.order.status == OperationalOrderStatus.delivered) {
      return 'Pedido encerrado';
    }
    return 'Converter em venda';
  }
}

class _AddOrderItemResult {
  const _AddOrderItemResult({
    required this.product,
    required this.quantityUnits,
    required this.notes,
    required this.modifiers,
  });

  final Product product;
  final int quantityUnits;
  final String? notes;
  final List<OperationalOrderItemModifierInput> modifiers;
}

class _AddOrderItemSheet extends ConsumerStatefulWidget {
  const _AddOrderItemSheet();

  @override
  ConsumerState<_AddOrderItemSheet> createState() => _AddOrderItemSheetState();
}

class _AddOrderItemSheetState extends ConsumerState<_AddOrderItemSheet> {
  final _searchController = TextEditingController();
  final _notesController = TextEditingController();
  Product? _selectedProduct;
  int _quantityUnits = 1;
  String _search = '';
  final Set<int> _selectedOptionIds = <int>{};
  final Map<int, ModifierOption> _optionsById = <int, ModifierOption>{};
  final Map<int, ModifierGroup> _groupsById = <int, ModifierGroup>{};
  bool _loadingModifiers = false;

  @override
  void dispose() {
    _searchController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catalogAsync = ref.watch(orderCatalogProvider(_search));

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Buscar SKU para adicionar',
            ),
            onChanged: (value) => setState(() => _search = value.trim()),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 180,
            child: catalogAsync.when(
              data: (products) => ListView.builder(
                itemCount: products.length,
                itemBuilder: (context, index) {
                  final product = products[index];
                  final selected = _selectedProduct?.id == product.id;
                  return ListTile(
                    selected: selected,
                    title: Text(product.displayName),
                    subtitle: Text(
                      AppFormatters.currencyFromCents(product.salePriceCents),
                    ),
                    trailing: selected ? const Icon(Icons.check) : null,
                    onTap: () => _selectProduct(product),
                  );
                },
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) =>
                  Center(child: Text('Falha ao buscar catalogo: $error')),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Quantidade'),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _quantityUnits > 1
                    ? () => setState(() => _quantityUnits--)
                    : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text('$_quantityUnits'),
              IconButton(
                onPressed: () => setState(() => _quantityUnits++),
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          TextField(
            controller: _notesController,
            decoration: const InputDecoration(
              labelText: 'Observacao do item (opcional)',
            ),
            minLines: 1,
            maxLines: 2,
          ),
          const SizedBox(height: 8),
          if (_loadingModifiers)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: CircularProgressIndicator(),
            )
          else if (_groupsById.isNotEmpty)
            SizedBox(
              height: 180,
              child: ListView(
                children: _groupsById.values
                    .map((group) {
                      final options = _optionsById.values
                          .where((option) => option.groupId == group.id)
                          .toList(growable: false);
                      return ExpansionTile(
                        title: Text(group.name),
                        subtitle: Text(
                          group.isRequired ? 'Obrigatorio' : 'Opcional',
                        ),
                        children: options
                            .map((option) {
                              final selected = _selectedOptionIds.contains(
                                option.id,
                              );
                              return CheckboxListTile(
                                value: selected,
                                title: Text(option.name),
                                subtitle: Text(
                                  option.priceDeltaCents == 0
                                      ? option.adjustmentType
                                      : '${option.adjustmentType} (${AppFormatters.currencyFromCents(option.priceDeltaCents)})',
                                ),
                                onChanged: (value) {
                                  setState(() {
                                    if (value == true) {
                                      _selectedOptionIds.add(option.id);
                                    } else {
                                      _selectedOptionIds.remove(option.id);
                                    }
                                  });
                                },
                              );
                            })
                            .toList(growable: false),
                      );
                    })
                    .toList(growable: false),
              ),
            ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _selectedProduct == null
                  ? null
                  : () => Navigator.of(context).pop(
                      _AddOrderItemResult(
                        product: _selectedProduct!,
                        quantityUnits: _quantityUnits,
                        notes: _cleanNullable(_notesController.text),
                        modifiers: _buildModifierInputs(),
                      ),
                    ),
              icon: const Icon(Icons.check),
              label: const Text('Adicionar no pedido'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _selectProduct(Product product) async {
    setState(() {
      _selectedProduct = product;
      _selectedOptionIds.clear();
      _optionsById.clear();
      _groupsById.clear();
      _loadingModifiers = true;
    });

    if (product.baseProductId == null) {
      setState(() => _loadingModifiers = false);
      return;
    }

    final localCatalog = ref.read(localCatalogRepositoryProvider);
    final groups = await localCatalog.listModifierGroups(
      product.baseProductId!,
    );
    for (final group in groups) {
      _groupsById[group.id] = group;
      final options = await localCatalog.listModifierOptions(group.id);
      for (final option in options) {
        _optionsById[option.id] = option;
      }
    }

    if (!mounted) {
      return;
    }
    setState(() => _loadingModifiers = false);
  }

  List<OperationalOrderItemModifierInput> _buildModifierInputs() {
    final modifiers = <OperationalOrderItemModifierInput>[];
    for (final optionId in _selectedOptionIds) {
      final option = _optionsById[optionId];
      if (option == null) {
        continue;
      }
      final group = _groupsById[option.groupId];
      modifiers.add(
        OperationalOrderItemModifierInput(
          modifierGroupId: group?.id,
          modifierOptionId: option.id,
          groupNameSnapshot: group?.name,
          optionNameSnapshot: option.name,
          adjustmentTypeSnapshot: option.adjustmentType,
          priceDeltaCents: option.priceDeltaCents,
          quantity: 1,
        ),
      );
    }
    return modifiers;
  }

  String? _cleanNullable(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

class _LinkedSaleCard extends ConsumerWidget {
  const _LinkedSaleCard({required this.orderId});

  final int orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<int?>(
      future: ref
          .read(operationalOrderRepositoryProvider)
          .findLinkedSaleId(orderId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }
        final saleId = snapshot.data;
        if (saleId == null) {
          return const SizedBox.shrink();
        }
        return Card(
          child: ListTile(
            title: const Text('Venda vinculada'),
            subtitle: Text('Venda #$saleId gerada a partir deste pedido.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              context.pushNamed(
                AppRouteNames.saleReceipt,
                pathParameters: {'saleId': '$saleId'},
              );
            },
          ),
        );
      },
    );
  }
}
