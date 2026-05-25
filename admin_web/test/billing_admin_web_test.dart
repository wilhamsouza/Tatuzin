import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/testing.dart';
import 'package:tatuzin_admin_web/src/core/auth/admin_auth_storage.dart';
import 'package:tatuzin_admin_web/src/core/auth/admin_debug_log.dart';
import 'package:tatuzin_admin_web/src/core/auth/admin_providers.dart';
import 'package:tatuzin_admin_web/src/core/models/admin_billing_models.dart';
import 'package:tatuzin_admin_web/src/core/models/admin_models.dart';
import 'package:tatuzin_admin_web/src/core/network/admin_api_client.dart';
import 'package:tatuzin_admin_web/src/core/network/admin_api_service.dart';
import 'package:tatuzin_admin_web/src/features/billing/presentation/billing_admin_page.dart';
import 'package:tatuzin_admin_web/src/features/billing/presentation/billing_company_detail_page.dart';
import 'package:tatuzin_admin_web/src/features/licenses/presentation/licenses_page.dart';

void main() {
  test('sanitiza payloads defensivamente e mascara URLs de checkout', () {
    final sanitized = sanitizeAdminBillingValue({
      'Authorization': 'Bearer very-secret-token',
      'access_token': 'mp-access-token',
      'x-signature': 'signature',
      'checkoutUrl':
          'https://www.mercadopago.com.br/checkout/v1/redirect?token=abc',
      'init_point': 'https://www.mercadopago.com/init?token=abc',
      'sandbox_init_point': 'https://sandbox.mercadopago.com/init?token=def',
      'nested': [
        {'card_number': '4111111111111111', 'status': 'ok'},
      ],
    });

    final rendered = formatSanitizedAdminJson(sanitized);
    expect(rendered, contains('[redacted]'));
    expect(rendered, isNot(contains('very-secret-token')));
    expect(rendered, isNot(contains('mp-access-token')));
    expect(rendered, isNot(contains('4111111111111111')));
    expect(rendered, isNot(contains('token=abc')));
    expect(rendered, isNot(contains('token=def')));
  });

  test('logs nao exibem preview de token', () {
    expect(summarizeToken('abcdef1234567890'), 'present');
    expect(summarizeToken(''), 'empty');
  });

  test('router nao registra rota owner', () {
    final routerSource = File(
      'lib/src/app/admin_web_router.dart',
    ).readAsStringSync();
    expect(routerSource, isNot(contains("path: '/owner'")));
    expect(routerSource, isNot(contains('path: "/owner"')));
  });

  test('AdminApiService bloqueia actions billing sem reason antes da rede', () {
    final service = _FakeAdminApiService();

    expect(
      () => service.refreshBillingCompany(companyId: 'company-1', reason: ''),
      throwsA(isA<AdminApiException>()),
    );
    expect(
      () => service.forceBillingPlan(
        companyId: 'company-1',
        plan: 'PRO',
        reason: ' ',
      ),
      throwsA(isA<AdminApiException>()),
    );
    expect(
      () => service.cancelBillingLocal(
        companyId: 'company-1',
        reason: '',
        effective: 'period_end',
      ),
      throwsA(isA<AdminApiException>()),
    );
    expect(
      () => service.dryRunLicenseEmergencyExtension(
        companyId: 'company-1',
        days: 3,
        reason: ' ',
      ),
      throwsA(isA<AdminApiException>()),
    );
    expect(
      () => service.applyLicenseEmergencyExtension(
        companyId: 'company-1',
        days: 3,
        reason: '',
        confirmationText: 'ESTENDER',
      ),
      throwsA(isA<AdminApiException>()),
    );
    expect(
      () => service.dryRunLicenseSuspend(companyId: 'company-1', reason: ''),
      throwsA(isA<AdminApiException>()),
    );
    expect(
      () => service.applyLicenseSuspend(
        companyId: 'company-1',
        reason: ' ',
        confirmationText: 'SUSPENDER',
      ),
      throwsA(isA<AdminApiException>()),
    );
    expect(
      () => service.dryRunLicenseReactivate(companyId: 'company-1', reason: ''),
      throwsA(isA<AdminApiException>()),
    );
    expect(
      () => service.applyLicenseReactivate(
        companyId: 'company-1',
        reason: ' ',
        confirmationText: 'REATIVAR',
      ),
      throwsA(isA<AdminApiException>()),
    );
    expect(
      () => service.dryRunBillingReconcile(companyId: 'company-1', reason: ' '),
      throwsA(isA<AdminApiException>()),
    );
    expect(
      () => service.applyBillingReconcile(
        companyId: 'company-1',
        reason: '',
        confirmationText: 'RECONCILIAR',
      ),
      throwsA(isA<AdminApiException>()),
    );
  });

  testWidgets('Billing Admin lista empresas com provider mascarado', (
    tester,
  ) async {
    _setLargeViewport(tester);
    await tester.pumpWidget(
      _adminTestApp(
        service: _FakeAdminApiService(),
        child: const BillingAdminPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Billing avancado'), findsOneWidget);
    expect(find.textContaining('Console avancado de billing'), findsOneWidget);
    expect(find.text('Ir para Licencas read-only'), findsOneWidget);
    expect(find.text('Loja Moda Sul'), findsOneWidget);
    expect(find.text('pre_..._7890'), findsOneWidget);
    expect(find.textContaining('preapproval-secret-full-id'), findsNothing);
  });

  testWidgets('Billing Admin abre detalhe ao clicar na empresa', (
    tester,
  ) async {
    _setLargeViewport(tester);
    final service = _FakeAdminApiService();
    await tester.pumpWidget(
      _adminRouterTestApp(service: service, initialLocation: '/billing'),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Loja Moda Sul').first);
    await tester.pumpAndSettle();

    expect(find.text('Billing de Loja Moda Sul'), findsOneWidget);
    expect(service.statusFetchCount, greaterThanOrEqualTo(1));
  });

  testWidgets('Billing Admin renderiza detalhe acessado por deep link', (
    tester,
  ) async {
    _setLargeViewport(tester);
    await tester.pumpWidget(
      _adminRouterTestApp(
        service: _FakeAdminApiService(),
        initialLocation: '/billing/company-1',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Billing de Loja Moda Sul'), findsOneWidget);
    expect(
      find.textContaining('Area avancada. Acoes nesta tela podem alterar'),
      findsOneWidget,
    );
    expect(find.text('Dashboard Plataforma'), findsNothing);
  });

  testWidgets('Billing detalhe sanitiza eventos e exige reason no cancel-local', (
    tester,
  ) async {
    _setLargeViewport(tester);
    await tester.pumpWidget(
      _adminTestApp(
        service: _FakeAdminApiService(),
        child: const BillingCompanyDetailPage(companyId: 'company-1'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dado interno de plataforma'), findsOneWidget);
    expect(find.text('Consultar Licencas read-only'), findsOneWidget);
    expect(find.text('pre_..._7890'), findsWidgets);
    expect(find.textContaining('preapproval-secret-full-id'), findsNothing);

    await tester.tap(find.textContaining('payment.created'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Bearer secret'), findsNothing);
    expect(find.textContaining('token=abc'), findsNothing);
    expect(find.textContaining('[redacted]'), findsWidgets);

    await tester.tap(find.text('Cancel-local'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Esta ação não cancela Mercado Pago. Ela aplica apenas correção local administrativa.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(find.text('Informe um motivo.'), findsOneWidget);
  });

  testWidgets('Billing refresh exige reason', (tester) async {
    _setLargeViewport(tester);
    await tester.pumpWidget(
      _adminTestApp(
        service: _FakeAdminApiService(),
        child: const BillingCompanyDetailPage(companyId: 'company-1'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    expect(find.text('Informe um motivo.'), findsOneWidget);
  });

  testWidgets('Billing force-plan exige reason', (tester) async {
    _setLargeViewport(tester);
    await tester.pumpWidget(
      _adminTestApp(
        service: _FakeAdminApiService(),
        child: const BillingCompanyDetailPage(companyId: 'company-1'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Force-plan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    expect(find.text('Informe um motivo.'), findsOneWidget);
  });

  testWidgets('Billing force-plan permite PRO e recarrega detalhe', (
    tester,
  ) async {
    _setLargeViewport(tester);
    final service = _FakeAdminApiService();
    await tester.pumpWidget(
      _adminTestApp(
        service: service,
        child: const BillingCompanyDetailPage(companyId: 'company-1'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Force-plan'));
    await tester.pumpAndSettle();
    expect(find.text('PRO'), findsWidgets);
    await tester.enterText(find.byType(TextField).last, 'ajuste suporte PRO');
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aplicar force-plan'));
    await tester.pumpAndSettle();

    expect(service.forcePlanCalls, 1);
    expect(service.lastForcePlan, 'PRO');
    expect(service.lastForcePlanStatus, 'ACTIVE');
    expect(service.lastForcePlanReason, 'ajuste suporte PRO');
    expect(service.statusFetchCount, greaterThanOrEqualTo(2));
  });

  testWidgets('/licenses mostra modo read-only e continua acessivel', (
    tester,
  ) async {
    _setLargeViewport(tester);
    await tester.pumpWidget(
      _adminTestApp(
        service: _FakeAdminApiService(),
        child: const LicensesPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Licencas read-only'), findsOneWidget);
    expect(find.textContaining('Modo seguro/read-only'), findsOneWidget);
  });

  testWidgets('/licenses/:companyId linka para billing avancado', (
    tester,
  ) async {
    _setLargeViewport(tester);
    await tester.pumpWidget(
      _adminRouterTestApp(
        service: _FakeAdminApiService(),
        initialLocation: '/licenses/company-1',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Abrir billing avancado'), findsOneWidget);
    expect(
      find.textContaining('Use apenas para suporte operacional'),
      findsOneWidget,
    );

    await tester.tap(find.text('Abrir billing avancado'));
    await tester.pumpAndSettle();

    expect(find.text('Billing de Loja Moda Sul'), findsOneWidget);
    expect(
      find.textContaining('Area avancada. Acoes nesta tela podem alterar'),
      findsOneWidget,
    );
  });

  testWidgets(
    'Extensao emergencial exige motivo e dias validos antes do dry-run',
    (tester) async {
      _setLargeViewport(tester);
      final service = _FakeAdminApiService();
      await tester.pumpWidget(
        _adminRouterTestApp(
          service: service,
          initialLocation: '/licenses/company-1',
        ),
      );
      await tester.pumpAndSettle();

      await _openExtensionDialog(tester);
      await tester.tap(find.text('Simular dry-run'));
      await tester.pumpAndSettle();

      expect(
        find.text('Informe o motivo da acao administrativa.'),
        findsOneWidget,
      );
      expect(service.extensionDryRunCalls, 0);

      await tester.enterText(find.byType(TextField).at(0), '30');
      await tester.enterText(
        find.byType(TextField).at(1),
        'Suporte emergencial',
      );
      await tester.tap(find.text('Simular dry-run'));
      await tester.pumpAndSettle();

      expect(find.text('Informe dias entre 1 e 7.'), findsOneWidget);
      expect(service.extensionDryRunCalls, 0);
    },
  );

  testWidgets('Extensao emergencial usa dry-run e confirmacao ESTENDER', (
    tester,
  ) async {
    _setLargeViewport(tester);
    final service = _FakeAdminApiService();
    await tester.pumpWidget(
      _adminRouterTestApp(
        service: service,
        initialLocation: '/licenses/company-1',
      ),
    );
    await tester.pumpAndSettle();

    await _openExtensionDialog(tester);
    await tester.enterText(find.byType(TextField).at(1), 'Cliente em plantao');
    await tester.tap(find.text('Simular dry-run'));
    await tester.pumpAndSettle();

    expect(service.extensionDryRunCalls, 1);
    expect(service.extensionApplyCalls, 0);
    expect(find.text('Confirmacao exigida: ESTENDER'), findsOneWidget);
    expect(find.textContaining('Plano: BASIC -> BASIC'), findsOneWidget);
    expect(find.textContaining('PendingPlan: PRO -> PRO'), findsOneWidget);
    expect(find.textContaining('preapproval-secret-full-id'), findsNothing);

    await tester.enterText(find.byType(TextField).last, 'ERRADO');
    await tester.pumpAndSettle();
    expect(
      find.text('Digite ESTENDER para liberar a confirmacao.'),
      findsOneWidget,
    );
    final disabledConfirm = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Confirmar extensao'),
    );
    expect(disabledConfirm.onPressed, isNull);

    await tester.enterText(find.byType(TextField).last, 'ESTENDER');
    await tester.pumpAndSettle();
    final enabledConfirm = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Confirmar extensao'),
    );
    expect(enabledConfirm.onPressed, isNotNull);
    await tester.tap(find.text('Confirmar extensao'));
    await tester.pumpAndSettle();

    expect(service.extensionApplyCalls, 1);
    expect(service.statusFetchCount, greaterThanOrEqualTo(2));
    expect(find.text('Extensao emergencial aplicada.'), findsOneWidget);
  });

  testWidgets('Extensao emergencial bloqueada mostra blockers e nao executa', (
    tester,
  ) async {
    _setLargeViewport(tester);
    final service = _FakeAdminApiService(blockExtension: true);
    await tester.pumpWidget(
      _adminRouterTestApp(
        service: service,
        initialLocation: '/licenses/company-1',
      ),
    );
    await tester.pumpAndSettle();

    await _openExtensionDialog(tester);
    await tester.enterText(find.byType(TextField).at(1), 'Cliente em plantao');
    await tester.tap(find.text('Simular dry-run'));
    await tester.pumpAndSettle();

    expect(find.text('Bloqueios:'), findsOneWidget);
    expect(
      find.textContaining('Ja existe extensao emergencial ativa'),
      findsOneWidget,
    );
    final confirm = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Confirmar extensao'),
    );
    expect(confirm.onPressed, isNull);
    expect(service.extensionApplyCalls, 0);
  });

  testWidgets('Suspender licenca usa dry-run e confirmacao SUSPENDER', (
    tester,
  ) async {
    _setLargeViewport(tester);
    final service = _FakeAdminApiService();
    await tester.pumpWidget(
      _adminRouterTestApp(
        service: service,
        initialLocation: '/licenses/company-1',
      ),
    );
    await tester.pumpAndSettle();

    await _openLicenseStatusDialog(tester, 'Suspender licenca');
    await tester.tap(find.text('Simular dry-run'));
    await tester.pumpAndSettle();

    expect(
      find.text('Informe o motivo da acao administrativa.'),
      findsOneWidget,
    );
    expect(service.suspendDryRunCalls, 0);
    expect(service.suspendApplyCalls, 0);

    await tester.enterText(find.byType(TextField).at(0), 'Risco operacional');
    await tester.tap(find.text('Simular dry-run'));
    await tester.pumpAndSettle();

    expect(service.suspendDryRunCalls, 1);
    expect(service.suspendApplyCalls, 0);
    expect(find.text('Confirmacao exigida: SUSPENDER'), findsOneWidget);
    expect(find.textContaining('Status: ACTIVE -> SUSPENDED'), findsOneWidget);
    expect(find.textContaining('Plano: BASIC -> BASIC'), findsOneWidget);
    expect(find.textContaining('PendingPlan: PRO -> PRO'), findsOneWidget);
    expect(find.textContaining('preapproval-secret-full-id'), findsNothing);

    await tester.enterText(find.byType(TextField).last, 'ERRADO');
    await tester.pumpAndSettle();
    expect(
      find.text('Digite SUSPENDER para liberar a confirmacao.'),
      findsOneWidget,
    );
    final disabledConfirm = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Confirmar suspensao'),
    );
    expect(disabledConfirm.onPressed, isNull);

    await tester.enterText(find.byType(TextField).last, 'SUSPENDER');
    await tester.pumpAndSettle();
    final enabledConfirm = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Confirmar suspensao'),
    );
    expect(enabledConfirm.onPressed, isNotNull);
    await tester.tap(find.text('Confirmar suspensao'));
    await tester.pumpAndSettle();

    expect(service.suspendApplyCalls, 1);
    expect(service.statusFetchCount, greaterThanOrEqualTo(2));
    expect(find.text('Licenca suspensa.'), findsOneWidget);
  });

  testWidgets('Reativar licenca bloqueada mostra blockers e nao executa', (
    tester,
  ) async {
    _setLargeViewport(tester);
    final service = _FakeAdminApiService(blockReactivate: true);
    await tester.pumpWidget(
      _adminRouterTestApp(
        service: service,
        initialLocation: '/licenses/company-1',
      ),
    );
    await tester.pumpAndSettle();

    await _openLicenseStatusDialog(tester, 'Reativar licenca');
    await tester.enterText(
      find.byType(TextField).at(0),
      'Cliente regularizado',
    );
    await tester.tap(find.text('Simular dry-run'));
    await tester.pumpAndSettle();

    expect(find.text('Bloqueios:'), findsOneWidget);
    expect(
      find.textContaining('Licenca vencida por expiresAt'),
      findsOneWidget,
    );
    final confirm = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Confirmar reativacao'),
    );
    expect(confirm.onPressed, isNull);
    expect(service.reactivateApplyCalls, 0);
  });

  testWidgets('Reativar licenca usa dry-run e confirmacao REATIVAR', (
    tester,
  ) async {
    _setLargeViewport(tester);
    final service = _FakeAdminApiService();
    await tester.pumpWidget(
      _adminRouterTestApp(
        service: service,
        initialLocation: '/licenses/company-1',
      ),
    );
    await tester.pumpAndSettle();

    await _openLicenseStatusDialog(tester, 'Reativar licenca');
    await tester.enterText(
      find.byType(TextField).at(0),
      'Cliente regularizado',
    );
    await tester.tap(find.text('Simular dry-run'));
    await tester.pumpAndSettle();

    expect(service.reactivateDryRunCalls, 1);
    expect(service.reactivateApplyCalls, 0);
    expect(find.text('Confirmacao exigida: REATIVAR'), findsOneWidget);
    expect(find.textContaining('Status: SUSPENDED -> ACTIVE'), findsOneWidget);
    expect(find.textContaining('Plano: BASIC -> BASIC'), findsOneWidget);
    expect(find.textContaining('PendingPlan: PRO -> PRO'), findsOneWidget);
    expect(find.textContaining('preapproval-secret-full-id'), findsNothing);

    await tester.enterText(find.byType(TextField).last, 'REATIVAR');
    await tester.pumpAndSettle();
    final enabledConfirm = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Confirmar reativacao'),
    );
    expect(enabledConfirm.onPressed, isNotNull);
    await tester.tap(find.text('Confirmar reativacao'));
    await tester.pumpAndSettle();

    expect(service.reactivateApplyCalls, 1);
    expect(service.statusFetchCount, greaterThanOrEqualTo(2));
    expect(find.text('Licenca reativada.'), findsOneWidget);
  });

  testWidgets('Reconciliar billing exige motivo antes do dry-run', (
    tester,
  ) async {
    _setLargeViewport(tester);
    final service = _FakeAdminApiService();
    await tester.pumpWidget(
      _adminRouterTestApp(
        service: service,
        initialLocation: '/licenses/company-1',
      ),
    );
    await tester.pumpAndSettle();

    await _openReconcileDialog(tester);
    await tester.tap(find.text('Simular dry-run'));
    await tester.pumpAndSettle();

    expect(
      find.text('Informe o motivo da acao administrativa.'),
      findsOneWidget,
    );
    expect(service.billingReconcileDryRunCalls, 0);
    expect(service.billingReconcileApplyCalls, 0);
  });

  testWidgets('Reconciliar billing usa dry-run e confirmacao RECONCILIAR', (
    tester,
  ) async {
    _setLargeViewport(tester);
    final service = _FakeAdminApiService();
    await tester.pumpWidget(
      _adminRouterTestApp(
        service: service,
        initialLocation: '/licenses/company-1',
      ),
    );
    await tester.pumpAndSettle();

    await _openReconcileDialog(tester);
    await tester.enterText(find.byType(TextField).at(0), 'Atualizar cobranca');
    await tester.tap(find.text('Simular dry-run'));
    await tester.pumpAndSettle();

    expect(service.billingReconcileDryRunCalls, 1);
    expect(service.billingReconcileApplyCalls, 0);
    expect(find.text('Confirmacao exigida: RECONCILIAR'), findsOneWidget);
    expect(find.text('Plano ativo: BASIC'), findsWidgets);
    expect(find.text('PendingPlan: PRO'), findsWidgets);
    expect(find.text('Assinatura provider: pre_..._7890'), findsOneWidget);
    expect(find.textContaining('preapproval-secret-full-id'), findsNothing);

    await tester.enterText(find.byType(TextField).last, 'ERRADO');
    await tester.pumpAndSettle();
    expect(
      find.text('Digite RECONCILIAR para liberar a confirmacao.'),
      findsOneWidget,
    );
    final disabledConfirm = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Confirmar reconciliacao'),
    );
    expect(disabledConfirm.onPressed, isNull);

    await tester.enterText(find.byType(TextField).last, 'RECONCILIAR');
    await tester.pumpAndSettle();
    final enabledConfirm = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Confirmar reconciliacao'),
    );
    expect(enabledConfirm.onPressed, isNotNull);
    await tester.tap(find.text('Confirmar reconciliacao'));
    await tester.pumpAndSettle();

    expect(service.billingReconcileApplyCalls, 1);
    expect(service.statusFetchCount, greaterThanOrEqualTo(2));
    expect(find.text('Billing reconciliado.'), findsOneWidget);
  });

  testWidgets('Reconciliar billing bloqueado mostra blockers e nao executa', (
    tester,
  ) async {
    _setLargeViewport(tester);
    final service = _FakeAdminApiService(blockReconcile: true);
    await tester.pumpWidget(
      _adminRouterTestApp(
        service: service,
        initialLocation: '/licenses/company-1',
      ),
    );
    await tester.pumpAndSettle();

    await _openReconcileDialog(tester);
    await tester.enterText(find.byType(TextField).at(0), 'Atualizar cobranca');
    await tester.tap(find.text('Simular dry-run'));
    await tester.pumpAndSettle();

    expect(find.text('Bloqueios:'), findsOneWidget);
    expect(
      find.textContaining('Nao ha assinatura provider ou checkout pendente'),
      findsOneWidget,
    );
    final confirm = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Confirmar reconciliacao'),
    );
    expect(confirm.onPressed, isNull);
    expect(service.billingReconcileApplyCalls, 0);
  });
}

void _setLargeViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Future<void> _openExtensionDialog(WidgetTester tester) async {
  final button = find.widgetWithText(FilledButton, 'Extensao emergencial');
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> _openLicenseStatusDialog(
  WidgetTester tester,
  String buttonLabel,
) async {
  final button = find.widgetWithText(OutlinedButton, buttonLabel);
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> _openReconcileDialog(WidgetTester tester) async {
  final button = find.widgetWithText(
    OutlinedButton,
    'Reconciliar Mercado Pago',
  );
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Widget _adminTestApp({
  required AdminApiService service,
  required Widget child,
}) {
  return ProviderScope(
    overrides: [adminApiServiceProvider.overrideWithValue(service)],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

Widget _adminRouterTestApp({
  required AdminApiService service,
  required String initialLocation,
}) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/billing',
        builder: (context, state) => const BillingAdminPage(),
      ),
      GoRoute(
        path: '/billing/:companyId',
        builder: (context, state) => BillingCompanyDetailPage(
          companyId: state.pathParameters['companyId'] ?? '',
        ),
      ),
      GoRoute(
        path: '/licenses',
        builder: (context, state) => const LicensesPage(),
      ),
      GoRoute(
        path: '/licenses/:companyId',
        builder: (context, state) => LicenseCompanyPage(
          companyId: state.pathParameters['companyId'] ?? '',
        ),
      ),
    ],
  );

  return ProviderScope(
    overrides: [adminApiServiceProvider.overrideWithValue(service)],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (context, child) => Scaffold(body: child ?? const SizedBox()),
    ),
  );
}

class _FakeAdminApiService extends AdminApiService {
  _FakeAdminApiService({
    this.blockExtension = false,
    this.blockReconcile = false,
    this.blockReactivate = false,
  }) : super(
         apiClient: AdminApiClient(
           baseUrl: 'https://api.test/api',
           authStorage: AdminAuthStorage(),
           httpClient: MockClient((request) async {
             throw UnimplementedError(request.url.toString());
           }),
         ),
         authStorage: AdminAuthStorage(),
       );

  final bool blockExtension;
  final bool blockReconcile;
  final bool blockReactivate;
  int statusFetchCount = 0;
  int forcePlanCalls = 0;
  int extensionDryRunCalls = 0;
  int extensionApplyCalls = 0;
  int suspendDryRunCalls = 0;
  int suspendApplyCalls = 0;
  int reactivateDryRunCalls = 0;
  int reactivateApplyCalls = 0;
  int billingReconcileDryRunCalls = 0;
  int billingReconcileApplyCalls = 0;
  String? lastForcePlan;
  String? lastForcePlanStatus;
  String? lastForcePlanReason;

  @override
  Future<AdminPaginatedResult<AdminBillingCompanySummary>>
  fetchBillingCompanies({AdminBillingCompaniesQuery? query}) async {
    return AdminPaginatedResult<AdminBillingCompanySummary>(
      items: [
        AdminBillingCompanySummary.fromMap({
          'companyId': 'company-1',
          'companyName': 'Loja Moda Sul',
          'plan': 'PRO',
          'licenseStatus': 'ACTIVE',
          'billingProvider': 'mercadopago',
          'hasProviderSubscription': true,
          'maskedProviderSubscriptionId': 'pre_..._7890',
          'pendingPlan': null,
          'cancelAtPeriodEnd': false,
        }),
      ],
      pagination: const AdminPaginationMeta(
        page: 1,
        pageSize: 20,
        total: 1,
        count: 1,
        hasNext: false,
        hasPrevious: false,
      ),
      filters: const {},
      sort: const AdminSortMeta(by: 'updatedAt', direction: 'desc'),
    );
  }

  @override
  Future<AdminBillingCompanyStatus> fetchBillingCompanyStatus(
    String companyId,
  ) async {
    statusFetchCount += 1;
    return AdminBillingCompanyStatus.fromMap({
      'company': {'id': companyId, 'name': 'Loja Moda Sul'},
      'license': {
        'plan': 'BASIC',
        'status': 'SUSPENDED',
        'pendingPlan': 'PRO',
        'expiresAt': '2026-05-20T00:00:00.000Z',
        'providerSubscriptionId': 'preapproval-secret-full-id',
      },
      'billing': {
        'provider': 'mercadopago',
        'providerSubscriptionId': 'preapproval-secret-full-id',
        'maskedProviderSubscriptionId': 'pre_..._7890',
        'hasProviderSubscription': true,
        'pendingPlan': 'PRO',
      },
      'checkoutSessions': const [],
      'events': const [],
      'invoices': const [],
    });
  }

  @override
  Future<AdminLicenseExtensionDryRun> dryRunLicenseEmergencyExtension({
    required String companyId,
    required int days,
    required String reason,
    String? note,
  }) async {
    if (reason.trim().isEmpty) {
      throw const AdminApiException(
        message: 'Informe o motivo da acao administrativa.',
        code: 'ADMIN_REASON_REQUIRED',
      );
    }
    extensionDryRunCalls += 1;
    return AdminLicenseExtensionDryRun.fromMap({
      'allowed': !blockExtension,
      'expectedConfirmationText': 'ESTENDER',
      'summary': blockExtension
          ? 'Extensao bloqueada.'
          : 'Extensao emergencial de $days dias disponivel.',
      'risks': const ['Nao altera license.plan.', 'Nao altera Mercado Pago.'],
      'blockers': blockExtension
          ? const ['Ja existe extensao emergencial ativa.']
          : const [],
      'maxAllowedDays': 7,
      'allowedDaysRange': const {'min': 1, 'max': 7},
      'currentLicense': const {
        'plan': 'BASIC',
        'status': 'SUSPENDED',
        'pendingPlan': 'PRO',
        'expiresAt': '2026-05-20T00:00:00.000Z',
        'maskedProviderSubscriptionId': 'pre_..._7890',
      },
      'proposedChange': const {
        'planBefore': 'BASIC',
        'planAfter': 'BASIC',
        'pendingPlanBefore': 'PRO',
        'pendingPlanAfter': 'PRO',
        'statusBefore': 'SUSPENDED',
        'statusAfter': 'ACTIVE',
        'expiresAtBefore': '2026-05-20T00:00:00.000Z',
        'expiresAtAfter': '2026-05-28T00:00:00.000Z',
      },
    });
  }

  @override
  Future<AdminLicenseExtensionResult> applyLicenseEmergencyExtension({
    required String companyId,
    required int days,
    required String reason,
    required String confirmationText,
    String? note,
  }) async {
    if (reason.trim().isEmpty) {
      throw const AdminApiException(
        message: 'Informe o motivo da acao administrativa.',
        code: 'ADMIN_REASON_REQUIRED',
      );
    }
    extensionApplyCalls += 1;
    return AdminLicenseExtensionResult.fromMap({
      'success': true,
      'message': 'Extensao emergencial aplicada.',
      'license': const {
        'plan': 'BASIC',
        'status': 'ACTIVE',
        'pendingPlan': 'PRO',
        'expiresAt': '2026-05-28T00:00:00.000Z',
        'maskedProviderSubscriptionId': 'pre_..._7890',
      },
      'proposedChange': const {
        'planBefore': 'BASIC',
        'planAfter': 'BASIC',
        'pendingPlanBefore': 'PRO',
        'pendingPlanAfter': 'PRO',
      },
    });
  }

  @override
  Future<AdminLicenseStatusActionDryRun> dryRunLicenseSuspend({
    required String companyId,
    required String reason,
    String? note,
  }) async {
    if (reason.trim().isEmpty) {
      throw const AdminApiException(
        message: 'Informe o motivo da acao administrativa.',
        code: 'ADMIN_REASON_REQUIRED',
      );
    }
    suspendDryRunCalls += 1;
    return AdminLicenseStatusActionDryRun.fromMap({
      'allowed': true,
      'expectedConfirmationText': 'SUSPENDER',
      'summary': 'Suspender estado administrativo da licenca.',
      'risks': const [
        'A suspensao pode bloquear acesso operacional.',
        'Esta acao nao altera plano nem Mercado Pago.',
      ],
      'blockers': const [],
      'currentLicense': const {
        'plan': 'BASIC',
        'status': 'ACTIVE',
        'pendingPlan': 'PRO',
        'maskedProviderSubscriptionId': 'pre_..._7890',
      },
      'proposedChange': const {
        'statusBefore': 'ACTIVE',
        'statusAfter': 'SUSPENDED',
        'planBefore': 'BASIC',
        'planAfter': 'BASIC',
        'pendingPlanBefore': 'PRO',
        'pendingPlanAfter': 'PRO',
        'currentPeriodEndBefore': '2026-06-20T00:00:00.000Z',
        'currentPeriodEndAfter': '2026-06-20T00:00:00.000Z',
      },
    });
  }

  @override
  Future<AdminLicenseStatusActionResult> applyLicenseSuspend({
    required String companyId,
    required String reason,
    required String confirmationText,
    String? note,
  }) async {
    if (reason.trim().isEmpty) {
      throw const AdminApiException(
        message: 'Informe o motivo da acao administrativa.',
        code: 'ADMIN_REASON_REQUIRED',
      );
    }
    suspendApplyCalls += 1;
    return AdminLicenseStatusActionResult.fromMap({
      'success': true,
      'message': 'Licenca suspensa.',
      'license': const {
        'plan': 'BASIC',
        'status': 'SUSPENDED',
        'pendingPlan': 'PRO',
        'maskedProviderSubscriptionId': 'pre_..._7890',
      },
      'proposedChange': const {
        'statusBefore': 'ACTIVE',
        'statusAfter': 'SUSPENDED',
        'planBefore': 'BASIC',
        'planAfter': 'BASIC',
        'pendingPlanBefore': 'PRO',
        'pendingPlanAfter': 'PRO',
      },
    });
  }

  @override
  Future<AdminLicenseStatusActionDryRun> dryRunLicenseReactivate({
    required String companyId,
    required String reason,
    String? note,
  }) async {
    if (reason.trim().isEmpty) {
      throw const AdminApiException(
        message: 'Informe o motivo da acao administrativa.',
        code: 'ADMIN_REASON_REQUIRED',
      );
    }
    reactivateDryRunCalls += 1;
    return AdminLicenseStatusActionDryRun.fromMap({
      'allowed': !blockReactivate,
      'expectedConfirmationText': 'REATIVAR',
      'summary': blockReactivate
          ? 'Reativacao bloqueada.'
          : 'Reativar estado administrativo da licenca.',
      'risks': const [
        'Reativar restabelece acesso conforme license.plan.',
        'Esta acao nao altera plano nem Mercado Pago.',
      ],
      'blockers': blockReactivate
          ? const [
              'Licenca vencida por expiresAt. Use Extensao emergencial ou Reconciliar billing antes de reativar.',
            ]
          : const [],
      'currentLicense': const {
        'plan': 'BASIC',
        'status': 'SUSPENDED',
        'pendingPlan': 'PRO',
        'maskedProviderSubscriptionId': 'pre_..._7890',
      },
      'proposedChange': const {
        'statusBefore': 'SUSPENDED',
        'statusAfter': 'ACTIVE',
        'planBefore': 'BASIC',
        'planAfter': 'BASIC',
        'pendingPlanBefore': 'PRO',
        'pendingPlanAfter': 'PRO',
        'currentPeriodEndBefore': '2026-06-20T00:00:00.000Z',
        'currentPeriodEndAfter': '2026-06-20T00:00:00.000Z',
      },
    });
  }

  @override
  Future<AdminLicenseStatusActionResult> applyLicenseReactivate({
    required String companyId,
    required String reason,
    required String confirmationText,
    String? note,
  }) async {
    if (reason.trim().isEmpty) {
      throw const AdminApiException(
        message: 'Informe o motivo da acao administrativa.',
        code: 'ADMIN_REASON_REQUIRED',
      );
    }
    reactivateApplyCalls += 1;
    return AdminLicenseStatusActionResult.fromMap({
      'success': true,
      'message': 'Licenca reativada.',
      'license': const {
        'plan': 'BASIC',
        'status': 'ACTIVE',
        'pendingPlan': 'PRO',
        'maskedProviderSubscriptionId': 'pre_..._7890',
      },
      'proposedChange': const {
        'statusBefore': 'SUSPENDED',
        'statusAfter': 'ACTIVE',
        'planBefore': 'BASIC',
        'planAfter': 'BASIC',
        'pendingPlanBefore': 'PRO',
        'pendingPlanAfter': 'PRO',
      },
    });
  }

  @override
  Future<AdminBillingReconcileDryRun> dryRunBillingReconcile({
    required String companyId,
    required String reason,
    String? note,
  }) async {
    if (reason.trim().isEmpty) {
      throw const AdminApiException(
        message: 'Informe o motivo da acao administrativa.',
        code: 'ADMIN_REASON_REQUIRED',
      );
    }
    billingReconcileDryRunCalls += 1;
    return AdminBillingReconcileDryRun.fromMap({
      'allowed': !blockReconcile,
      'expectedConfirmationText': 'RECONCILIAR',
      'summary': blockReconcile
          ? 'Reconciliacao bloqueada.'
          : 'Billing pode ser reconciliado pelo fluxo seguro existente.',
      'risks': const [
        'Nao forca troca manual de plano.',
        'Nao edita providerSubscriptionId manualmente.',
      ],
      'blockers': blockReconcile
          ? const ['Nao ha assinatura provider ou checkout pendente.']
          : const [],
      'currentBillingStatus': const {
        'plan': 'BASIC',
        'status': 'SUSPENDED',
        'pendingPlan': 'PRO',
        'maskedProviderSubscriptionId': 'pre_..._7890',
      },
      'pendingCheckoutSessions': const [
        {
          'id': 'checkout-1',
          'plan': 'PRO',
          'status': 'pending',
          'maskedProviderReference': 'pre_..._7890',
        },
      ],
      'likelyActions': const [
        'Consultar Mercado Pago pelo fluxo seguro existente.',
        'Reconciliar faturas autorizadas.',
      ],
      'providerCheckSummary': const {
        'provider': 'mercadopago',
        'maskedProviderSubscriptionId': 'pre_..._7890',
        'consulted': false,
      },
    });
  }

  @override
  Future<AdminBillingReconcileResult> applyBillingReconcile({
    required String companyId,
    required String reason,
    required String confirmationText,
    String? note,
  }) async {
    if (reason.trim().isEmpty) {
      throw const AdminApiException(
        message: 'Informe o motivo da acao administrativa.',
        code: 'ADMIN_REASON_REQUIRED',
      );
    }
    billingReconcileApplyCalls += 1;
    return AdminBillingReconcileResult.fromMap({
      'success': true,
      'message': 'Billing reconciliado.',
      'updatedStatus': const {
        'plan': 'BASIC',
        'status': 'ACTIVE',
        'pendingPlan': 'PRO',
        'maskedProviderSubscriptionId': 'pre_..._7890',
      },
      'invoicesReconciled': 1,
      'checkoutSessionsUpdated': 1,
      'warnings': const [],
    });
  }

  @override
  Future<AdminPaginatedResult<AdminBillingEvent>> fetchBillingEvents({
    required AdminBillingListQuery query,
  }) async {
    return AdminPaginatedResult<AdminBillingEvent>(
      items: [
        AdminBillingEvent.fromMap({
          'id': 'event-1',
          'provider': 'mercadopago',
          'eventType': 'payment.created',
          'status': 'processed',
          'payload': {
            'Authorization': 'Bearer secret',
            'checkoutUrl':
                'https://www.mercadopago.com.br/checkout/v1/redirect?token=abc',
            'card': {'card_number': '4111111111111111'},
            'public': 'ok',
          },
        }),
      ],
      pagination: const AdminPaginationMeta(
        page: 1,
        pageSize: 10,
        total: 1,
        count: 1,
        hasNext: false,
        hasPrevious: false,
      ),
      filters: const {},
      sort: const AdminSortMeta(by: 'createdAt', direction: 'desc'),
    );
  }

  @override
  Future<AdminPaginatedResult<AdminBillingCheckoutSession>>
  fetchBillingCheckoutSessions({required AdminBillingListQuery query}) async {
    return AdminPaginatedResult<AdminBillingCheckoutSession>(
      items: [
        AdminBillingCheckoutSession.fromMap({
          'id': 'session-1',
          'plan': 'PRO',
          'status': 'created',
          'provider': 'mercadopago',
          'checkoutUrl':
              'https://www.mercadopago.com.br/checkout/v1/redirect?token=abc',
        }),
      ],
      pagination: const AdminPaginationMeta(
        page: 1,
        pageSize: 10,
        total: 1,
        count: 1,
        hasNext: false,
        hasPrevious: false,
      ),
      filters: const {},
      sort: const AdminSortMeta(by: 'createdAt', direction: 'desc'),
    );
  }

  @override
  Future<AdminPaginatedResult<AdminLicenseSnapshot>> fetchLicenses({
    AdminLicensesQuery? query,
  }) async {
    return const AdminPaginatedResult<AdminLicenseSnapshot>(
      items: [],
      pagination: AdminPaginationMeta(
        page: 1,
        pageSize: 20,
        total: 0,
        count: 0,
        hasNext: false,
        hasPrevious: false,
      ),
      filters: {},
      sort: AdminSortMeta(by: 'updatedAt', direction: 'desc'),
    );
  }

  @override
  Future<AdminBillingActionResult> forceBillingPlan({
    required String companyId,
    required String plan,
    required String reason,
    String? status,
    DateTime? currentPeriodEnd,
    bool clearProvider = false,
  }) async {
    if (reason.trim().isEmpty) {
      throw const AdminApiException(
        message: 'Informe o motivo da ação administrativa.',
        code: 'ADMIN_REASON_REQUIRED',
      );
    }
    forcePlanCalls += 1;
    lastForcePlan = plan;
    lastForcePlanStatus = status;
    lastForcePlanReason = reason;
    return AdminBillingActionResult.fromMap({
      'message': 'Force-plan aplicado.',
      'status': {
        'companyId': companyId,
        'plan': plan,
        'status': status ?? 'ACTIVE',
      },
    });
  }
}
