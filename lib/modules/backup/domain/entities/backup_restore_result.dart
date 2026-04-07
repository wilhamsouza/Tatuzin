import 'backup_file_info.dart';
import 'backup_validation_result.dart';

class BackupRestoreResult {
  const BackupRestoreResult({
    required this.restoredBackup,
    required this.safetyBackup,
    required this.restoredAt,
  });

  final BackupValidationResult restoredBackup;
  final BackupFileInfo safetyBackup;
  final DateTime restoredAt;
}
