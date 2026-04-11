import 'dart:io';

import 'package:sqflite/sqflite.dart';

import '../../../app/core/constants/app_constants.dart';
import '../../../app/core/database/table_names.dart';
import '../../../app/core/errors/app_exceptions.dart';
import '../domain/entities/backup_validation_result.dart';

class BackupValidationService {
  static const Set<String> _requiredTables = {
    TableNames.categorias,
    TableNames.produtos,
    TableNames.clientes,
    TableNames.customerCreditTransactions,
    TableNames.vendas,
    TableNames.itensVenda,
    TableNames.fiado,
    TableNames.fiadoLancamentos,
    TableNames.caixaSessoes,
    TableNames.caixaMovimentos,
    TableNames.configuracoes,
    TableNames.backupLogs,
  };

  Future<BackupValidationResult> validate(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw const ValidationException(
        'O arquivo selecionado nao foi encontrado.',
      );
    }

    final stat = await file.stat();
    if (stat.size == 0) {
      throw const ValidationException('O arquivo selecionado esta vazio.');
    }

    final header = await _readHeader(file);
    if (!header.startsWith('SQLite format 3')) {
      throw const ValidationException(
        'O arquivo selecionado nao e um backup SQLite valido do sistema.',
      );
    }

    Database? database;
    try {
      database = await openDatabase(
        file.path,
        readOnly: true,
        singleInstance: false,
      );

      final versionRows = await database.rawQuery('PRAGMA user_version');
      final schemaVersion = versionRows.isEmpty
          ? 0
          : (versionRows.first.values.first as int? ?? 0);
      if (schemaVersion <= 0 || schemaVersion > AppConstants.databaseVersion) {
        throw const ValidationException(
          'O backup selecionado nao e compativel com esta versao do aplicativo.',
        );
      }

      final tableRows = await database.rawQuery('''
        SELECT name
        FROM sqlite_master
        WHERE type = 'table'
      ''');
      final detectedTables = tableRows
          .map((row) => row['name']?.toString())
          .whereType<String>()
          .toSet();

      final missingTables = _requiredTables.difference(detectedTables);
      if (missingTables.isNotEmpty) {
        throw const ValidationException(
          'O arquivo selecionado nao pertence a um backup valido do sistema.',
        );
      }

      final sortedTables = detectedTables.toList()..sort();
      return BackupValidationResult(
        filePath: file.path,
        fileName: file.uri.pathSegments.isEmpty
            ? file.path
            : file.uri.pathSegments.last,
        sizeBytes: stat.size,
        schemaVersion: schemaVersion,
        detectedTables: sortedTables,
      );
    } catch (error) {
      if (error is ValidationException) {
        rethrow;
      }
      throw ValidationException(
        'Nao foi possivel validar o arquivo selecionado como backup do sistema.',
        cause: error,
      );
    } finally {
      await database?.close();
    }
  }

  Future<String> _readHeader(File file) async {
    final bytes = await file.openRead(0, 16).expand((chunk) => chunk).toList();
    return String.fromCharCodes(bytes);
  }
}
