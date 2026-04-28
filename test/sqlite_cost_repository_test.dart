import 'package:erp_pdv_app/app/core/app_context/app_operational_context.dart';
import 'package:erp_pdv_app/app/core/config/app_environment.dart';
import 'package:erp_pdv_app/app/core/database/table_names.dart';
import 'package:erp_pdv_app/app/core/session/app_session.dart';
import 'package:erp_pdv_app/modules/custos/data/sqlite_cost_repository.dart';
import 'package:erp_pdv_app/modules/custos/domain/entities/cost_type.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Database database;
  late SqliteCostRepository repository;

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await _createCostSchema(db);
        },
      ),
    );
    repository = SqliteCostRepository.forDatabase(
      databaseLoader: () async => database,
      operationalContext: AppOperationalContext(
        environment: const AppEnvironment.localDefault(),
        session: AppSession.localDefault(),
      ),
    );
  });

  tearDown(() async {
    await database.close();
  });

  test('overview vazio retorna zerado rapidamente', () async {
    final overview = await repository.fetchOverview().timeout(
      const Duration(seconds: 2),
    );

    expect(overview.pendingFixedCents, 0);
    expect(overview.pendingVariableCents, 0);
    expect(overview.openFixedCount, 0);
    expect(overview.openVariableCount, 0);
  });

  test('lista vazia retorna rapidamente', () async {
    final costs = await repository
        .searchCosts(type: CostType.fixed)
        .timeout(const Duration(seconds: 2));

    expect(costs, isEmpty);
  });

  test('falha SQLite em custos propaga erro', () async {
    await database.execute('DROP TABLE ${TableNames.custos}');

    await expectLater(
      repository.fetchOverview(),
      throwsA(isA<DatabaseException>()),
    );
  });
}

Future<void> _createCostSchema(Database db) {
  return db.execute('''
    CREATE TABLE ${TableNames.custos} (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL,
      remote_id TEXT,
      descricao TEXT NOT NULL,
      tipo_custo TEXT NOT NULL,
      categoria TEXT,
      valor_centavos INTEGER NOT NULL DEFAULT 0,
      data_referencia TEXT NOT NULL,
      pago_em TEXT,
      forma_pagamento TEXT,
      observacao TEXT,
      recorrente INTEGER NOT NULL DEFAULT 0,
      status TEXT NOT NULL,
      caixa_movimento_id INTEGER,
      criado_em TEXT NOT NULL,
      atualizado_em TEXT NOT NULL,
      cancelado_em TEXT
    )
  ''');
}
