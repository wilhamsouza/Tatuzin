import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tatuzin/app/core/constants/app_constants.dart';
import 'package:tatuzin/app/core/database/migrations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('preserva as 37 versoes historicas publicadas', () {
    expect(AppConstants.databaseVersion, 37);
    expect(
      AppMigrations.versionsForTesting,
      List<int>.generate(37, (i) => i + 1),
    );
  });

  test('estrutura de migrations futuras esta integrada sem versao vazia', () {
    expect(
      AppMigrations.versionsForTesting,
      List<int>.generate(37, (i) => i + 1),
    );

    final migrationsSource = File(
      'lib/app/core/database/migrations.dart',
    ).readAsStringSync();
    final futureSource = File(
      'lib/app/core/database/future_migrations.dart',
    ).readAsStringSync();

    expect(migrationsSource, contains("part 'future_migrations.dart';"));
    expect(migrationsSource, contains('...futureMigrationSteps,'));
    expect(futureSource, contains("part of 'migrations.dart';"));
    expect(
      futureSource,
      contains(
        'const List<MigrationStep> futureMigrationSteps = <MigrationStep>[];',
      ),
    );
  });

  test('criacao limpa e upgrade antigo chegam ao mesmo schema final', () async {
    final clean = await _openCleanDatabase();
    addTearDown(clean.close);

    final migrated = await _openMigratedDatabaseFromVersion1();
    addTearDown(() async {
      final path = migrated.path;
      await migrated.close();
      await databaseFactory.deleteDatabase(path);
    });

    final cleanSchema = await _schemaSnapshot(clean);
    final migratedSchema = await _schemaSnapshot(migrated);

    expect(migratedSchema, cleanSchema);
    _expectMatchesFixture(cleanSchema, _loadFixture());
  });

  test('helper de coluna e idempotente', () async {
    final db = await openDatabase(inMemoryDatabasePath, version: 1);
    addTearDown(db.close);

    await db.execute('CREATE TABLE helper_test (id INTEGER PRIMARY KEY)');
    await AppMigrations.ensureColumnExistsForTesting(
      db,
      tableName: 'helper_test',
      columnName: 'notes',
      columnDefinition: 'TEXT',
    );
    await AppMigrations.ensureColumnExistsForTesting(
      db,
      tableName: 'helper_test',
      columnName: 'notes',
      columnDefinition: 'TEXT',
    );

    final columns = await db.rawQuery('PRAGMA table_info(helper_test)');
    expect(columns.where((row) => row['name'] == 'notes'), hasLength(1));
  });
}

Future<Database> _openCleanDatabase() {
  return openDatabase(
    inMemoryDatabasePath,
    version: AppConstants.databaseVersion,
    onCreate: AppMigrations.runCreate,
  );
}

Future<Database> _openMigratedDatabaseFromVersion1() async {
  final path =
      '${Directory.systemTemp.path}/tatuzin_migration_${DateTime.now().microsecondsSinceEpoch}.db';
  var db = await openDatabase(
    path,
    version: 1,
    onCreate: AppMigrations.runCreate,
  );
  await db.close();

  db = await openDatabase(
    path,
    version: AppConstants.databaseVersion,
    onUpgrade: AppMigrations.runUpgrade,
  );
  return db;
}

Future<Map<String, Object?>> _schemaSnapshot(Database db) async {
  final objects = await db.rawQuery('''
    SELECT type, name, tbl_name, sql
    FROM sqlite_master
    WHERE name NOT LIKE 'sqlite_%'
    ORDER BY type, name
  ''');

  final tableNames = objects
      .where((row) => row['type'] == 'table')
      .map((row) => row['name']! as String)
      .toList(growable: false);

  final tables = <String, Object?>{};
  for (final table in tableNames) {
    tables[table] = {
      'columns': await _columns(db, table),
      'foreignKeys': await _foreignKeys(db, table),
      'indexes': await _indexes(db, table),
    };
  }

  return {
    'version': AppConstants.databaseVersion,
    'objects': objects
        .map(
          (row) => {
            'type': row['type'],
            'name': row['name'],
            'table': row['tbl_name'],
            'sql': _normalizeSql(row['sql']?.toString()),
          },
        )
        .toList(growable: false),
    'tables': tables,
  };
}

Future<List<Object?>> _columns(Database db, String table) async {
  final rows = await db.rawQuery('PRAGMA table_info($table)');
  return rows
      .map(
        (row) => {
          'name': row['name'],
          'type': row['type'],
          'notnull': row['notnull'],
          'default': row['dflt_value'],
          'pk': row['pk'],
        },
      )
      .toList(growable: false);
}

Future<List<Object?>> _foreignKeys(Database db, String table) async {
  final rows = await db.rawQuery('PRAGMA foreign_key_list($table)');
  return rows
      .map(
        (row) => {
          'from': row['from'],
          'table': row['table'],
          'to': row['to'],
          'onUpdate': row['on_update'],
          'onDelete': row['on_delete'],
        },
      )
      .toList(growable: false);
}

Future<List<Object?>> _indexes(Database db, String table) async {
  final rows = await db.rawQuery('PRAGMA index_list($table)');
  return rows
      .map(
        (row) => {
          'name': row['name'],
          'unique': row['unique'],
          'origin': row['origin'],
          'partial': row['partial'],
        },
      )
      .toList(growable: false);
}

Map<String, Object?> _loadFixture() {
  final file = File('test/fixtures/sqlite_schema_v37_snapshot.json');
  return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
}

void _expectMatchesFixture(
  Map<String, Object?> schema,
  Map<String, Object?> fixture,
) {
  expect(schema['version'], fixture['version']);
  expect(AppMigrations.versionsForTesting, fixture['migrationVersions']);

  final tables = schema['tables']! as Map<String, Object?>;
  final fixtureTables = fixture['tables']! as Map<String, Object?>;
  for (final entry in fixtureTables.entries) {
    expect(tables, contains(entry.key));
    final table = tables[entry.key]! as Map<String, Object?>;
    final expectedColumns = List<String>.from(entry.value as List<dynamic>);
    final actualColumns = (table['columns']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .map((row) => row['name'])
        .toList(growable: false);
    expect(actualColumns, containsAll(expectedColumns), reason: entry.key);
  }

  final objectNames = (schema['objects']! as List<Object?>)
      .cast<Map<String, Object?>>()
      .map((row) => row['name'])
      .toSet();
  expect(
    objectNames,
    containsAll(List<String>.from(fixture['indexes']! as List<dynamic>)),
  );
  expect(
    objectNames,
    containsAll(List<String>.from(fixture['triggers']! as List<dynamic>)),
  );
}

String? _normalizeSql(String? sql) {
  return sql
      ?.replaceAll(
        RegExp(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+'),
        '<timestamp>',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
