import 'package:erp_pdv_app/app/core/database/app_database.dart';
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
}
