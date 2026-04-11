import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/utils/money_parser.dart';
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
  late final TextEditingController _creditAmountController;
  late final TextEditingController _amountReceivedController;
  bool _leaveChangeAsCredit = false;

  @override
  void initState() {
    super.initState();
    _notesController = TextEditingController();
    _creditAmountController = TextEditingController();
    _amountReceivedController = TextEditingController();
  }

  @override
  void dispose() {
    _notesController.dispose();
    _creditAmountController.dispose();
    _amountReceivedController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final checkoutState = ref.watch(checkoutControllerProvider);
    final isSubmitting = checkoutState.isLoading;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    const sectionPadding = EdgeInsets.fromLTRB(14, 14, 14, 14);
    final availableCreditCents = _selectedClient?.creditBalanceCents ?? 0;
    final appliedCreditCents =
        _saleType == SaleType.cash && _selectedClient != null
        ? _clampCreditUsage(
            MoneyParser.parseToCents(_creditAmountController.text),
            cart.totalCents,
            availableCreditCents,
          )
        : 0;
    final immediateDueCents = (cart.totalCents - appliedCreditCents) < 0
        ? 0
        : cart.totalCents - appliedCreditCents;
    final tenderedCents = MoneyParser.parseToCents(
      _amountReceivedController.text,
    );
    final changeLeftAsCreditCents =
        _saleType == SaleType.cash &&
            _paymentMethod == PaymentMethod.cash &&
            _selectedClient != null &&
            _leaveChangeAsCredit &&
            tenderedCents > immediateDueCents
        ? tenderedCents - immediateDueCents
        : 0;
    final effectivePaymentMethod = _saleType == SaleType.fiado
        ? PaymentMethod.fiado
        : _paymentMethod;
    final paymentLabel =
        _saleType == SaleType.cash &&
            appliedCreditCents > 0 &&
            immediateDueCents == 0
        ? 'Haver'
        : effectivePaymentMethod.label;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Finalizar venda'),
        actions: [
          IconButton(
            tooltip: 'Voltar ao PDV',
            onPressed: () => context.goNamed(AppRouteNames.sales),
            icon: const Icon(Icons.storefront_outlined),
          ),
          IconButton(
            tooltip: 'Abrir dashboard',
            onPressed: () => context.goNamed(AppRouteNames.dashboard),
            icon: const Icon(Icons.home_outlined),
          ),
        ],
      ),
      body: cart.isEmpty
          ? _CheckoutEmptyState(
              onPressed: () => context.goNamed(AppRouteNames.sales),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 172),
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer.withValues(
                              alpha: 0.72,
                            ),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            Icons.point_of_sale_rounded,
                            color: colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Conferência final',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${cart.totalItems} item(ns) • $paymentLabel',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          AppFormatters.currencyFromCents(cart.totalCents),
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                AppSectionCard(
                  title: 'Tipo da venda',
                  subtitle: 'Escolha o tipo de fechamento da venda.',
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
                                    _dueDate = null;
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
                                    _creditAmountController.clear();
                                    _amountReceivedController.clear();
                                    _leaveChangeAsCredit = false;
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
                      ? 'Selecione como o cliente vai pagar agora.'
                      : 'No fiado, o pagamento fica registrado como fiado.',
                  padding: sectionPadding,
                  child: _saleType == SaleType.cash
                      ? immediateDueCents == 0 && appliedCreditCents > 0
                            ? Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(18),
                                  color: colorScheme.primaryContainer
                                      .withValues(alpha: 0.56),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.account_balance_wallet_outlined,
                                      color: colorScheme.primary,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'Venda coberta integralmente por haver.',
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: 3,
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 2,
                                      crossAxisSpacing: 10,
                                      mainAxisSpacing: 10,
                                      childAspectRatio: 1.7,
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
                                        : () => setState(
                                            () => _paymentMethod = method,
                                          ),
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
                  title: _saleType == SaleType.fiado
                      ? 'Cliente e vencimento'
                      : 'Cliente da venda',
                  subtitle: _saleType == SaleType.fiado
                      ? 'Preencha estes dados para registrar o fiado.'
                      : 'Opcional. Use se quiser vincular a venda ao histórico do cliente.',
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
                          _setSelectedClient(client);
                        },
                        onClearClient: _selectedClient == null || isSubmitting
                            ? null
                            : () => _setSelectedClient(null),
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
                if (_saleType == SaleType.cash && _selectedClient != null) ...[
                  const SizedBox(height: 12),
                  AppSectionCard(
                    title: 'Haver disponível',
                    subtitle:
                        'Abata saldo do cliente antes de receber o restante da venda.',
                    padding: sectionPadding,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _CheckoutSummaryMetric(
                                label: 'Saldo atual',
                                value: AppFormatters.currencyFromCents(
                                  availableCreditCents,
                                ),
                                icon: Icons.account_balance_wallet_outlined,
                                emphasize: availableCreditCents > 0,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _CheckoutSummaryMetric(
                                label: 'Aplicado agora',
                                value: AppFormatters.currencyFromCents(
                                  appliedCreditCents,
                                ),
                                icon: Icons.remove_circle_outline,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _creditAmountController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Valor de haver para usar',
                            hintText: '0,00',
                            suffixIcon: TextButton(
                              onPressed: availableCreditCents <= 0
                                  ? null
                                  : () {
                                      final cents = _clampCreditUsage(
                                        availableCreditCents,
                                        cart.totalCents,
                                        availableCreditCents,
                                      );
                                      _creditAmountController.text =
                                          AppFormatters.currencyInputFromCents(
                                            cents,
                                          );
                                      setState(() {});
                                    },
                              child: const Text('Usar tudo'),
                            ),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: colorScheme.outlineVariant,
                            ),
                          ),
                          child: Text(
                            immediateDueCents == 0
                                ? 'O haver cobre toda a venda.'
                                : 'Restante para receber agora: ${AppFormatters.currencyFromCents(immediateDueCents)}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (_saleType == SaleType.cash &&
                    _paymentMethod == PaymentMethod.cash) ...[
                  const SizedBox(height: 12),
                  AppSectionCard(
                    title: 'Recebimento em dinheiro',
                    subtitle:
                        'Informe quanto entrou agora. Se houver excesso, voce pode devolver ou deixar como haver.',
                    padding: sectionPadding,
                    child: Column(
                      children: [
                        TextField(
                          controller: _amountReceivedController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Valor recebido agora',
                            hintText: AppFormatters.currencyInputFromCents(
                              immediateDueCents,
                            ),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        if (_selectedClient != null) ...[
                          const SizedBox(height: 10),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            value: _leaveChangeAsCredit,
                            onChanged: (value) =>
                                setState(() => _leaveChangeAsCredit = value),
                            title: const Text('Deixar troco como haver'),
                            subtitle: Text(
                              changeLeftAsCreditCents > 0
                                  ? 'Novo haver gerado: ${AppFormatters.currencyFromCents(changeLeftAsCreditCents)}'
                                  : 'Ative se o cliente quiser manter o troco como saldo.',
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                AppSectionCard(
                  title: 'Conferência rápida',
                  subtitle:
                      'Mantenha o foco no pagamento e abra os itens só se precisar revisar.',
                  padding: sectionPadding,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _CheckoutSummaryMetric(
                              label: 'Itens',
                              value: '${cart.totalItems}',
                              icon: Icons.shopping_bag_outlined,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _CheckoutSummaryMetric(
                              label: 'Total',
                              value: AppFormatters.currencyFromCents(
                                cart.totalCents,
                              ),
                              icon: Icons.payments_outlined,
                              emphasize: true,
                            ),
                          ),
                        ],
                      ),
                      if (appliedCreditCents > 0) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _CheckoutSummaryMetric(
                                label: 'Haver aplicado',
                                value: AppFormatters.currencyFromCents(
                                  appliedCreditCents,
                                ),
                                icon: Icons.account_balance_wallet_outlined,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _CheckoutSummaryMetric(
                                label: 'Receber agora',
                                value: AppFormatters.currencyFromCents(
                                  immediateDueCents,
                                ),
                                icon: Icons.payments_outlined,
                                emphasize: immediateDueCents > 0,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => context.goNamed(AppRouteNames.cart),
                          icon: const Icon(Icons.shopping_cart_outlined),
                          label: const Text('Voltar ao carrinho'),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Theme(
                        data: theme.copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          childrenPadding: EdgeInsets.zero,
                          title: Text(
                            'Ver itens da venda',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            cart.items.first.productName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          children: [
                            const SizedBox(height: 6),
                            for (
                              var index = 0;
                              index < cart.items.length;
                              index++
                            ) ...[
                              _CheckoutItemRow(item: cart.items[index]),
                              if (index < cart.items.length - 1)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 8),
                                  child: Divider(height: 1),
                                ),
                            ],
                          ],
                        ),
                      ),
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
                      label: paymentLabel,
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
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: colorScheme.outlineVariant),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 14,
                        offset: const Offset(0, 8),
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
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Total',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _saleType == SaleType.fiado
                                        ? _dueDate == null
                                              ? 'Fiado • vencimento pendente'
                                              : 'Fiado • vence em ${AppFormatters.shortDate(_dueDate!)}'
                                        : paymentLabel,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              AppFormatters.currencyFromCents(cart.totalCents),
                              textAlign: TextAlign.right,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
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
    final availableCreditCents = _selectedClient?.creditBalanceCents ?? 0;
    final creditToUseCents =
        saleType == SaleType.cash && _selectedClient != null
        ? _clampCreditUsage(
            MoneyParser.parseToCents(_creditAmountController.text),
            cartState.totalCents,
            availableCreditCents,
          )
        : 0;
    final immediateDueCents = (cartState.totalCents - creditToUseCents) < 0
        ? 0
        : cartState.totalCents - creditToUseCents;
    final tenderedCents = MoneyParser.parseToCents(
      _amountReceivedController.text,
    );
    final changeLeftAsCreditCents =
        saleType == SaleType.cash &&
            _paymentMethod == PaymentMethod.cash &&
            _selectedClient != null &&
            _leaveChangeAsCredit &&
            tenderedCents > immediateDueCents
        ? tenderedCents - immediateDueCents
        : 0;

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

    if (saleType == SaleType.cash &&
        _paymentMethod == PaymentMethod.cash &&
        immediateDueCents > 0 &&
        tenderedCents > 0 &&
        tenderedCents < immediateDueCents) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'O valor recebido em dinheiro nao cobre o restante da venda.',
          ),
        ),
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
      customerCreditUsedCents: creditToUseCents,
      changeLeftAsCreditCents: changeLeftAsCreditCents,
    );

    try {
      final sale = await ref
          .read(checkoutControllerProvider.notifier)
          .finalize(input);

      ref.read(cartProvider.notifier).clear();
      ref.invalidate(productListProvider);
      ref.invalidate(salesCatalogProvider);
      ref.invalidate(clientListProvider);
      if (_selectedClient != null) {
        ref.invalidate(customerCreditBalanceProvider(_selectedClient!.id));
        ref.invalidate(customerCreditTransactionsProvider(_selectedClient!.id));
      }
      ref.invalidate(fiadoListProvider);
      ref.invalidate(currentCashSessionProvider);
      ref.invalidate(currentCashMovementsProvider);
      ref.invalidate(cashSessionHistoryProvider);
      ref.invalidate(saleHistoryListProvider);
      ref.invalidate(dashboardMetricsProvider);

      if (!context.mounted) {
        return;
      }

      context.goNamed(
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

  void _setSelectedClient(Client? client) {
    setState(() {
      _selectedClient = client;
      if (client == null) {
        _creditAmountController.clear();
        _amountReceivedController.clear();
        _leaveChangeAsCredit = false;
      }
    });
  }

  int _clampCreditUsage(int requested, int saleTotalCents, int availableCents) {
    if (requested <= 0 || saleTotalCents <= 0 || availableCents <= 0) {
      return 0;
    }
    final cappedBySale = requested > saleTotalCents
        ? saleTotalCents
        : requested;
    return cappedBySale > availableCents ? availableCents : cappedBySale;
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
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
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
                style: theme.textTheme.titleSmall?.copyWith(
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
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _CheckoutSummaryMetric extends StatelessWidget {
  const _CheckoutSummaryMetric({
    required this.label,
    required this.value,
    required this.icon,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: emphasize
            ? colorScheme.primaryContainer.withValues(alpha: 0.58)
            : colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 18,
            color: emphasize ? colorScheme.primary : colorScheme.onSurface,
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: emphasize ? colorScheme.primary : null,
            ),
          ),
        ],
      ),
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
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
                  'Haver ${AppFormatters.currencyFromCents(selectedClient!.creditBalanceCents)}',
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
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
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
          padding: const EdgeInsets.all(12),
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
