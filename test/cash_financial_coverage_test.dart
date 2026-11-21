import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tatuzin/app/core/app_context/app_operational_context.dart';
import 'package:tatuzin/app/core/config/app_environment.dart';
import 'package:tatuzin/app/core/database/app_database.dart';
import 'package:tatuzin/app/core/database/table_names.dart';
import 'package:tatuzin/app/core/session/app_session.dart';
import 'package:tatuzin/app/core/session/app_user.dart';
import 'package:tatuzin/app/core/session/company_context.dart';
import 'package:tatuzin/app/core/session/cached_session_storage.dart';
import 'package:tatuzin/modules/account/domain/company_receipt_settings.dart';
import 'package:tatuzin/modules/caixa/data/cash_database_support.dart';
import 'package:tatuzin/modules/caixa/data/cash_workspace_store.dart';
import 'package:tatuzin/modules/fiado/data/sqlite_fiado_repository.dart';
import 'package:tatuzin/modules/fiado/domain/entities/fiado_payment_input.dart';
import 'package:tatuzin/modules/vendas/data/support/sale_cash_effects_support.dart';
import 'package:tatuzin/modules/vendas/domain/entities/sale_enums.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tatuzin/modules/compras/data/support/purchase_payment_writer.dart';
import 'package:tatuzin/modules/custos/data/sqlite_cost_repository.dart';
import 'package:tatuzin/modules/custos/domain/repositories/cost_repository.dart';
import 'support/sale_inventory_test_support.dart' show createSaleRepository;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late AppDatabase app;
  late Database db;
  late String isolation;
  late int sessionId;
  final now = DateTime(2026, 11, 20, 10);
  final context = AppOperationalContext(
    environment: const AppEnvironment.localDefault(),
    session: AppSession.localDefault(),
  );

  setUp(() async {
    isolation = 'cash-financial-${DateTime.now().microsecondsSinceEpoch}';
    app = AppDatabase.forIsolationKey(isolation);
    db = await app.database;
    sessionId = await CashDatabaseSupport.ensureOpenSession(db, timestamp: now);
  });
  tearDown(() async {
    await app.close();
    await AppDatabase.deleteDatabaseForIsolationKeyForTesting(isolation);
  });

  Future<Map<String, Object?>> balance() async => (await db.query(
    TableNames.caixaSessoes,
    where: 'id = ?',
    whereArgs: [sessionId],
  )).single;

  test(
    'ledger com dinheiro, Pix e cartão conserva centavos e estornos por meio',
    () async {
      for (final tender in {
        PaymentMethod.cash: 101,
        PaymentMethod.pix: 202,
        PaymentMethod.card: 303,
      }.entries) {
        await SaleCashEffectsSupport.registerCashSaleReceipt(
          db,
          timestamp: now,
          userId: null,
          saleId: 7,
          amountCents: tender.value,
          receiptNumber: 'MISTO',
          paymentMethod: tender.key,
        );
      }
      expect((await balance())['saldo_esperado_centavos'], 101);
      await SaleCashEffectsSupport.registerSaleCancellation(
        db,
        timestamp: now,
        userId: null,
        saleId: 7,
        amountCents: 202,
        receiptNumber: 'MISTO',
        reason: 'Estorno Pix',
        paymentMethod: PaymentMethod.pix,
      );
      await SaleCashEffectsSupport.registerSaleReturnRefund(
        db,
        timestamp: now,
        userId: null,
        saleId: 7,
        amountCents: 1,
        receiptNumber: 'MISTO',
        reason: 'Devolução parcial',
        paymentMethod: PaymentMethod.cash,
      );
      expect((await balance())['saldo_esperado_centavos'], 100);
      await CashSessionMathSupport.rebuildSessionTotals(
        db,
        sessionId: sessionId,
      );
      expect((await balance())['saldo_esperado_centavos'], 100);
    },
  );

  test(
    'recebimentos parciais de fiado por três meios e cancelamento não retiram Pix do numerário',
    () async {
      final iso = now.toIso8601String();
      final customer = await db.insert(TableNames.clientes, {
        'uuid': 'cash-customer',
        'nome': 'Cliente de teste',
        'saldo_devedor_centavos': 1001,
        'criado_em': iso,
        'atualizado_em': iso,
      });
      final sale = await db.insert(TableNames.vendas, {
        'uuid': 'cash-credit-sale',
        'cliente_id': customer,
        'tipo_venda': 'fiado',
        'forma_pagamento': 'fiado',
        'status': 'ativa',
        'valor_total_centavos': 1001,
        'desconto_centavos': 0,
        'acrescimo_centavos': 0,
        'valor_final_centavos': 1001,
        'numero_cupom': 'FIADO-CENTS',
        'data_venda': iso,
      });
      final fiado = await db.insert(TableNames.fiado, {
        'uuid': 'cash-credit-note',
        'venda_id': sale,
        'cliente_id': customer,
        'valor_original_centavos': 1001,
        'valor_aberto_centavos': 1001,
        'vencimento': iso,
        'status': 'pendente',
        'criado_em': iso,
        'atualizado_em': iso,
      });
      final repository = SqliteFiadoRepository(app, context);
      for (final tender in {
        PaymentMethod.cash: 101,
        PaymentMethod.pix: 203,
        PaymentMethod.card: 307,
      }.entries) {
        await repository.registerPayment(
          FiadoPaymentInput(
            fiadoId: fiado,
            amountCents: tender.value,
            paymentMethod: tender.key,
          ),
        );
      }
      final detail = await repository.fetchDetail(fiado);
      expect(detail.account.openCents, 390);
      expect((await balance())['saldo_esperado_centavos'], 101);
      expect((await balance())['total_recebimentos_fiado_centavos'], 611);
      await createSaleRepository(
        db,
      ).cancelSale(saleId: sale, reason: 'Cancelamento com três meios');
      final after = await balance();
      expect(after['saldo_esperado_centavos'], 0);
      expect(after['total_recebimentos_fiado_centavos'], 0);
      expect(after['total_recebimentos_fiado_pix_centavos'], 0);
      expect(after['total_recebimentos_fiado_cartao_centavos'], 0);
      await CashSessionMathSupport.rebuildSessionTotals(
        db,
        sessionId: sessionId,
      );
      expect((await balance())['saldo_esperado_centavos'], 0);
      expect(
        (await db.query(
          TableNames.clientes,
          where: 'id = ?',
          whereArgs: [customer],
        )).single['saldo_devedor_centavos'],
        0,
      );
    },
  );

  test(
    'compras e custos multimeio só retiram dinheiro físico nos pagamentos em dinheiro',
    () async {
      final iso = now.toIso8601String();
      final supplier = await db.insert(TableNames.fornecedores, {
        'uuid': 'cash-supplier',
        'nome': 'Fornecedor teste',
        'criado_em': iso,
        'atualizado_em': iso,
      });
      final purchase = await db.insert(TableNames.compras, {
        'uuid': 'cash-purchase',
        'fornecedor_id': supplier,
        'data_compra': iso,
        'status': 'recebida',
        'subtotal_centavos': 606,
        'valor_final_centavos': 606,
        'valor_pendente_centavos': 606,
        'criado_em': iso,
        'atualizado_em': iso,
      });
      for (final tender in {
        PaymentMethod.cash: 101,
        PaymentMethod.pix: 202,
        PaymentMethod.card: 303,
      }.entries) {
        await db.transaction(
          (txn) => PurchasePaymentWriter.insertPayment(
            txn,
            purchaseId: purchase,
            currentLocalUserId: null,
            supplierName: 'Fornecedor teste',
            amountCents: tender.value,
            paymentMethod: tender.key,
            registeredAt: now,
            notes: null,
          ),
        );
      }
      expect((await balance())['saldo_esperado_centavos'], -101);
      final authorized = AppOperationalContext(
        environment: const AppEnvironment.localDefault(),
        session: AppSession.localDefault().copyWith(
          scope: SessionScope.authenticatedRemote,
          user: const AppUser(
            localId: null,
            remoteId: 'cash-owner',
            displayName: 'Dono teste',
            email: 'owner@test.invalid',
            roleLabel: 'Dono',
            kind: AppUserKind.remoteAuthenticated,
          ),
          company: const CompanyContext(
            localId: null,
            remoteId: 'cash-company',
            displayName: 'Empresa teste',
            legalName: 'Empresa teste',
            documentNumber: null,
          ),
          clientInstanceId: 'cash-test-device',
          membership: const AppMembershipContext(
            role: 'OWNER',
            permissions: {'cash.open', 'cash.close'},
          ),
        ),
      );
      final costs = SqliteCostRepository(app, authorized);
      for (final tender in {
        PaymentMethod.cash: 107,
        PaymentMethod.pix: 207,
        PaymentMethod.card: 307,
      }.entries) {
        final cost = await db.insert(TableNames.custos, {
          'uuid': 'cash-cost-${tender.key.name}',
          'descricao': 'Custo de teste',
          'tipo_custo': 'fixed',
          'valor_centavos': tender.value,
          'data_referencia': iso,
          'status': 'pending',
          'criado_em': iso,
          'atualizado_em': iso,
        });
        await costs.markCostPaid(
          MarkCostPaidInput(
            costId: cost,
            paidAt: now,
            paymentMethod: tender.key,
            registerInCash: true,
          ),
        );
      }
      expect((await balance())['saldo_esperado_centavos'], -208);
      expect((await balance())['total_sangrias_centavos'], 208);
      await CashSessionMathSupport.rebuildSessionTotals(
        db,
        sessionId: sessionId,
      );
      expect((await balance())['saldo_esperado_centavos'], -208);
      expect(await db.query(TableNames.caixaMovimentos), hasLength(6));
    },
  );

  test(
    'política é isolada e login antigo não rebaixa revisão persistida',
    () async {
      app.configureCashPolicy(
        const CompanyContext.localDefault().copyWith(
          cashBlindClosureEnabled: true,
          cashPolicyRevision: 4,
        ),
      );
      await app.database;
      expect(
        (await CashWorkspaceStore.read(
          db,
          'cash.policy',
        ))['cashBlindClosureEnabled'],
        true,
      );
      app.configureCashPolicy(const CompanyContext.localDefault());
      await app.database;
      expect(
        (await CashWorkspaceStore.read(
          db,
          'cash.policy',
        ))['cashPolicyRevision'],
        4,
      );
      final otherKey = '$isolation-other';
      final other = AppDatabase.forIsolationKey(otherKey);
      addTearDown(() async {
        await other.close();
        await AppDatabase.deleteDatabaseForIsolationKeyForTesting(otherKey);
      });
      expect(
        await CashWorkspaceStore.read(await other.database, 'cash.policy'),
        isEmpty,
      );
    },
  );

  test(
    'configuração da empresa aceita API antiga e conserva política conhecida',
    () {
      final old = CompanyReceiptSettingsSnapshot.fromJson({
        'company': {'id': 'tenant', 'name': 'Loja'},
      });
      final known = const CompanyContext.localDefault().copyWith(
        cashBlindClosureEnabled: true,
        cashPolicyRevision: 2,
      );
      expect(old.mergeInto(known).cashBlindClosureEnabled, true);
      final current = CompanyReceiptSettingsSnapshot.fromJson({
        'company': {
          'id': 'tenant',
          'name': 'Loja',
          'cashBlindClosureEnabled': false,
          'cashPolicyRevision': 3,
        },
      }).mergeInto(known);
      expect(current.cashBlindClosureEnabled, false);
      expect(current.cashPolicyRevision, 3);
    },
  );

  test(
    'cache da sessão preserva política durante reinício offline e limpa ao sair',
    () async {
      SharedPreferences.setMockInitialValues({});
      final storage = SharedPreferencesCachedSessionStorage();
      final session = AppSession.localDefault();
      // Use a real remote identity in the existing cache contract.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('session.cached.user_id', 'u');
      await prefs.setString('session.cached.company_id', 'c');
      await prefs.setString('session.cached.client_instance_id', 'd');
      await prefs.setBool('session.cached.company.cash_blind_closure', true);
      await prefs.setInt('session.cached.company.cash_policy_revision', 6);
      final restored = await storage.readSession();
      expect(restored?.company.cashBlindClosureEnabled, true);
      expect(restored?.company.cashPolicyRevision, 6);
      await storage.clear();
      expect(await storage.readSession(), isNull);
      expect(session.company.cashBlindClosureEnabled, false);
    },
  );
}
