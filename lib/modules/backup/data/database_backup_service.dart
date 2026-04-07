import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../../../app/core/database/app_database.dart';
import '../../../app/core/database/database_file_locator.dart';
import '../../../app/core/database/table_names.dart';
import '../../../app/core/errors/app_exceptions.dart';
import '../../../app/core/utils/app_logger.dart';
import '../../../app/core/utils/id_generator.dart';
import '../domain/entities/backup_file_info.dart';
import 'backup_validation_service.dart';

class DatabaseBackupService {
  DatabaseBackupService({
    required AppDatabase appDatabase,
    required DatabaseFileLocator fileLocator,
    required BackupValidationService validationService,
  }) : _appDatabase = appDatabase,
       _fileLocator = fileLocator,
       _validationService = validationService;

  final AppDatabase _appDatabase;
  final DatabaseFileLocator _fileLocator;
  final BackupValidationService _validationService;

  Future<BackupFileInfo> createBackup({bool safetyCopy = false}) async {
    final database = await _appDatabase.database;
    final timestamp = DateTime.now();
    final backupDirectory = await _fileLocator.ensureBackupDirectory();
    final fileName = _fileLocator.buildBackupFileName(
      timestamp: timestamp,
      safetyCopy: safetyCopy,
    );
    final targetPath = path.join(backupDirectory.path, fileName);

    if (await File(targetPath).exists()) {
      throw const ValidationException(
        'Ja existe um arquivo de backup com este nome. Tente novamente em alguns segundos.',
      );
    }

    try {
      final escapedTargetPath = targetPath.replaceAll("'", "''");
      AppLogger.info('Creating backup at $targetPath');
      await database.execute("VACUUM INTO '$escapedTargetPath'");

      await _validationService.validate(targetPath);
      final stat = await File(targetPath).stat();
      final info = BackupFileInfo(
        filePath: targetPath,
        fileName: fileName,
        sizeBytes: stat.size,
        createdAt: timestamp,
        isSafetyCopy: safetyCopy,
      );

      await _writeBackupLog(
        database,
        type: safetyCopy ? 'pre_restore' : 'manual',
        destination: targetPath,
        status: 'sucesso',
        details: safetyCopy
            ? 'Backup de seguranca criado antes da restauracao.'
            : 'Backup manual gerado com sucesso.',
      );

      return info;
    } catch (error) {
      await _safeLogFailure(
        database,
        type: safetyCopy ? 'pre_restore' : 'manual',
        destination: targetPath,
        details: error.toString(),
      );
      throw ValidationException(
        safetyCopy
            ? 'Nao foi possivel criar o backup de seguranca antes da restauracao.'
            : 'Nao foi possivel gerar o backup do sistema.',
        cause: error,
      );
    }
  }

  Future<void> _safeLogFailure(
    Database database, {
    required String type,
    required String destination,
    required String details,
  }) async {
    try {
      await _writeBackupLog(
        database,
        type: type,
        destination: destination,
        status: 'falha',
        details: details,
      );
    } catch (error) {
      AppLogger.warn('Backup log could not be persisted: $error');
    }
  }

  Future<void> _writeBackupLog(
    Database database, {
    required String type,
    required String destination,
    required String status,
    required String details,
  }) async {
    await database.insert(TableNames.backupLogs, {
      'uuid': IdGenerator.next(),
      'tipo_backup': type,
      'destino': destination,
      'status': status,
      'detalhes': details,
      'criado_em': DateTime.now().toIso8601String(),
    });
  }
}
