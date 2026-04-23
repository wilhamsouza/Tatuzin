import 'package:erp_pdv_app/app/core/database/app_database.dart';
import 'package:erp_pdv_app/app/core/database/table_names.dart';
import 'package:erp_pdv_app/app/core/session/app_session.dart';
import 'package:erp_pdv_app/app/core/session/app_user.dart';
import 'package:erp_pdv_app/app/core/session/company_context.dart';
import 'package:erp_pdv_app/app/core/session/session_provider.dart';
import 'package:erp_pdv_app/modules/dashboard/presentation/providers/dashboard_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'operational dashboard snapshot usa apenas sinais locais operacionais',
    () async {
      final session = _remoteSession();
      final isolationKey = SessionIsolation.keyFor(session);
      await AppDatabase.deleteDatabaseForIsolationKeyForTesting(isolationKey);

      final container = ProviderContainer();
      addTearDown(() async {
        container.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await AppDatabase.deleteDatabaseForIsolationKeyForTesting(isolationKey);
      });

      container
          .read(appSessionProvider.notifier)
          .setAuthenticatedSession(
            scope: session.scope,
            user: session.user,
            company: session.company,
            isOfflineFallback: session.isOfflineFallback,
          );
      await container.read(appStartupProvider.future);

      final database = await container.read(appDatabaseProvider).database;
      final now = DateTime.now();
      final yesterday = now.subtract(const Duration(days: 1));
      final clientId = await database.insert(TableNames.clientes, {
        'uuid': 'client-${now.microsecondsSinceEpoch}',
        'nome': 'Cliente Operacional',
        'telefone': null,
        'endereco': null,
        'observacao': null,
        'saldo_devedor_centavos': 0,
        'ativo': 1,
        'criado_em': now.toIso8601String(),
        'atualizado_em': now.toIso8601String(),
        'deletado_em': null,
      });

      final openCashSessionId = await database.insert(TableNames.caixaSessoes, {
        'uuid': 'cash-session-${now.microsecondsSinceEpoch}',
        'usuario_id': null,
        'aberta_em': now.toIso8601String(),
        'fechada_em': null,
        'troco_inicial_centavos': 2000,
        'total_suprimentos_centavos': 0,
        'total_sangrias_centavos': 0,
        'total_vendas_centavos': 0,
        'total_recebimentos_fiado_centavos': 0,
        'saldo_final_centavos': 18500,
        'status': 'aberto',
        'observacao': null,
      });

      await database.insert(TableNames.caixaMovimentos, {
        'uuid': 'mov-${now.microsecondsSinceEpoch}-1',
        'sessao_id': openCashSessionId,
        'tipo_movimento': 'venda',
        'referencia_tipo': 'venda',
        'referencia_id': 1,
        'valor_centavos': 12500,
        'descricao': 'Venda do balcao',
        'criado_em': now.toIso8601String(),
      });
      await database.insert(TableNames.caixaMovimentos, {
        'uuid': 'mov-${now.microsecondsSinceEpoch}-2',
        'sessao_id': openCashSessionId,
        'tipo_movimento': 'sangria',
        'referencia_tipo': 'caixa',
        'referencia_id': null,
        'valor_centavos': 1500,
        'descricao': 'Retirada para troco',
        'criado_em': now.subtract(const Duration(minutes: 5)).toIso8601String(),
      });

      await database.insert(TableNames.vendas, {
        'uuid': 'sale-${now.microsecondsSinceEpoch}-today',
        'cliente_id': null,
        'tipo_venda': 'vista',
        'forma_pagamento': 'dinheiro',
        'status': 'ativa',
        'desconto_centavos': 0,
        'acrescimo_centavos': 0,
        'valor_total_centavos': 2400,
        'valor_final_centavos': 2400,
        'numero_cupom': 'cupom-hoje',
        'data_venda': now.toIso8601String(),
        'usuario_id': null,
        'observacao': null,
        'cancelada_em': null,
        'venda_origem_id': null,
      });
      await database.insert(TableNames.vendas, {
        'uuid': 'sale-${now.microsecondsSinceEpoch}-old',
        'cliente_id': clientId,
        'tipo_venda': 'fiado',
        'forma_pagamento': 'fiado',
        'status': 'ativa',
        'desconto_centavos': 0,
        'acrescimo_centavos': 0,
        'valor_total_centavos': 3000,
        'valor_final_centavos': 3000,
        'numero_cupom': 'cupom-fiado',
        'data_venda': yesterday.toIso8601String(),
        'usuario_id': null,
        'observacao': null,
        'cancelada_em': null,
        'venda_origem_id': null,
      });
      final fiadoSaleRows = await database.query(
        TableNames.vendas,
        where: 'numero_cupom = ?',
        whereArgs: ['cupom-fiado'],
        limit: 1,
      );
      final fiadoSaleId = fiadoSaleRows.first['id'] as int;

      await database.insert(TableNames.fiado, {
        'uuid': 'fiado-${now.microsecondsSinceEpoch}',
        'cliente_id': clientId,
        'venda_id': fiadoSaleId,
        'valor_original_centavos': 3000,
        'valor_aberto_centavos': 1800,
        'vencimento': now.toIso8601String(),
        'status': 'pendente',
        'criado_em': now.toIso8601String(),
        'atualizado_em': now.toIso8601String(),
        'quitado_em': null,
      });

      await database.insert(TableNames.pedidosOperacionais, {
        'uuid': 'order-${now.microsecondsSinceEpoch}-open',
        'status': 'open',
        'observacao': null,
        'criado_em': now.toIso8601String(),
        'atualizado_em': now.toIso8601String(),
        'fechado_em': null,
      });
      await database.insert(TableNames.pedidosOperacionais, {
        'uuid': 'order-${now.microsecondsSinceEpoch}-ready',
        'status': 'ready',
        'observacao': null,
        'criado_em': now.toIso8601String(),
        'atualizado_em': now.toIso8601String(),
        'fechado_em': null,
      });
      await database.insert(TableNames.pedidosOperacionais, {
        'uuid': 'order-${now.microsecondsSinceEpoch}-done',
        'status': 'delivered',
        'observacao': null,
        'criado_em': now.toIso8601String(),
        'atualizado_em': now.toIso8601String(),
        'fechado_em': now.toIso8601String(),
      });

      final snapshot = await container.read(
        operationalDashboardSnapshotProvider.future,
      );

      expect(snapshot.soldTodayCents, 2400);
      expect(snapshot.currentCashCents, 18500);
      expect(snapshot.pendingFiadoCount, 1);
      expect(snapshot.pendingFiadoCents, 1800);
      expect(snapshot.activeOperationalOrdersCount, 2);
      expect(snapshot.recentMovementsCount, 2);
      expect(snapshot.recentMovements.first.label, 'Venda recebida');
      expect(snapshot.recentMovements.last.label, 'Sangria');
    },
  );
}

AppSession _remoteSession() {
  final suffix = DateTime.now().microsecondsSinceEpoch;
  return AppSession(
    scope: SessionScope.authenticatedRemote,
    user: AppUser(
      localId: null,
      remoteId: 'usr_dashboard_$suffix',
      displayName: 'Operador Dashboard',
      email: 'dashboard_$suffix@tatuzin.test',
      roleLabel: 'Operador',
      kind: AppUserKind.remoteAuthenticated,
    ),
    company: CompanyContext(
      localId: null,
      remoteId: 'cmp_dashboard_$suffix',
      displayName: 'Empresa Dashboard',
      legalName: 'Empresa Dashboard LTDA',
      documentNumber: null,
      licensePlan: 'pro',
      licenseStatus: 'active',
      syncEnabled: true,
    ),
    startedAt: DateTime.now(),
    isOfflineFallback: false,
  );
}
