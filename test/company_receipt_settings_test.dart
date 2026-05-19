import 'package:erp_pdv_app/app/core/entitlements/plan_entitlements.dart';
import 'package:erp_pdv_app/app/core/session/app_session.dart';
import 'package:erp_pdv_app/app/core/session/app_user.dart';
import 'package:erp_pdv_app/app/core/session/company_context.dart';
import 'package:erp_pdv_app/app/core/session/session_provider.dart';
import 'package:erp_pdv_app/app/core/theme/app_theme.dart';
import 'package:erp_pdv_app/modules/account/data/company_receipt_settings_repository.dart';
import 'package:erp_pdv_app/modules/account/domain/company_receipt_settings.dart';
import 'package:erp_pdv_app/modules/account/presentation/pages/company_page.dart';
import 'package:erp_pdv_app/modules/account/presentation/providers/company_receipt_settings_providers.dart';
import 'package:erp_pdv_app/modules/comprovantes/data/commercial_receipt_mapper.dart';
import 'package:erp_pdv_app/modules/comprovantes/domain/entities/commercial_receipt.dart';
import 'package:erp_pdv_app/modules/comprovantes/domain/entities/commercial_receipt_detail_line.dart';
import 'package:erp_pdv_app/modules/comprovantes/presentation/widgets/commercial_receipt_view.dart';
import 'package:erp_pdv_app/modules/vendas/domain/entities/sale_detail.dart';
import 'package:erp_pdv_app/modules/vendas/domain/entities/sale_enums.dart';
import 'package:erp_pdv_app/modules/vendas/domain/entities/sale_record.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Empresa e comprovante carrega campos configurados', (
    tester,
  ) async {
    await _pumpCompanyPage(
      tester,
      repository: _FakeCompanyReceiptSettingsRepository(
        snapshot: _snapshot(
          settings: const CompanyReceiptSettings(
            receiptDisplayName: 'Loja do Recibo',
            receiptDocument: '12.345.678/0001-90',
            receiptPhone: '(11) 99999-0000',
            receiptAddress: 'Rua do Caixa, 100',
            receiptFooterMessage: 'Volte sempre.',
          ),
        ),
      ),
    );

    expect(find.text('Loja do Recibo'), findsOneWidget);
    expect(find.text('12.345.678/0001-90'), findsOneWidget);
    expect(find.text('(11) 99999-0000'), findsOneWidget);
    expect(find.text('Rua do Caixa, 100'), findsOneWidget);
    expect(find.text('Volte sempre.'), findsOneWidget);
  });

  testWidgets('OWNER edita e salva dados do comprovante', (tester) async {
    final repository = _FakeCompanyReceiptSettingsRepository(
      snapshot: _snapshot(settings: const CompanyReceiptSettings.defaults()),
    );
    await _pumpCompanyPage(tester, repository: repository);

    await tester.enterText(find.byType(TextField).at(0), 'Mercado Central');
    await tester.enterText(find.byType(TextField).at(1), '12345678000100');
    await tester.enterText(find.byType(TextField).at(2), '(11) 98888-7777');
    await tester.enterText(find.byType(TextField).at(3), 'Av. Principal, 10');
    await tester.enterText(find.byType(TextField).at(4), 'Obrigado!');
    await tester.ensureVisible(find.text('Salvar alterações'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar alterações'));
    await tester.pumpAndSettle();

    expect(repository.savedDraft?.receiptDisplayName, 'Mercado Central');
    expect(repository.savedDraft?.receiptDocument, '12345678000100');
    expect(repository.savedDraft?.receiptPhone, '(11) 98888-7777');
    expect(repository.savedDraft?.receiptAddress, 'Av. Principal, 10');
    expect(repository.savedDraft?.receiptFooterMessage, 'Obrigado!');
  });

  testWidgets('sem permissao mostra mensagem amigavel', (tester) async {
    await _pumpCompanyPage(
      tester,
      session: _session(role: 'OPERATOR'),
      repository: _FakeCompanyReceiptSettingsRepository(
        snapshot: _snapshot(settings: const CompanyReceiptSettings.defaults()),
      ),
    );

    expect(find.text('Sem permissão para editar'), findsOneWidget);
    expect(
      find.text('Somente o dono/administrador pode alterar dados da empresa.'),
      findsOneWidget,
    );
  });

  testWidgets('erro inicial usa cache e bloqueia salvamento', (tester) async {
    final repository = _FakeCompanyReceiptSettingsRepository(
      snapshot: _snapshot(settings: const CompanyReceiptSettings.defaults()),
      fetchError: Exception('falha remota'),
    );

    await _pumpCompanyPage(
      tester,
      session: _session(
        receiptSettings: const CompanyReceiptSettings(
          receiptDisplayName: 'Nome em cache',
          receiptDocument: '123',
          receiptPhone: '9999',
          receiptAddress: 'Rua Cache, 10',
          receiptFooterMessage: 'Cache ativo',
        ),
      ),
      repository: repository,
    );

    expect(find.text('Nome em cache'), findsOneWidget);
    expect(find.text('Cache ativo'), findsOneWidget);

    final saveButtonLabel = find.textContaining('Salvar');
    await tester.ensureVisible(saveButtonLabel);
    await tester.pumpAndSettle();
    await tester.tap(saveButtonLabel);
    await tester.pumpAndSettle();

    expect(repository.savedDraft, isNull);
  });

  testWidgets('preview exibe dados habilitados do comprovante', (tester) async {
    await _pumpCompanyPage(
      tester,
      repository: _FakeCompanyReceiptSettingsRepository(
        snapshot: _snapshot(
          settings: const CompanyReceiptSettings(
            receiptDisplayName: 'Padaria Sol',
            receiptDocument: '11122233344',
            receiptPhone: '(11) 97777-0000',
            receiptAddress: 'Rua do Pao, 50',
            receiptFooterMessage: 'Agradecemos a visita.',
          ),
        ),
      ),
    );

    await tester.ensureVisible(find.text('Pré-visualizar comprovante'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pré-visualizar comprovante'));
    await tester.pumpAndSettle();

    expect(find.text('Padaria Sol'), findsWidgets);
    expect(find.textContaining('CPF/CNPJ: 11122233344'), findsOneWidget);
    expect(
      find.textContaining('Telefone/WhatsApp: (11) 97777-0000'),
      findsOneWidget,
    );
    expect(find.textContaining('Endereço: Rua do Pao, 50'), findsOneWidget);
    expect(find.text('Agradecemos a visita.'), findsWidgets);
  });

  test(
    'comprovante real usa receiptDisplayName e oculta campos desligados',
    () {
      final receipt = CommercialReceiptMapper.fromSaleDetail(
        _saleDetail(type: SaleType.cash),
        businessName: 'Empresa da Sessao',
        receiptSettings: const CompanyReceiptSettings(
          receiptDisplayName: 'Nome do Comprovante',
          receiptDocument: '123',
          receiptPhone: '9999',
          receiptAddress: 'Rua A',
          receiptFooterMessage: 'Rodape proprio',
          showDocumentOnReceipt: false,
          showPhoneOnReceipt: true,
          showAddressOnReceipt: false,
          showFooterMessageOnReceipt: true,
        ),
      );

      expect(receipt.businessName, 'Nome do Comprovante');
      expect(receipt.businessDetails.map((detail) => detail.label), [
        'Telefone/WhatsApp',
      ]);
      expect(receipt.footerMessage, 'Rodape proprio');
    },
  );

  test('comprovante real usa fallback e nao mostra campos vazios', () {
    final receipt = CommercialReceiptMapper.fromSaleDetail(
      _saleDetail(type: SaleType.cash),
      businessName: 'Empresa da Sessao',
      receiptSettings: const CompanyReceiptSettings(
        receiptDisplayName: '',
        receiptDocument: '',
        receiptPhone: null,
        receiptAddress: ' ',
        receiptFooterMessage: '',
      ),
    );

    expect(receipt.businessName, 'Empresa da Sessao');
    expect(receipt.businessDetails, isEmpty);
    expect(receipt.footerMessage, contains('dados persistidos do ERP'));
  });

  testWidgets('tipos de comprovante continuam renderizando', (tester) async {
    final receipts = <CommercialReceipt>[
      CommercialReceiptMapper.fromSaleDetail(_saleDetail(type: SaleType.cash)),
      CommercialReceiptMapper.fromSaleDetail(_saleDetail(type: SaleType.fiado)),
      _basicReceipt(CommercialReceiptType.fiadoPayment),
      _basicReceipt(CommercialReceiptType.customerCredit),
    ];

    for (final receipt in receipts) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: CommercialReceiptView(receipt: receipt),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(receipt.title), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}

Future<void> _pumpCompanyPage(
  WidgetTester tester, {
  AppSession? session,
  required _FakeCompanyReceiptSettingsRepository repository,
}) async {
  final effectiveSession = session ?? _session();
  final container = ProviderContainer(
    overrides: [
      companyReceiptSettingsRepositoryProvider.overrideWithValue(repository),
    ],
  );
  addTearDown(container.dispose);
  container
      .read(appSessionProvider.notifier)
      .setAuthenticatedSession(
        scope: effectiveSession.scope,
        user: effectiveSession.user,
        company: effectiveSession.company,
        clientInstanceId: effectiveSession.clientInstanceId,
        membership: effectiveSession.membership,
        employee: effectiveSession.employee,
      );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.light(), home: const CompanyPage()),
    ),
  );
  await tester.pumpAndSettle();
}

AppSession _session({
  String role = 'OWNER',
  CompanyReceiptSettings receiptSettings =
      const CompanyReceiptSettings.defaults(),
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
    company: const CompanyContext(
      localId: null,
      remoteId: 'company-1',
      displayName: 'Cafe Oliveira',
      legalName: 'Cafe Oliveira LTDA',
      documentNumber: '123',
      licensePlan: 'pro',
      licenseStatus: 'active',
      syncEnabled: true,
      entitlements: PlanEntitlements.pro,
    ).copyWith(receiptSettings: receiptSettings),
    membership: AppMembershipContext(role: role, permissions: const <String>{}),
    startedAt: DateTime(2026, 5, 18, 10),
    isOfflineFallback: false,
    clientInstanceId: 'device-1',
  );
}

CompanyReceiptSettingsSnapshot _snapshot({
  required CompanyReceiptSettings settings,
}) {
  return CompanyReceiptSettingsSnapshot(
    companyId: 'company-1',
    displayName: 'Cafe Oliveira',
    legalName: 'Cafe Oliveira LTDA',
    documentNumber: '123',
    settings: settings,
  );
}

SaleDetail _saleDetail({required SaleType type}) {
  return SaleDetail(
    sale: SaleRecord(
      id: 1,
      uuid: 'sale-1',
      receiptNumber: 'R-001',
      saleType: type,
      paymentMethod: type == SaleType.fiado
          ? PaymentMethod.fiado
          : PaymentMethod.cash,
      operationalOrderId: null,
      status: SaleStatus.active,
      totalCents: 1200,
      finalCents: 1200,
      discountCents: 0,
      surchargeCents: 0,
      creditUsedCents: 0,
      creditGeneratedCents: 0,
      immediateReceivedCents: type == SaleType.fiado ? 0 : 1200,
      soldAt: DateTime(2026, 5, 18, 10),
      clientId: null,
      clientName: null,
      notes: null,
      cancelledAt: null,
      fiadoId: type == SaleType.fiado ? 1 : null,
      fiadoStatus: type == SaleType.fiado ? 'pendente' : null,
      fiadoOpenCents: type == SaleType.fiado ? 1200 : null,
      fiadoDueDate: type == SaleType.fiado ? DateTime(2026, 5, 30) : null,
    ),
    items: const [],
  );
}

CommercialReceipt _basicReceipt(CommercialReceiptType type) {
  return CommercialReceipt(
    type: type,
    identifier: 'R-002',
    issuedAt: DateTime(2026, 5, 18, 10),
    businessName: 'Cafe Oliveira',
    title: type.title,
    statusLabel: 'Ativo',
    operationDetails: const [
      CommercialReceiptDetailLine(label: 'Cupom', value: 'R-002'),
    ],
    items: const [],
    extraDetails: const [],
    subtotalCents: 1200,
    discountCents: 0,
    surchargeCents: 0,
    totalCents: 1200,
    subtotalLabel: 'Subtotal',
    totalLabel: 'Total',
    footerMessage: 'Documento de teste.',
  );
}

class _FakeCompanyReceiptSettingsRepository
    implements CompanyReceiptSettingsRepository {
  _FakeCompanyReceiptSettingsRepository({
    required this.snapshot,
    this.fetchError,
  });

  CompanyReceiptSettingsSnapshot snapshot;
  final Object? fetchError;
  CompanyReceiptSettingsDraft? savedDraft;

  @override
  Future<CompanyReceiptSettingsSnapshot> fetch() async {
    final error = fetchError;
    if (error != null) {
      throw error;
    }
    return snapshot;
  }

  @override
  Future<CompanyReceiptSettingsSnapshot> save(
    CompanyReceiptSettingsDraft draft,
  ) async {
    savedDraft = draft;
    snapshot = CompanyReceiptSettingsSnapshot(
      companyId: snapshot.companyId,
      displayName: snapshot.displayName,
      legalName: snapshot.legalName,
      documentNumber: snapshot.documentNumber,
      settings: CompanyReceiptSettings(
        receiptDisplayName: draft.receiptDisplayName,
        receiptDocument: draft.receiptDocument,
        receiptPhone: draft.receiptPhone,
        receiptAddress: draft.receiptAddress,
        receiptFooterMessage: draft.receiptFooterMessage,
        showDocumentOnReceipt: draft.showDocumentOnReceipt,
        showPhoneOnReceipt: draft.showPhoneOnReceipt,
        showAddressOnReceipt: draft.showAddressOnReceipt,
        showFooterMessageOnReceipt: draft.showFooterMessageOnReceipt,
      ),
    );
    return snapshot;
  }
}
