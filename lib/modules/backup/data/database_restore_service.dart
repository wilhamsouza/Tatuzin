import 'dart:io';

import 'package:sqflite/sqflite.dart';

import '../../../app/core/database/app_database.dart';
import '../../../app/core/database/database_file_locator.dart';
import '../../../app/core/database/table_names.dart';
import '../../../app/core/errors/app_exceptions.dart';
import '../../../app/core/utils/app_logger.dart';
import '../../../app/core/utils/id_generator.dart';
import '../domain/entities/backup_restore_result.dart';
import 'backup_validation_service.dart';
import 'database_backup_service.dart';

class DatabaseRestoreService {
  DatabaseRestoreService({
    required AppDatabase appDatabase,
    required DatabaseFileLocator fileLocator,
    required BackupValidationService validationService,
    required DatabaseBackupService backupService,
  }) : _appDatabase = appDatabase,
       _fileLocator = fileLocator,
       _validationService = validationService,
       _backupService = backupService;

  final AppDatabase _appDatabase;
  final DatabaseFileLocator _fileLocator;
  final BackupValidationService _validationService;
  final DatabaseBackupService _backupService;

  Future<BackupRestoreResult> restoreFromBackup(String backupFilePath) async {
    final currentDatabasePath = await _fileLocator.resolveDatabasePath();
    if (backupFilePath == currentDatabasePath) {
      throw const ValidationException(
        'Selecione um arquivo de backup exportado, nao a base ativa do aplicativo.',
      );
    }

    final validatedBackup = await _validationService.validate(backupFilePath);
    final safetyBackup = await _backupService.createBackup(safetyCopy: true);

    await _appDatabase.close();

    try {
      await deleteDatabase(currentDatabasePath);
      await _deleteSidecars(currentDatabasePath);
      await File(backupFilePath).copy(currentDatabasePath);

      await _validationService.validate(currentDatabasePath);
      await _appDatabase.database;
      await _writeRestoreLog(
        status: 'sucesso',
        destination: backupFilePath,
        details:
            'Restauracao concluida com sucesso usando ${validatedBackup.fileName}.',
      );

      return BackupRestoreResult(
        restoredBackup: validatedBackup,
        safetyBackup: safetyBackup,
        restoredAt: DateTime.now(),
      );
    } catch (error, stackTrace) {
      AppLogger.error(
        'Restore failed. Attempting rollback using safety backup',
        error: error,
        stackTrace: stackTrace,
      );

      try {
        await deleteDatabase(currentDatabasePath);
        await _deleteSidecars(currentDatabasePath);
        await File(safetyBackup.filePath).copy(currentDatabasePath);
        await _validationService.validate(currentDatabasePath);
        await _appDatabase.close();
        await _appDatabase.database;
        await _writeRestoreLog(
          status: 'falha',
          destination: backupFilePath,
          details:
              'Falha na restauracao. A base anterior foi recuperada pelo backup de seguranca ${safetyBackup.fileName}. Erro: $error',
        );
      } catch (rollbackError, rollbackStackTrace) {
        AppLogger.error(
          'Rollback after restore failure also failed',
          error: rollbackError,
          stackTrace: rollbackStackTrace,
        );
        throw ValidationException(
          'Nao foi possivel restaurar o backup e a recuperacao automatica da base anterior falhou. Utilize o backup de seguranca ${safetyBackup.fileName}.',
          cause: error,
        );
      }

      throw ValidationException(
        'Nao foi possivel concluir a restauracao. A base anterior foi preservada pelo backup de seguranca ${safetyBackup.fileName}.',
        cause: error,
      );
    }
  }

  Future<void> _deleteSidecars(String databasePath) async {
    for (final sidecarPath in _fileLocator.sidecarPathsFor(databasePath)) {
      final file = File(sidecarPath);
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  Future<void> _writeRestoreLog({
    required String status,
    required String destination,
    required String details,
  }) async {
    try {
      final database = await _appDatabase.database;
      await database.insert(TableNames.backupLogs, {
        'uuid': IdGenerator.next(),
        'tipo_backup': 'restore_manual',
        'destino': destination,
        'status': status,
        'detalhes': details,
        'criado_em': DateTime.now().toIso8601String(),
      });
    } catch (error) {
      AppLogger.warn('Restore log could not be persisted: $error');
    }
  }
}
