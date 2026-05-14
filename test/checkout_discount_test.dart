import 'package:erp_pdv_app/app/core/entitlements/plan_entitlements.dart';
import 'package:erp_pdv_app/app/core/errors/app_exceptions.dart';
import 'package:erp_pdv_app/app/core/formatters/app_formatters.dart';
import 'package:erp_pdv_app/app/core/session/app_session.dart';
import 'package:erp_pdv_app/app/core/session/app_user.dart';
import 'package:erp_pdv_app/app/core/session/company_context.dart';
import 'package:erp_pdv_app/app/core/session/session_provider.dart';
import 'package:erp_pdv_app/app/core/theme/app_theme.dart';
import 'package:erp_pdv_app/modules/carrinho/domain/entities/cart_item.dart';
import 'package:erp_pdv_app/modules/carrinho/presentation/providers/cart_provider.dart';
import 'package:erp_pdv_app/modules/checkout/presentation/pages/checkout_page.dart';
import 'package:erp_pdv_app/modules/comprovantes/domain/entities/commercial_receipt.dart';
import 'package:erp_pdv_app/modules/comprovantes/domain/entities/commercial_receipt_detail_line.dart';
import 'package:erp_pdv_app/modules/comprovantes/presentation/widgets/commercial_receipt_view.dart';
import 'package:erp_pdv_app/modules/produtos/domain/entities/product.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('OWNER consegue abrir o fluxo de desconto no checkout', (
    tester,
  ) async {
    await _pumpCheckoutPage(tester, session: _session(membershipRole: 'OWNER'));

    await tester.tap(find.byKey(const Key('checkout-discount-manage-button')));
    await tester.pumpAndSettle();

    expect(find.text('Aplicar desconto'), findsOneWidget);
    expect(
      find.byKey(const Key('checkout-discount-value-field')),
      findsOneWidget,
    );
  });

  testWidgets('funcionario com permissao consegue aplicar desconto em reais', (
    tester,
  ) async {
    final container = await _pumpCheckoutPage(
      tester,
      session: _session(
        employee: const AppEmployeeContext(
          id: 'employee-1',
          role: 'CASHIER',
          status: 'ACTIVE',
          permissions: {'sales.discount'},
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('checkout-discount-manage-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('checkout-discount-value-field')),
      '10,00',
    );
    await tester.tap(find.byKey(const Key('checkout-discount-apply-button')));
    await tester.pumpAndSettle();

    expect(find.text('Desconto aplicado.'), findsOneWidget);
    expect(container.read(cartProvider).appliedSaleDiscountCents, 1000);
    expect(container.read(cartProvider).totalCents, 4000);
  });

  testWidgets(
    'funcionario com permissao consegue aplicar desconto percentual',
    (tester) async {
      final container = await _pumpCheckoutPage(
        tester,
        session: _session(
          employee: const AppEmployeeContext(
            id: 'employee-2',
            role: 'SELLER',
            status: 'ACTIVE',
            permissions: {'sales.discount'},
          ),
        ),
        unitPriceCents: 10000,
      );

      await tester.tap(
        find.byKey(const Key('checkout-discount-manage-button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('checkout-discount-mode-percent')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('checkout-discount-value-field')),
        '10',
      );
      await tester.tap(find.byKey(const Key('checkout-discount-apply-button')));
      await tester.pumpAndSettle();

      expect(container.read(cartProvider).appliedSaleDiscountCents, 1000);
      expect(container.read(cartProvider).totalCents, 9000);
    },
  );

  testWidgets('funcionario sem permissao nao consegue aplicar desconto', (
    tester,
  ) async {
    await _pumpCheckoutPage(
      tester,
      session: _session(
        employee: const AppEmployeeContext(
          id: 'employee-3',
          role: 'CASHIER',
          status: 'ACTIVE',
          permissions: {'sales.create'},
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('checkout-discount-manage-button')));
    await tester.pumpAndSettle();

    expect(
      find.text('Voce nao tem permissao para aplicar desconto.'),
      findsOneWidget,
    );
  });

  testWidgets('funcionario DISABLED nao consegue aplicar desconto', (
    tester,
  ) async {
    await _pumpCheckoutPage(
      tester,
      session: _session(
        employee: const AppEmployeeContext(
          id: 'employee-4',
          role: 'CASHIER',
          status: 'DISABLED',
          permissions: {'sales.discount'},
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('checkout-discount-manage-button')));
    await tester.pumpAndSettle();

    expect(
      find.text('Voce nao tem permissao para aplicar desconto.'),
      findsOneWidget,
    );
  });

  test('desconto maior que subtotal e bloqueado no carrinho', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    _setSession(container, _session(membershipRole: 'OWNER'));
    _primeCart(container, unitPriceCents: 5000, quantity: 1);

    expect(
      () => container
          .read(cartProvider.notifier)
          .applySaleDiscount(const CartSaleDiscount.amount(amountCents: 6000)),
      throwsA(
        isA<ValidationException>().having(
          (error) => error.message,
          'message',
          'O desconto nao pode ser maior que o subtotal.',
        ),
      ),
    );
  });

  test('provider bloqueia aplicacao de desconto sem permissao efetiva', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    _setSession(container, _session());
    _primeCart(container, unitPriceCents: 5000, quantity: 1);

    expect(
      () => container
          .read(cartProvider.notifier)
          .applySaleDiscount(const CartSaleDiscount.amount(amountCents: 500)),
      throwsA(
        isA<ValidationException>().having(
          (error) => error.message,
          'message',
          'Voce nao tem permissao para aplicar desconto.',
        ),
      ),
    );
  });

  test('limpar carrinho remove desconto aplicado', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    _setSession(container, _session(membershipRole: 'OWNER'));
    _primeCart(container, unitPriceCents: 5000, quantity: 1);

    container
        .read(cartProvider.notifier)
        .applySaleDiscount(const CartSaleDiscount.amount(amountCents: 500));
    container.read(cartProvider.notifier).clear();

    expect(container.read(cartProvider).saleDiscount, isNull);
    expect(container.read(cartProvider).appliedSaleDiscountCents, 0);
  });

  test('remover item ajusta desconto fixo invalido com aviso', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    _setSession(container, _session(membershipRole: 'OWNER'));
    _primeCart(container, unitPriceCents: 5000, quantity: 2);

    container
        .read(cartProvider.notifier)
        .applySaleDiscount(const CartSaleDiscount.amount(amountCents: 7000));
    final itemId = container.read(cartProvider).items.first.id;
    container.read(cartProvider.notifier).decreaseQuantity(itemId);

    final cart = container.read(cartProvider);
    expect(cart.subtotalCents, 5000);
    expect(cart.appliedSaleDiscountCents, 5000);
    expect(cart.saleDiscountNotice, CartController.discountAdjustedNotice);
  });

  testWidgets('recibo mostra desconto quando aplicado', (tester) async {
    final receipt = CommercialReceipt(
      type: CommercialReceiptType.cashSale,
      identifier: 'R-001',
      issuedAt: DateTime(2026, 5, 13, 10),
      businessName: 'Tatuzin',
      title: 'Comprovante',
      statusLabel: 'Ativa',
      customerName: 'Cliente',
      paymentMethodLabel: 'Dinheiro',
      operationDetails: const [
        CommercialReceiptDetailLine(label: 'Cupom', value: 'R-001'),
      ],
      items: const [],
      extraDetails: const [],
      subtotalCents: 10000,
      discountCents: 1000,
      surchargeCents: 0,
      totalCents: 9000,
      subtotalLabel: 'Subtotal',
      totalLabel: 'Total final',
      notes: null,
      footerMessage: 'Documento de teste.',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: CommercialReceiptView(receipt: receipt),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Desconto'), findsOneWidget);
    expect(find.text(AppFormatters.currencyFromCents(1000)), findsOneWidget);
  });
}

Future<ProviderContainer> _pumpCheckoutPage(
  WidgetTester tester, {
  required AppSession session,
  int unitPriceCents = 5000,
}) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  container
      .read(appSessionProvider.notifier)
      .setAuthenticatedSession(
        scope: session.scope,
        user: session.user,
        company: session.company,
        clientInstanceId: session.clientInstanceId,
        membership: session.membership,
        employee: session.employee,
      );
  _primeCart(container, unitPriceCents: unitPriceCents, quantity: 1);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.light(), home: const CheckoutPage()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void _setSession(ProviderContainer container, AppSession session) {
  container
      .read(appSessionProvider.notifier)
      .setAuthenticatedSession(
        scope: session.scope,
        user: session.user,
        company: session.company,
        clientInstanceId: session.clientInstanceId,
        membership: session.membership,
        employee: session.employee,
      );
}

void _primeCart(
  ProviderContainer container, {
  required int unitPriceCents,
  required int quantity,
}) {
  final notifier = container.read(cartProvider.notifier);
  final product = _product(unitPriceCents: unitPriceCents, stockMil: 1000 * 10);
  for (var index = 0; index < quantity; index++) {
    notifier.addProduct(product);
  }
}

AppSession _session({
  String membershipRole = 'MEMBER',
  AppEmployeeContext? employee,
}) {
  return AppSession(
    scope: SessionScope.authenticatedRemote,
    user: const AppUser(
      localId: null,
      remoteId: 'user-1',
      displayName: 'Operador',
      email: 'operador@tatuzin.test',
      roleLabel: 'Operador',
      kind: AppUserKind.remoteAuthenticated,
    ),
    company: CompanyContext(
      localId: null,
      remoteId: 'company-1',
      displayName: 'Cafe Oliveira',
      legalName: 'Cafe Oliveira LTDA',
      documentNumber: null,
      licensePlan: PlanEntitlements.pro.plan.key,
      licenseStatus: 'active',
      syncEnabled: true,
      entitlements: PlanEntitlements.pro,
    ),
    membership: AppMembershipContext(
      role: membershipRole,
      permissions: const <String>{},
    ),
    employee: employee,
    startedAt: DateTime(2026, 5, 13, 9),
    isOfflineFallback: false,
    clientInstanceId: 'device-1',
  );
}

Product _product({required int unitPriceCents, required int stockMil}) {
  final now = DateTime(2026, 5, 13, 9);
  return Product(
    id: 1,
    uuid: 'product-1',
    name: 'Cafe coado',
    description: null,
    categoryId: null,
    categoryName: null,
    barcode: 'CAFE-001',
    primaryPhotoPath: null,
    productType: 'simples',
    niche: ProductNiches.food,
    catalogType: ProductCatalogTypes.simple,
    modelName: null,
    variantLabel: null,
    baseProductId: null,
    baseProductName: null,
    unitMeasure: 'un',
    costCents: 1000,
    manualCostCents: 1000,
    costSource: ProductCostSource.manual,
    salePriceCents: unitPriceCents,
    stockMil: stockMil,
    isActive: true,
    createdAt: now,
    updatedAt: now,
    deletedAt: null,
    remoteId: '11111111-1111-4111-8111-111111111111',
  );
}
