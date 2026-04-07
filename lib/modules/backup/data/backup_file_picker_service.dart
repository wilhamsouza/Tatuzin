import 'package:file_picker/file_picker.dart';

import '../../../app/core/errors/app_exceptions.dart';

class BackupFilePickerService {
  Future<String?> pickBackupFilePath() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      dialogTitle: 'Selecionar backup do sistema',
      type: FileType.custom,
      allowedExtensions: const ['db', 'sqlite', 'backup', 'bak'],
    );

    if (result == null) {
      return null;
    }

    final selectedPath = result.files.single.path;
    if (selectedPath == null || selectedPath.isEmpty) {
      throw const ValidationException(
        'Nao foi possivel acessar o arquivo selecionado.',
      );
    }

    return selectedPath;
  }
}
