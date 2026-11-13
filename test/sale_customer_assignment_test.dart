import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tatuzin/app/core/app_context/app_operational_context.dart';
import 'package:tatuzin/app/core/config/app_environment.dart';
import 'package:tatuzin/app/core/database/app_database.dart';
import 'package:tatuzin/app/core/database/table_names.dart';
import 'package:tatuzin/app/core/session/app_session.dart';
import 'package:tatuzin/app/core/session/session_provider.dart';
import 'package:tatuzin/app/core/sync/operational_sync_projection_applier.dart';
import 'package:tatuzin/app/core/sync/operational_sync_remote_datasource.dart';
import 'package:tatuzin/modules/activity/presentation/activity_providers.dart';
import 'package:tatuzin/modules/historico_vendas/data/sale_customer_assignment_repository.dart';
import 'package:tatuzin/modules/historico_vendas/data/sqlite_sale_history_repository.dart';
import 'test_tenant_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late ProviderContainer container;
  late AppDatabase appDb;
  late Database db;
  late SaleCustomerAssignmentRepository repository;
  late AppOperationalContext context;
  late String isolation;
  late int client;
  late int sale;

  setUp(() async {
    container = ProviderContainer();
    setTestTenantSession(container);
    final session = container
        .read(appSessionProvider)
        .copyWith(
          membership: const AppMembershipContext(
            role: 'OWNER',
            permissions: {},
          ),
        );
    context = AppOperationalContext(
      environment: const AppEnvironment.localDefault(),
      session: session,
    );
    isolation = 'remote:assignment-${DateTime.now().microsecondsSinceEpoch}';
    appDb = AppDatabase.forIsolationKey(isolation);
    db = await appDb.database;
    repository = SaleCustomerAssignmentRepository(appDb, context);
    final now = DateTime.now().toIso8601String();
    client = await db.insert(TableNames.clientes, {
      'uuid': 'client-a',
      'nome': 'Ana',
      'ativo': 1,
      'criado_em': now,
      'atualizado_em': now,
    });
    sale = await db.insert(TableNames.vendas, {
      'uuid': 'sale-a',
      'tipo_venda': 'vista',
      'forma_pagamento': 'pix',
      'status': 'ativa',
      'valor_total_centavos': 2500,
      'valor_final_centavos': 2500,
      'numero_cupom': '123',
      'data_venda': now,
      'seller_remote_user_id': session.user.remoteId,
    });
  });
  tearDown(() async {
    container.dispose();
    await appDb.close();
    await AppDatabase.deleteDatabaseForIsolationKeyForTesting(isolation);
  });

  test(
    'association persists audit and outbox atomically without changing money',
    () async {
      final original = (await db.query(
        TableNames.vendas,
        where: 'id=?',
        whereArgs: [sale],
      )).single;
      await repository.assign(sale, client);
      final saved = (await db.query(
        TableNames.vendas,
        where: 'id=?',
        whereArgs: [sale],
      )).single;
      for (final key in original.keys.where(
        (k) => !['cliente_id', 'customer_assignment_revision'].contains(k),
      )) {
        expect(saved[key], original[key], reason: key);
      }
      expect(saved['cliente_id'], client);
      expect(saved['customer_assignment_revision'], 1);
      expect((await db.query('sale_customer_assignments')).length, 1);
      final event = (await db.query(TableNames.operationalSyncEvents)).single;
      expect(event['entity'], 'saleCustomerAssignment');
      expect(
        jsonDecode(event['payload_json'] as String)['customerUuid'],
        'client-a',
      );
      expect(await repository.syncMessage(sale), contains('pendente'));
      await appDb.close();
      expect(
        (await SqliteSaleHistoryRepository(
          appDb,
        ).fetchDetail(sale)).sale.clientName,
        'Ana',
      );
    },
  );

  test(
    'pending assignment blocks another edit; rejection is visible and values remain intact',
    () async {
      await repository.assign(sale, client);
      final second = await db.insert(TableNames.clientes, {
        'uuid': 'client-b',
        'nome': 'Bia',
        'ativo': 1,
        'criado_em': DateTime.now().toIso8601String(),
        'atualizado_em': DateTime.now().toIso8601String(),
      });
      await expectLater(repository.assign(sale, second), throwsStateError);
      await db.update(TableNames.operationalSyncEvents, {
        'status': 'conflict',
        'error_message': 'Revisão divergente',
      });
      expect(await repository.syncMessage(sale), contains('não confirmada'));
      expect((await db.query('sale_customer_assignments')).length, 1);
    },
  );

  test('financial and ownership restrictions reject before mutation', () async {
    for (final change in [
      {'tipo_venda': 'fiado'},
      {'haver_utilizado_centavos': 100},
      {'haver_gerado_centavos': 100},
      {'status': 'cancelada'},
      {'customer_assignment_locked': 1},
    ]) {
      await db.update(
        TableNames.vendas,
        change,
        where: 'id=?',
        whereArgs: [sale],
      );
      await expectLater(repository.assign(sale, client), throwsStateError);
      await db.update(
        TableNames.vendas,
        {
          'tipo_venda': 'vista',
          'haver_utilizado_centavos': 0,
          'haver_gerado_centavos': 0,
          'status': 'ativa',
          'customer_assignment_locked': 0,
        },
        where: 'id=?',
        whereArgs: [sale],
      );
    }
    final operatorContext = AppOperationalContext(
      environment: context.environment,
      session: context.session.copyWith(
        membership: const AppMembershipContext(
          role: 'SELLER',
          permissions: {'sales.create'},
        ),
      ),
    );
    await db.update(
      TableNames.vendas,
      {'seller_remote_user_id': 'another-user'},
      where: 'id=?',
      whereArgs: [sale],
    );
    await expectLater(
      SaleCustomerAssignmentRepository(
        appDb,
        operatorContext,
      ).assign(sale, client),
      throwsStateError,
    );
    expect(await db.query('sale_customer_assignments'), isEmpty);
  });

  test('failure to enqueue rolls back customer and audit', () async {
    await db.execute(
      "CREATE TRIGGER fail_assignment_queue BEFORE INSERT ON ${TableNames.operationalSyncEvents} BEGIN SELECT RAISE(ABORT,'test failure'); END",
    );
    await expectLater(repository.assign(sale, client), throwsA(anything));
    expect(
      (await db.query(
        TableNames.vendas,
        where: 'id=?',
        whereArgs: [sale],
      )).single['cliente_id'],
      isNull,
    );
    expect(await db.query('sale_customer_assignments'), isEmpty);
  });

  test(
    'remote customer projection applies without changing money and ignores stale revisions',
    () async {
      final applier = SqliteOperationalSyncProjectionApplier(
        appDatabase: appDb,
        companyRemoteId: 'company-1',
      );
      OperationalSyncPulledEvent change(int revision, String? uuid) =>
          OperationalSyncPulledEvent(
            eventId: 'remote-$revision',
            feature: 'pdv',
            entity: 'saleCustomerAssignment',
            operation: 'append',
            occurredAt: DateTime.now(),
            payload: const {},
            projection: {
              'companyId': 'company-1',
              'saleUuid': 'sale-a',
              'customerServerId': null,
              'customerUuid': uuid,
              'revision': revision,
            },
          );
      await applier.apply(change(1, 'client-a'));
      expect(
        (await SqliteSaleHistoryRepository(
          appDb,
        ).fetchDetail(sale)).sale.clientName,
        'Ana',
      );
      await applier.apply(change(0, null));
      final saved = (await db.query(
        TableNames.vendas,
        where: 'id=?',
        whereArgs: [sale],
      )).single;
      expect(saved['cliente_id'], client);
      expect(saved['valor_final_centavos'], 2500);
    },
  );

  test(
    'today activity includes more than five sales and excludes other dates',
    () async {
      final now = DateTime.now();
      for (var index = 0; index < 8; index++) {
        await db.insert(TableNames.vendas, {
          'uuid': 'sale-$index',
          'tipo_venda': 'vista',
          'forma_pagamento': 'pix',
          'status': index == 0 ? 'cancelada' : 'ativa',
          'valor_total_centavos': 1000,
          'valor_final_centavos': 1000,
          'numero_cupom': 'today-$index',
          'data_venda': now.toIso8601String(),
        });
      }
      await db.insert(TableNames.vendas, {
        'uuid': 'yesterday',
        'tipo_venda': 'vista',
        'forma_pagamento': 'pix',
        'status': 'ativa',
        'valor_total_centavos': 1000,
        'valor_final_centavos': 1000,
        'numero_cupom': 'yesterday',
        'data_venda': DateTime(
          now.year,
          now.month,
          now.day - 1,
        ).toIso8601String(),
      });
      final scope = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWith((ref) => appDb),
          appStartupProvider.overrideWith(
            (ref) async => const AppStartupState.success(),
          ),
        ],
      );
      addTearDown(scope.dispose);
      setTestTenantSession(scope);
      final today = await scope.read(dailySaleActivityProvider.future);
      expect(today.length, 9);
      expect(today.any((sale) => sale.receiptNumber == 'yesterday'), false);
    },
  );
}
