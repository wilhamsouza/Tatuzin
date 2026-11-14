import 'package:tatuzin/app/core/database/app_database.dart';
import 'package:tatuzin/app/core/database/table_names.dart';
import 'package:tatuzin/app/core/providers/app_data_refresh_provider.dart';
import 'package:tatuzin/modules/relatorios/domain/entities/report_filter.dart';
import 'package:tatuzin/modules/relatorios/presentation/providers/report_providers.dart';
import 'package:tatuzin/app/core/session/app_session.dart';
import 'package:tatuzin/app/core/session/app_user.dart';
import 'package:tatuzin/app/core/session/company_context.dart';
import 'package:tatuzin/app/core/session/session_provider.dart';
import 'package:tatuzin/modules/dashboard/presentation/providers/dashboard_providers.dart';
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
            clientInstanceId: session.clientInstanceId,
            membership: const AppMembershipContext(
              role: 'OWNER',
              permissions: {},
            ),
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
      expect(snapshot.todaySalesCount, 1);
      expect(snapshot.hasOpenCashSession, true);
      expect(snapshot.currentCashCents, 18500);
      expect(snapshot.pendingFiadoCount, 1);
      expect(snapshot.pendingFiadoCents, 1800);
      expect(snapshot.activeOperationalOrdersCount, 2);
      expect(snapshot.recentMovementsCount, 2);
      expect(snapshot.recentMovements.first.label, 'Venda recebida');
      expect(snapshot.recentMovements.last.label, 'Sangria');

      final template = Map<String, Object?>.from(
        (await database.query(
          TableNames.vendas,
          where: 'status = ? AND numero_cupom != ?',
          whereArgs: ['ativa', 'cupom-fiado'],
          limit: 1,
        )).first,
      )..remove('id');
      for (var index = 0; index < 6; index++) {
        await database.insert(TableNames.vendas, {
          ...template,
          'uuid': 'extra-sale-$index-${now.microsecondsSinceEpoch}',
          'numero_cupom': 'extra-$index',
          'valor_total_centavos': 100,
          'valor_final_centavos': 100,
          'data_venda': now.toIso8601String(),
        });
        await database.insert(TableNames.caixaMovimentos, {
          'uuid': 'extra-movement-$index-${now.microsecondsSinceEpoch}',
          'sessao_id': openCashSessionId,
          'tipo_movimento': 'venda',
          'valor_centavos': 100,
          'criado_em': now.toIso8601String(),
        });
      }
      await database.insert(TableNames.vendas, {
        ...template,
        'uuid': 'cancelled-${now.microsecondsSinceEpoch}',
        'numero_cupom': 'cancelled-extra',
        'status': 'cancelada',
        'valor_final_centavos': 99999,
        'data_venda': now.toIso8601String(),
      });
      container.invalidate(operationalDashboardSnapshotProvider);
      final updated = await container.read(
        operationalDashboardSnapshotProvider.future,
      );
      expect(updated.todaySalesCount, 7);
      expect(updated.soldTodayCents, 3000);
      expect(updated.recentMovementsCount, 5);

      final reportFilter = ReportFilter(
        start: DateTime(2025),
        endExclusive: DateTime(2025, 2),
      );
      container.read(reportFilterProvider.notifier).replace(reportFilter);
      final subscription = container.listen(
        dashboardSalesTrendProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);
      final trend = await container.read(dashboardSalesTrendProvider.future);
      expect(trend, hasLength(7));
      expect(trend.last.netSalesCents, 3000);
      expect(trend.last.salesCount, 7);
      expect(trend[5].netSalesCents, 3000);
      expect(trend.take(5).every((point) => point.netSalesCents == 0), isTrue);
      expect(container.read(reportFilterProvider), same(reportFilter));

      await database.insert(TableNames.vendas, {
        ...template,
        'uuid': 'refresh-sale-${now.microsecondsSinceEpoch}',
        'numero_cupom': 'refresh-sale',
        'valor_total_centavos': 500,
        'valor_final_centavos': 500,
        'data_venda': now.toIso8601String(),
      });
      container.read(appDataRefreshProvider.notifier).state++;
      final refreshedTrend = await container.read(
        dashboardSalesTrendProvider.future,
      );
      expect(refreshedTrend.last.netSalesCents, 3500);
      expect(refreshedTrend.last.salesCount, 8);
      expect(container.read(reportFilterProvider), same(reportFilter));
    },
  );

  test(
    'home não consulta relatórios sem permissão nem inicia bootstrap',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        await container.read(dashboardDailyOverviewProvider.future),
        isNull,
      );
      expect(await container.read(dashboardSalesTrendProvider.future), isEmpty);
      expect(container.exists(appStartupProvider), isFalse);
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
    clientInstanceId: 'device-1',
  );
}
