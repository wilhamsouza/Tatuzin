import 'package:share_plus/share_plus.dart';

import '../../../app/core/errors/app_exceptions.dart';
import '../domain/entities/backup_file_info.dart';

class BackupShareService {
  Future<void> share(BackupFileInfo backupFile) async {
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
