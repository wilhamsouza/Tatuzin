import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../../app/core/utils/id_generator.dart';

class ProductMediaStorage {
  Future<String> importPickedFile(XFile pickedFile) async {
    final sourceFile = File(pickedFile.path);
    if (!await sourceFile.exists()) {
      throw StateError('A imagem selecionada não está mais disponível.');
    }

    final targetDirectory = await _ensurePhotosDirectory();
    final extension = path.extension(pickedFile.path);
    final fileName =
        '${DateTime.now().microsecondsSinceEpoch}_${IdGenerator.next()}$extension';
    final targetPath = path.join(targetDirectory.path, fileName);
    final copied = await sourceFile.copy(targetPath);
    return copied.path;
  }

  Future<void> deleteManagedFile(String? filePath) async {
    final cleaned = filePath?.trim();
    if (cleaned == null || cleaned.isEmpty) {
      return;
    }

    final photosDirectory = await _ensurePhotosDirectory();
    final normalizedRoot = path.normalize(photosDirectory.path);
    final normalizedTarget = path.normalize(cleaned);
    if (!path.isWithin(normalizedRoot, normalizedTarget) &&
        normalizedRoot != normalizedTarget) {
      return;
    }

    final file = File(cleaned);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<Directory> _ensurePhotosDirectory() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final photosDirectory = Directory(
      path.join(documentsDirectory.path, 'product_photos'),
    );
    if (!await photosDirectory.exists()) {
      await photosDirectory.create(recursive: true);
    }
    return photosDirectory;
  }
}
