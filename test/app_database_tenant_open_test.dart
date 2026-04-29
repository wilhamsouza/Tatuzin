import 'package:erp_pdv_app/app/core/database/app_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('abertura concorrente do mesmo tenant reutiliza a instancia', () async {
    final isolationKey =
        'remote:tenant-open-${DateTime.now().microsecondsSinceEpoch}';
    final first = AppDatabase.forIsolationKey(isolationKey);
    final second = AppDatabase.forIsolationKey(isolationKey);

    addTearDown(() async {
      await first.close();
      await AppDatabase.deleteDatabaseForIsolationKeyForTesting(isolationKey);
    });

    expect(identical(first, second), isTrue);

    final databases = await Future.wait([
      first.database,
      second.database,
      AppDatabase.openForIsolationKey(isolationKey).then((_) => first.database),
    ]).timeout(const Duration(seconds: 8));

    expect(identical(databases[0], databases[1]), isTrue);
    expect(identical(databases[0], databases[2]), isTrue);
  });

  test('abertura normal registra trace pesquisavel das etapas', () async {
    final logs = <String>[];
    final previousDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      logs.add(message ?? '');
    };
    addTearDown(() {
      debugPrint = previousDebugPrint;
    });

    final isolationKey =
        'remote:tenant-trace-${DateTime.now().microsecondsSinceEpoch}';
    final database = AppDatabase.forIsolationKey(isolationKey);

    addTearDown(() async {
      await database.close();
      await AppDatabase.deleteDatabaseForIsolationKeyForTesting(isolationKey);
    });

    await database.database.timeout(const Duration(seconds: 8));

    final joined = logs.join('\n');
    expect(joined, contains('[DB_OPEN_TRACE] file_state'));
    expect(joined, contains('[DB_OPEN_TRACE] before_open_database'));
    expect(joined, contains('[DB_OPEN_TRACE] on_configure_started'));
    expect(joined, contains('[DB_OPEN_TRACE] on_configure_finished'));
    expect(joined, contains('[DB_OPEN_TRACE] on_create_started'));
    expect(joined, contains('[DB_OPEN_TRACE] on_create_finished'));
    expect(joined, contains('[DB_OPEN_TRACE] on_open_started'));
    expect(joined, contains('[DB_OPEN_TRACE] on_open_finished'));
    expect(joined, contains('[DB_OPEN_TRACE] after_open_database'));
    expect(joined, contains('[DB_OPEN_TRACE] post_bootstrap_started'));
    expect(joined, contains('[DB_OPEN_TRACE] post_bootstrap_finished'));
  });
}
