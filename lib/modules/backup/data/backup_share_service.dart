import 'package:share_plus/share_plus.dart';

import '../../../app/core/errors/app_exceptions.dart';
import '../domain/entities/backup_file_info.dart';
import 'backup_security_policy.dart';

class BackupShareService {
  const BackupShareService({required BackupSecurityPolicy securityPolicy})
    : _securityPolicy = securityPolicy;

  final BackupSecurityPolicy _securityPolicy;

  Future<void> share(BackupFileInfo backupFile) async {
    if (!_securityPolicy.canShareRawDatabase) {
      throw const ValidationException(
        BackupSecurityPolicy.rawDatabaseBlockedReason,
      );
    }

    try {
      await Share.shareXFiles(
        [XFile(backupFile.filePath)],
        subject: 'Backup do Tatuzin',
        text: 'Backup manual gerado em ${backupFile.fileName}',
      );
    } catch (error) {
      throw ValidationException(
        'Nao foi possivel compartilhar o arquivo de backup.',
        cause: error,
      );
    }
  }
}
