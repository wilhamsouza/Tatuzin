import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../constants/app_constants.dart';

class DatabaseFileLocator {
  Future<String> resolveDatabasePath() async {
    final databasesPath = await getDatabasesPath();
    return path.join(databasesPath, AppConstants.databaseName);
  }

  Future<Directory> ensureBackupDirectory() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final backupDirectory = Directory(
      path.join(documentsDirectory.path, 'backups'),
    );
    if (!await backupDirectory.exists()) {
      await backupDirectory.create(recursive: true);
    }
    return backupDirectory;
  }

  String buildBackupFileName({
    required DateTime timestamp,
    bool safetyCopy = false,
  }) {
    final date = [
      timestamp.year.toString().padLeft(4, '0'),
      timestamp.month.toString().padLeft(2, '0'),
      timestamp.day.toString().padLeft(2, '0'),
    ].join('-');
    final time = [
      timestamp.hour.toString().padLeft(2, '0'),
      timestamp.minute.toString().padLeft(2, '0'),
      timestamp.second.toString().padLeft(2, '0'),
    ].join('-');
    final prefix = safetyCopy
        ? 'simples_erp_pdv_pre_restore_backup'
        : 'simples_erp_pdv_backup';
    return '${prefix}_${date}_$time.db';
  }

  List<String> sidecarPathsFor(String databasePath) {
    return ['$databasePath-wal', '$databasePath-shm', '$databasePath-journal'];
  }
}
