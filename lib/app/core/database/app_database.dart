import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../constants/app_constants.dart';
import '../errors/app_exceptions.dart';
import '../utils/app_logger.dart';
import 'migrations.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  return AppDatabase.instance;
});

final appStartupProvider = FutureProvider<void>((ref) async {
  final database = ref.read(appDatabaseProvider);
  await database.database;
});

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    try {
      final databasesPath = await getDatabasesPath();
      final databasePath = path.join(databasesPath, AppConstants.databaseName);

      AppLogger.info('Opening database at $databasePath');
      AppLogger.info('Database bootstrap started');

      _database = await openDatabase(
        databasePath,
        version: AppConstants.databaseVersion,
        onConfigure: (db) async {
          await _runBootstrapStep('onConfigure > PRAGMA foreign_keys = ON', () {
            return _enableForeignKeys(db);
          });
          await _runBootstrapStep(
            'onConfigure > PRAGMA journal_mode = WAL',
            () {
              return _configureJournalMode(db);
            },
          );
        },
        onCreate: (db, version) async {
          await _runBootstrapStep(
            'onCreate > schema version $version',
            () async {
              AppLogger.info('Creating database schema version $version');
              await db.transaction((txn) async {
                await AppMigrations.runCreate(txn, version);
              });
            },
          );
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          await _runBootstrapStep(
            'onUpgrade > schema v$oldVersion to v$newVersion',
            () async {
              AppLogger.info(
                'Upgrading database from v$oldVersion to v$newVersion',
              );
              await db.transaction((txn) async {
                await AppMigrations.runUpgrade(txn, oldVersion, newVersion);
              });
            },
          );
        },
        onOpen: (db) async {
          await _runBootstrapStep('onOpen > final verification', () async {
            AppLogger.info('Database opened successfully');
            final foreignKeyResult = await db.rawQuery('PRAGMA foreign_keys');
            final foreignKeysEnabled = _readPragmaValue(foreignKeyResult);
            AppLogger.info(
              'PRAGMA foreign_keys verification returned $foreignKeysEnabled',
            );
            if (foreignKeysEnabled != '1') {
              throw StateError(
                'foreign_keys remained disabled after opening the database '
                '(result=$foreignKeysEnabled)',
              );
            }
          });
        },
      );

      return _database!;
    } catch (error, stackTrace) {
      if (error is DatabaseInitializationException) {
        AppLogger.error(
          'Database initialization aborted during bootstrap',
          error: error,
          stackTrace: stackTrace,
        );
        rethrow;
      }

      AppLogger.error(
        'Database initialization failed',
        error: error,
        stackTrace: stackTrace,
      );
      throw DatabaseInitializationException(
        'Nao foi possivel inicializar o banco de dados local',
        cause: error,
      );
    }
  }

  Future<void> close() async {
    if (_database == null) {
      return;
    }

    await _database!.close();
    _database = null;
    AppLogger.info('Database connection closed');
  }

  Future<void> _enableForeignKeys(Database db) async {
    AppLogger.info('Executing PRAGMA foreign_keys = ON with execute()');
    await db.execute('PRAGMA foreign_keys = ON');

    final result = await db.rawQuery('PRAGMA foreign_keys');
    final value = _readPragmaValue(result);

    AppLogger.info('PRAGMA foreign_keys returned $value');

    if (value != '1') {
      throw StateError(
        'PRAGMA foreign_keys verification failed with result=$value',
      );
    }
  }

  Future<void> _configureJournalMode(Database db) async {
    AppLogger.info('Executing PRAGMA journal_mode = WAL with rawQuery()');

    try {
      final walResult = await db.rawQuery('PRAGMA journal_mode = WAL');
      final walMode = _readPragmaValue(walResult);

      AppLogger.info('PRAGMA journal_mode = WAL returned $walMode');

      if (walMode == null || walMode.isEmpty) {
        throw StateError('PRAGMA journal_mode = WAL returned no result');
      }
    } catch (error, stackTrace) {
      AppLogger.warn(
        'PRAGMA journal_mode = WAL failed; attempting DELETE fallback | '
        'error=$error',
      );
      AppLogger.error(
        'WAL journal mode could not be enabled',
        error: error,
        stackTrace: stackTrace,
      );

      final fallbackResult = await db.rawQuery('PRAGMA journal_mode = DELETE');
      final fallbackMode = _readPragmaValue(fallbackResult);

      AppLogger.warn('PRAGMA journal_mode fallback returned $fallbackMode');

      if (fallbackMode == null || fallbackMode.isEmpty) {
        throw StateError(
          'PRAGMA journal_mode fallback to DELETE returned no result',
        );
      }
    }
  }

  Future<void> _runBootstrapStep(
    String step,
    Future<void> Function() action,
  ) async {
    AppLogger.info('Database bootstrap step started: $step');

    try {
      await action();
      AppLogger.info('Database bootstrap step completed: $step');
    } catch (error, stackTrace) {
      AppLogger.error(
        'Database bootstrap step failed: $step',
        error: error,
        stackTrace: stackTrace,
      );
      throw DatabaseInitializationException(
        'Nao foi possivel inicializar o banco de dados local na etapa: $step',
        cause: error,
      );
    }
  }

  String? _readPragmaValue(List<Map<String, Object?>> rows) {
    if (rows.isEmpty) {
      return null;
    }

    final firstRow = rows.first;
    if (firstRow.isEmpty) {
      return null;
    }

    return firstRow.values.first?.toString();
  }
}
