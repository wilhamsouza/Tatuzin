import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/constants/app_constants.dart';
import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import '../../../../app/core/widgets/app_status_badge.dart';
import '../../../../app/routes/route_names.dart';
import '../../../caixa/presentation/providers/cash_providers.dart';
import '../../../carrinho/domain/entities/cart_item.dart';
import '../../../carrinho/presentation/providers/cart_provider.dart';
import '../../../clientes/domain/entities/client.dart';
import '../../../clientes/presentation/providers/client_providers.dart';
import '../../../dashboard/presentation/providers/dashboard_providers.dart';
import '../../../fiado/presentation/providers/fiado_providers.dart';
import '../../../historico_vendas/presentation/providers/sale_history_providers.dart';
import '../../../produtos/presentation/providers/product_providers.dart';
import '../../../vendas/domain/entities/checkout_input.dart';
import '../../../vendas/domain/entities/sale_enums.dart';
import '../../../vendas/presentation/providers/sales_providers.dart';

class CheckoutPage extends ConsumerStatefulWidget {
  const CheckoutPage({super.key});

  @override
  ConsumerState<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends ConsumerState<CheckoutPage> {
  SaleType _saleType = SaleType.cash;
  PaymentMethod _paymentMethod = PaymentMethod.cash;
  Client? _selectedClient;
  DateTime? _dueDate;
  late final TextEditingController _notesController;

  @override
  void initState() {
    super.initState();
    _notesController = TextEditingController();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final checkoutState = ref.watch(checkoutControllerProvider);
    final isSubmitting = checkoutState.isLoading;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    const sectionPadding = EdgeInsets.fromLTRB(16, 16, 16, 16);
    final effectivePaymentMethod = _saleType == SaleType.fiado
        ? PaymentMethod.fiado
        : _paymentMethod;

    return Scaffold(
      appBar: AppBar(title: const Text(AppConstants.appName)),
      body: cart.isEmpty
          ? _CheckoutEmptyState(
              onPressed: () => context.goNamed(AppRouteNames.sales),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 188),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6C4CF1), Color(0xFF8B5CF6)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.point_of_sale_rounded,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Revise a venda e conclua sem perder tempo.',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Os dados abaixo seguem o fluxo atual do caixa e do fiado.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.white.withValues(alpha: 0.86),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      AppStatusBadge(
                        label: '${cart.totalItems} item(ns)',
                        tone: AppStatusTone.neutral,
                        icon: Icons.shopping_bag_outlined,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                AppSectionCard(
                  title: 'Tipo da venda',
                  subtitle: 'Defina como a operação será registrada.',
                  padding: sectionPadding,
                  child: Row(
                    children: [
                      Expanded(
                        child: _ChoiceCard(
                          label: 'À vista',
                          subtitle: 'Recebimento imediato',
                          icon: Icons.payments_outlined,
                          selected: _saleType == SaleType.cash,
                          onTap: isSubmitting
                              ? null
                              : () {
                                  setState(() {
                                    _saleType = SaleType.cash;
                                    if (_paymentMethod == PaymentMethod.fiado) {
                                      _paymentMethod = PaymentMethod.cash;
                                    }
                                  });
                                },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ChoiceCard(
                          label: 'Fiado',
                          subtitle: 'Cliente e vencimento',
                          icon: Icons.receipt_long_rounded,
                          selected: _saleType == SaleType.fiado,
                          onTap: isSubmitting
                              ? null
                              : () {
                                  setState(() {
                                    _saleType = SaleType.fiado;
                                    _paymentMethod = PaymentMethod.fiado;
                                  });
                                },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                AppSectionCard(
                  title: 'Forma de pagamento',
                  subtitle: _saleType == SaleType.cash
                      ? 'Escolha a forma de recebimento em um toque.'
                      : 'No fiado, a forma final permanece registrada como fiado.',
                  padding: sectionPadding,
                  child: _saleType == SaleType.cash
                      ? GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: 3,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                                childAspectRatio: 1.45,
                              ),
                          itemBuilder: (context, index) {
                            final method = [
                              PaymentMethod.cash,
                              PaymentMethod.pix,
                              PaymentMethod.card,
                            ][index];

                            return _ChoiceCard(
                              label: method.label,
                              subtitle: 'Disponível agora',
                              icon: method == PaymentMethod.cash
                                  ? Icons.payments_outlined
                                  : method == PaymentMethod.pix
                                  ? Icons.pix
                                  : Icons.credit_card_rounded,
                              selected: _paymentMethod == method,
                              onTap: isSubmitting
                                  ? null
                                  : () =>
                                        setState(() => _paymentMethod = method),
                            );
                          },
                        )
                      : Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            color: colorScheme.tertiaryContainer.withValues(
                              alpha: 0.5,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.lock_outline,
                                color: colorScheme.onSurface,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Forma persistida: fiado',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
                const SizedBox(height: 12),
                AppSectionCard(
                  title: 'Cliente e vencimento',
                  subtitle: _saleType == SaleType.fiado
                      ? 'Cliente e vencimento continuam obrigatórios para gerar a nota.'
                      : 'Cliente opcional para vincular a venda ao histórico.',
                  padding: sectionPadding,
                  child: Column(
                    children: [
                      _ClientSelector(
                        selectedClient: _selectedClient,
                        isRequired: _saleType == SaleType.fiado,
                        isBusy: isSubmitting,
                        onPickClient: () async {
                          final client = await _pickClient(context);
                          if (client == null) {
                            return;
                          }
                          setState(() => _selectedClient = client);
                        },
                        onClearClient: _selectedClient == null || isSubmitting
                            ? null
                            : () => setState(() => _selectedClient = null),
                      ),
                      if (_saleType == SaleType.fiado) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: isSubmitting
                                ? null
                                : () => _pickDueDate(context),
                            icon: const Icon(Icons.event_outlined),
                            label: Text(
                              _dueDate == null
                                  ? 'Selecionar vencimento'
                                  : 'Vencimento: ${AppFormatters.shortDate(_dueDate!)}',
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                AppSectionCard(
                  title: 'Resumo final',
                  subtitle: 'Confira os produtos antes de concluir.',
                  padding: sectionPadding,
                  child: Column(
                    children: [
                      for (
                        var index = 0;
                        index < cart.items.length;
                        index++
                      ) ...[
                        _CheckoutItemRow(item: cart.items[index]),
                        if (index < cart.items.length - 1)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 10),
                            child: Divider(height: 1),
                          ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                AppSectionCard(
                  title: 'Observação',
                  subtitle:
                      'Opcional. Use somente se precisar registrar contexto extra.',
                  padding: sectionPadding,
                  child: TextField(
                    controller: _notesController,
                    minLines: 1,
                    maxLines: 3,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      hintText: 'Adicionar observação',
                      isDense: true,
                    ),
                  ),
                ),
                if (checkoutState.hasError) ...[
                  const SizedBox(height: 12),
                  Card(
                    color: colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        checkoutState.error.toString(),
                        style: TextStyle(color: colorScheme.onErrorContainer),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    AppStatusBadge(
                      label: _saleType == SaleType.cash
                          ? 'Fluxo à vista'
                          : 'Fluxo fiado',
                      tone: _saleType == SaleType.cash
                          ? AppStatusTone.info
                          : AppStatusTone.warning,
                      icon: _saleType == SaleType.cash
                          ? Icons.payments_outlined
                          : Icons.receipt_long_rounded,
                    ),
                    AppStatusBadge(
                      label: effectivePaymentMethod.label,
                      tone: AppStatusTone.neutral,
                      icon: Icons.check_circle_outline,
                    ),
                  ],
                ),
              ],
            ),
      bottomNavigationBar: cart.isEmpty
          ? null
          : AnimatedPadding(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: SafeArea(
                minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 18,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            color: colorScheme.surfaceContainerLowest,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Total',
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${cart.totalItems} item(ns) - ${_saleType.label}',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _saleType == SaleType.fiado
                                          ? _dueDate == null
                                                ? 'Vencimento pendente'
                                                : 'Vencimento: ${AppFormatters.shortDate(_dueDate!)}'
                                          : effectivePaymentMethod.label,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Valor final',
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    AppFormatters.currencyFromCents(
                                      cart.totalCents,
                                    ),
                                    textAlign: TextAlign.right,
                                    style: theme.textTheme.headlineSmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: -0.3,
                                        ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: isSubmitting
                                ? null
                                : () => _finalize(context),
                            icon: isSubmitting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                    ),
                                  )
                                : const Icon(Icons.check_circle_outline),
                            label: Text(
                              isSubmitting
                                  ? 'Finalizando...'
                                  : 'Finalizar venda',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Future<void> _finalize(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final cartState = ref.read(cartProvider);
    final saleType = _saleType;

    if (saleType == SaleType.fiado && _selectedClient == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Selecione um cliente para finalizar no fiado.'),
        ),
      );
      return;
    }

    if (saleType == SaleType.fiado && _dueDate == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Informe o vencimento da nota a prazo.')),
      );
      return;
    }

    final input = CheckoutInput(
      items: cartState.items,
      saleType: saleType,
      paymentMethod: saleType == SaleType.fiado
          ? PaymentMethod.fiado
          : _paymentMethod,
      operationalOrderId: null,
      clientId: _selectedClient?.id,
      dueDate: _dueDate,
      notes: _notesController.text,
    );

    try {
      final sale = await ref
          .read(checkoutControllerProvider.notifier)
          .finalize(input);

      ref.read(cartProvider.notifier).clear();
      ref.invalidate(productListProvider);
      ref.invalidate(salesCatalogProvider);
      ref.invalidate(clientListProvider);
      ref.invalidate(fiadoListProvider);
      ref.invalidate(currentCashSessionProvider);
      ref.invalidate(currentCashMovementsProvider);
      ref.invalidate(cashSessionHistoryProvider);
      ref.invalidate(saleHistoryListProvider);
      ref.invalidate(dashboardMetricsProvider);

      if (!context.mounted) {
        return;
      }

      context.pushNamed(
        AppRouteNames.saleReceipt,
        pathParameters: {'saleId': '${sale.saleId}'},
        extra: true,
      );
    } catch (_) {
      if (!context.mounted) {
        return;
      }
    }
  }

  Future<void> _pickDueDate(BuildContext context) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );

    if (selected == null) {
      return;
    }

    setState(() {
      _dueDate = DateTime(selected.year, selected.month, selected.day, 23, 59);
    });
  }

  Future<Client?> _pickClient(BuildContext context) async {
    var searchQuery = '';

    return showModalBottomSheet<Client>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Consumer(
              builder: (context, ref, _) {
                final clientsAsync = ref.watch(
                  clientLookupProvider(searchQuery),
                );
                return SafeArea(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: 20,
                      right: 20,
                      top: 20,
                      bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search),
                            hintText: 'Buscar cliente por nome',
                          ),
                          onChanged: (value) {
                            setModalState(() => searchQuery = value);
                          },
                        ),
                        const SizedBox(height: 16),
                        Flexible(
                          child: clientsAsync.when(
                            data: (clients) {
                              if (clients.isEmpty) {
                                return const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(24),
                                    child: Text('Nenhum cliente encontrado.'),
                                  ),
                                );
                              }
                              return ListView.separated(
                                shrinkWrap: true,
                                itemCount: clients.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final client = clients[index];
                                  return ListTile(
                                    title: Text(client.name),
                                    subtitle: Text(
                                      client.phone ?? 'Sem telefone',
                                    ),
                                    onTap: () =>
                                        Navigator.of(context).pop(client),
                                  );
                                },
                              );
                            },
                            loading: () => const Center(
                              child: CircularProgressIndicator(),
                            ),
                            error: (error, _) => Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text('Falha ao buscar clientes: $error'),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _CheckoutItemRow extends StatelessWidget {
  const _CheckoutItemRow({required this.item});

  final CartItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: colorScheme.primaryContainer.withValues(alpha: 0.48),
          ),
          child: Icon(
            item.productType == 'peso'
                ? Icons.scale_outlined
                : Icons.inventory_2_outlined,
            size: 20,
            color: colorScheme.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.productName,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${AppFormatters.quantityFromMil(item.quantityMil)} ${item.unitMeasure} x ${AppFormatters.currencyFromCents(item.unitPriceCents)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              if (item.modifiers.isNotEmpty) ...[
                const SizedBox(height: 4),
                for (final modifier in item.modifiers)
                  Text(
                    '- ${modifier.groupName}: ${modifier.optionName} (${modifier.adjustmentType})',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
              if (item.notes?.trim().isNotEmpty ?? false) ...[
                const SizedBox(height: 4),
                Text(
                  'Obs.: ${item.notes!}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          AppFormatters.currencyFromCents(item.subtotalCents),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _CheckoutEmptyState extends StatelessWidget {
  const _CheckoutEmptyState({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.shopping_cart_outlined,
                      size: 34,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'O carrinho está vazio',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Adicione itens na venda para revisar o checkout por aqui.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: onPressed,
                    icon: const Icon(Icons.storefront_rounded),
                    label: const Text('Voltar para vendas'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ClientSelector extends StatelessWidget {
  const _ClientSelector({
    required this.selectedClient,
    required this.isRequired,
    required this.isBusy,
    required this.onPickClient,
    required this.onClearClient,
  });

  final Client? selectedClient;
  final bool isRequired;
  final bool isBusy;
  final VoidCallback onPickClient;
  final VoidCallback? onClearClient;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        title: Text(
          selectedClient?.name ??
              (isRequired
                  ? 'Selecionar cliente obrigatório'
                  : 'Selecionar cliente (opcional)'),
        ),
        subtitle: Text(
          selectedClient == null
              ? 'Cliente usado para fiado e histórico da venda.'
              : [
                  if (selectedClient!.phone?.isNotEmpty ?? false)
                    selectedClient!.phone!,
                  AppFormatters.currencyFromCents(
                    selectedClient!.debtorBalanceCents,
                  ),
                ].join(' - '),
        ),
        leading: AppStatusBadge(
          label: isRequired ? 'Obrigatório' : 'Opcional',
          tone: isRequired ? AppStatusTone.warning : AppStatusTone.neutral,
        ),
        trailing: Wrap(
          spacing: 2,
          children: [
            if (onClearClient != null)
              IconButton(
                tooltip: 'Remover cliente',
                onPressed: isBusy ? null : onClearClient,
                icon: const Icon(Icons.clear),
              ),
            IconButton(
              tooltip: 'Selecionar cliente',
              onPressed: isBusy ? null : onPickClient,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? colorScheme.primary
                  : colorScheme.outlineVariant,
              width: selected ? 1.6 : 1,
            ),
            color: selected
                ? colorScheme.primaryContainer.withValues(alpha: 0.52)
                : colorScheme.surface,
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? colorScheme.primary : null,
              ),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
