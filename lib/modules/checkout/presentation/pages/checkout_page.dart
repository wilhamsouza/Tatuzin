import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/errors/app_exceptions.dart';
import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/session/app_session.dart';
import '../../../../app/core/session/session_provider.dart';
import '../../../../app/core/utils/app_logger.dart';
import '../../../../app/core/utils/money_parser.dart';
import '../../../../app/core/widgets/app_bottom_sheet_container.dart';
import '../../../../app/core/widgets/app_input.dart';
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
import '../../../funcionarios/domain/employee_models.dart';
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
    final session = ref.watch(appSessionProvider);
    final checkoutState = ref.watch(checkoutControllerProvider);
    final isSubmitting = checkoutState.isLoading;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    const sectionPadding = EdgeInsets.fromLTRB(14, 14, 14, 14);
    final canManageDiscount = _canManageDiscount(session);
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
            immediateDueCents > 0 &&
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
            tooltip: 'Abrir painel operacional',
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
                  title: 'Desconto',
                  subtitle:
                      'Aplique um abatimento no fechamento mantendo o subtotal original dos itens.',
                  padding: sectionPadding,
                  child: _CheckoutDiscountSection(
                    cart: cart,
                    enabled: !isSubmitting,
                    canManageDiscount: canManageDiscount,
                    onManageDiscount: () => _handleDiscountPressed(context),
                    onRemoveDiscount: cart.hasSaleDiscount
                        ? () => _handleRemoveDiscount(context)
                        : null,
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
                      ? immediateDueCents == 0
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
                                        appliedCreditCents > 0
                                            ? 'Venda coberta integralmente por haver.'
                                            : 'Nenhum recebimento imediato e necessario para concluir esta venda.',
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
                    _paymentMethod == PaymentMethod.cash &&
                    immediateDueCents > 0) ...[
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
                              label: cart.hasSaleDiscount
                                  ? 'Subtotal'
                                  : 'Total',
                              value: AppFormatters.currencyFromCents(
                                cart.hasSaleDiscount
                                    ? cart.subtotalCents
                                    : cart.totalCents,
                              ),
                              icon: Icons.payments_outlined,
                            ),
                          ),
                        ],
                      ),
                      if (cart.hasSaleDiscount) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _CheckoutSummaryMetric(
                                label: 'Desconto',
                                value: AppFormatters.currencyFromCents(
                                  cart.appliedSaleDiscountCents,
                                ),
                                icon: Icons.percent_rounded,
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
                      ],
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
                                letterSpacing: 0,
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
                                  : 'Confirmar Venda - ${AppFormatters.currencyFromCents(cart.totalCents)}',
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
            immediateDueCents > 0 &&
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

    if (saleType == SaleType.cash && immediateDueCents > 0) {
      final currentCashSession = await ref.read(currentCashSessionProvider.future);
      if (currentCashSession == null) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              _paymentMethod == PaymentMethod.cash
                  ? 'Abra o caixa antes de registrar venda em dinheiro.'
                  : 'Abra o caixa antes de concluir uma venda com recebimento imediato.',
            ),
          ),
        );
        return;
      }
    }

    CartItem? unsyncedItem;
    for (final item in cartState.items) {
      if (!item.hasOperationalRemoteIdentity) {
        unsyncedItem = item;
        break;
      }
    }
    if (unsyncedItem != null) {
      AppLogger.warn(
        '[Checkout] blocked sale without remote identity | '
        'productLocalId=${unsyncedItem.productId} '
        'productVariantLocalId=${unsyncedItem.productVariantId}',
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${unsyncedItem.productName}: $operationalProductMissingRemoteMessage',
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
      discountCents: cartState.appliedSaleDiscountCents,
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
      ref.invalidate(pdvCustomerLookupProvider);
      if (_selectedClient != null) {
        ref.invalidate(customerCreditBalanceProvider(_selectedClient!.id));
        ref.invalidate(customerCreditTransactionsProvider(_selectedClient!.id));
      }
      ref.invalidate(fiadoListProvider);
      ref.invalidate(currentCashSessionProvider);
      ref.invalidate(currentCashMovementsProvider);
      ref.invalidate(cashSessionHistoryProvider);
      ref.invalidate(saleHistoryListProvider);
      ref.invalidate(operationalDashboardSnapshotProvider);

      if (!context.mounted) {
        return;
      }

      context.goNamed(
        AppRouteNames.saleReceipt,
        pathParameters: {'saleId': '${sale.saleId}'},
        extra: true,
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      _showMessage(context, _errorMessage(error));
    }
  }

  bool _canManageDiscount(AppSession session) {
    return session.canAccessPermission(EmployeePermission.salesDiscount.key);
  }

  Future<void> _handleDiscountPressed(BuildContext context) async {
    if (!_canManageDiscount(ref.read(appSessionProvider))) {
      _showMessage(context, 'Voce nao tem permissao para aplicar desconto.');
      return;
    }

    final cart = ref.read(cartProvider);
    if (cart.isEmpty) {
      _showMessage(context, 'Carrinho vazio nao permite desconto.');
      return;
    }

    final result = await showModalBottomSheet<_CheckoutDiscountSheetResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CheckoutDiscountSheet(
        subtotalCents: cart.subtotalCents,
        existingDiscount: cart.saleDiscount,
      ),
    );

    if (!context.mounted || result == null) {
      return;
    }

    final cartNotifier = ref.read(cartProvider.notifier);
    if (result.removeDiscount) {
      cartNotifier.removeSaleDiscount();
      _showMessage(context, 'Desconto removido.');
      return;
    }

    final discount = result.discount;
    if (discount == null) {
      return;
    }

    try {
      cartNotifier.applySaleDiscount(discount);
      _showMessage(context, 'Desconto aplicado.');
    } catch (error) {
      _showMessage(context, error.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _handleRemoveDiscount(BuildContext context) {
    if (!_canManageDiscount(ref.read(appSessionProvider))) {
      _showMessage(context, 'Voce nao tem permissao para aplicar desconto.');
      return;
    }

    ref.read(cartProvider.notifier).removeSaleDiscount();
    _showMessage(context, 'Desconto removido.');
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _errorMessage(Object error) {
    if (error is ValidationException || error is StockConflictException) {
      return error.toString().replaceFirst('Exception: ', '');
    }
    return 'Nao foi possivel concluir a venda agora.';
  }

  void _setSelectedClient(Client? client) {
    AppLogger.info(
      "Checkout PDV selected local customer | has_customer=${client != null} | local_id=${client?.id ?? 'none'}",
    );
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
                  pdvCustomerLookupProvider(searchQuery),
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
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('Falha ao buscar clientes: $error'),
                                    const SizedBox(height: 12),
                                    OutlinedButton.icon(
                                      onPressed: () => ref.invalidate(
                                        pdvCustomerLookupProvider(searchQuery),
                                      ),
                                      icon: const Icon(Icons.refresh),
                                      label: const Text('Tentar novamente'),
                                    ),
                                  ],
                                ),
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

class _CheckoutDiscountSection extends StatelessWidget {
  const _CheckoutDiscountSection({
    required this.cart,
    required this.enabled,
    required this.canManageDiscount,
    required this.onManageDiscount,
    required this.onRemoveDiscount,
  });

  final CartState cart;
  final bool enabled;
  final bool canManageDiscount;
  final VoidCallback onManageDiscount;
  final VoidCallback? onRemoveDiscount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasConfiguredDiscount = cart.saleDiscount != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasConfiguredDiscount) ...[
          Text(
            cart.saleDiscount!.isPercent
                ? 'Modo atual: percentual'
                : 'Modo atual: valor em reais',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
        ],
        _CheckoutDiscountSummaryRow(
          label: 'Subtotal',
          value: AppFormatters.currencyFromCents(cart.subtotalCents),
        ),
        const SizedBox(height: 8),
        _CheckoutDiscountSummaryRow(
          label: 'Desconto',
          value: AppFormatters.currencyFromCents(cart.appliedSaleDiscountCents),
        ),
        const SizedBox(height: 8),
        _CheckoutDiscountSummaryRow(
          label: 'Total a pagar',
          value: AppFormatters.currencyFromCents(cart.totalCents),
          emphasize: true,
        ),
        if (cart.saleDiscountNotice != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.tertiaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              cart.saleDiscountNotice!,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: const Key('checkout-discount-manage-button'),
              onPressed: enabled ? onManageDiscount : null,
              icon: Icon(
                hasConfiguredDiscount ? Icons.edit_outlined : Icons.percent,
              ),
              label: Text(
                hasConfiguredDiscount
                    ? 'Editar desconto'
                    : 'Adicionar desconto',
              ),
            ),
            if (onRemoveDiscount != null)
              TextButton.icon(
                key: const Key('checkout-discount-remove-button'),
                onPressed: enabled ? onRemoveDiscount : null,
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Remover desconto'),
              ),
            if (!canManageDiscount)
              Text(
                'Permissao exigida: ${EmployeePermission.salesDiscount.label}.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _CheckoutDiscountSummaryRow extends StatelessWidget {
  const _CheckoutDiscountSummaryRow({
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

    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: emphasize
                  ? colorScheme.onSurface
                  : colorScheme.onSurfaceVariant,
              fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
        Text(
          value,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: emphasize ? colorScheme.primary : null,
          ),
        ),
      ],
    );
  }
}

class _CheckoutDiscountSheetResult {
  const _CheckoutDiscountSheetResult.apply(this.discount)
    : removeDiscount = false;

  const _CheckoutDiscountSheetResult.remove()
    : discount = null,
      removeDiscount = true;

  final CartSaleDiscount? discount;
  final bool removeDiscount;
}

class _CheckoutDiscountSheet extends StatefulWidget {
  const _CheckoutDiscountSheet({
    required this.subtotalCents,
    required this.existingDiscount,
  });

  final int subtotalCents;
  final CartSaleDiscount? existingDiscount;

  @override
  State<_CheckoutDiscountSheet> createState() => _CheckoutDiscountSheetState();
}

class _CheckoutDiscountSheetState extends State<_CheckoutDiscountSheet> {
  late CartSaleDiscountMode _mode;
  late final TextEditingController _valueController;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingDiscount;
    _mode = existing?.mode ?? CartSaleDiscountMode.amount;
    _valueController = TextEditingController(
      text: existing == null
          ? ''
          : existing.isPercent
          ? _formatPercentBasisPoints(existing.percentBasisPoints)
          : AppFormatters.currencyInputFromCents(existing.amountCents),
    );
    _valueController.addListener(_clearErrorOnChange);
  }

  @override
  void dispose() {
    _valueController
      ..removeListener(_clearErrorOnChange)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final previewDiscount = _previewDiscountCents();
    final previewTotal = widget.subtotalCents - previewDiscount;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: AppBottomSheetContainer(
        title: 'Desconto',
        subtitle:
            'Escolha valor em reais ou percentual antes de concluir a venda.',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  key: const Key('checkout-discount-mode-amount'),
                  label: const Text('R\$'),
                  selected: _mode == CartSaleDiscountMode.amount,
                  onSelected: (_) => _switchMode(CartSaleDiscountMode.amount),
                ),
                ChoiceChip(
                  key: const Key('checkout-discount-mode-percent'),
                  label: const Text('%'),
                  selected: _mode == CartSaleDiscountMode.percent,
                  onSelected: (_) => _switchMode(CartSaleDiscountMode.percent),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AppInput(
              key: const Key('checkout-discount-value-field'),
              controller: _valueController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              labelText: _mode == CartSaleDiscountMode.amount
                  ? 'Valor do desconto'
                  : 'Percentual do desconto',
              hintText: _mode == CartSaleDiscountMode.amount ? '0,00' : '10',
              prefixIcon: Icon(
                _mode == CartSaleDiscountMode.amount
                    ? Icons.attach_money_rounded
                    : Icons.percent_rounded,
              ),
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorText!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 12),
            _CheckoutDiscountSummaryRow(
              label: 'Subtotal',
              value: AppFormatters.currencyFromCents(widget.subtotalCents),
            ),
            const SizedBox(height: 8),
            _CheckoutDiscountSummaryRow(
              label: 'Desconto',
              value: AppFormatters.currencyFromCents(previewDiscount),
            ),
            const SizedBox(height: 8),
            _CheckoutDiscountSummaryRow(
              label: 'Total',
              value: AppFormatters.currencyFromCents(
                previewTotal < 0 ? 0 : previewTotal,
              ),
              emphasize: true,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OverflowBar(
                alignment: MainAxisAlignment.end,
                spacing: 8,
                overflowSpacing: 8,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                  if (widget.existingDiscount != null)
                    TextButton(
                      onPressed: () => Navigator.of(
                        context,
                      ).pop(const _CheckoutDiscountSheetResult.remove()),
                      child: const Text('Remover desconto'),
                    ),
                  FilledButton(
                    key: const Key('checkout-discount-apply-button'),
                    onPressed: _apply,
                    child: const Text('Aplicar desconto'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _switchMode(CartSaleDiscountMode nextMode) {
    if (_mode == nextMode) {
      return;
    }
    setState(() {
      _mode = nextMode;
      _errorText = null;
      _valueController.clear();
    });
  }

  void _clearErrorOnChange() {
    if (_errorText == null) {
      return;
    }
    setState(() {
      _errorText = null;
    });
  }

  int _previewDiscountCents() {
    final discount = _buildDiscount(showErrors: false);
    if (discount == null) {
      return 0;
    }
    return discount.resolveAppliedCents(widget.subtotalCents);
  }

  void _apply() {
    final discount = _buildDiscount(showErrors: true);
    if (discount == null) {
      return;
    }
    Navigator.of(context).pop(_CheckoutDiscountSheetResult.apply(discount));
  }

  CartSaleDiscount? _buildDiscount({required bool showErrors}) {
    if (_mode == CartSaleDiscountMode.amount) {
      final amountCents = MoneyParser.parseToCents(_valueController.text);
      if (amountCents < 0) {
        return _reject(showErrors, 'O desconto nao pode ser negativo.');
      }
      if (amountCents > widget.subtotalCents) {
        return _reject(
          showErrors,
          'O desconto nao pode ser maior que o subtotal.',
        );
      }
      return CartSaleDiscount.amount(amountCents: amountCents);
    }

    final percentBasisPoints = _parsePercentBasisPoints(_valueController.text);
    if (percentBasisPoints == null) {
      return _reject(showErrors, 'Informe um percentual valido.');
    }
    if (percentBasisPoints < 0 || percentBasisPoints > 10000) {
      return _reject(
        showErrors,
        'O percentual de desconto deve ficar entre 0 e 100.',
      );
    }
    return CartSaleDiscount.percent(percentBasisPoints: percentBasisPoints);
  }

  CartSaleDiscount? _reject(bool showErrors, String message) {
    if (showErrors) {
      setState(() {
        _errorText = message;
      });
    }
    return null;
  }

  int? _parsePercentBasisPoints(String rawValue) {
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) {
      return 0;
    }
    final sanitized = trimmed.replaceAll(RegExp(r'[^0-9,.-]'), '');
    final normalized = sanitized.replaceAll(',', '.');
    final value = double.tryParse(normalized);
    if (value == null) {
      return null;
    }
    return (value * 100).round();
  }

  String _formatPercentBasisPoints(int basisPoints) {
    final whole = basisPoints ~/ 100;
    final fraction = basisPoints % 100;
    if (fraction == 0) {
      return '$whole';
    }
    if (fraction % 10 == 0) {
      return '$whole,${fraction ~/ 10}';
    }
    final paddedFraction = fraction.toString().padLeft(2, '0');
    return '$whole,$paddedFraction';
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
