import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../../app/core/utils/id_generator.dart';

class ProductMediaStorage {
  static const _thumbnailMaxDimension = 640;
  static const _thumbnailJpegQuality = 72;

  Future<String> importPickedFile(XFile pickedFile) async {
    final sourceFile = File(pickedFile.path);
    if (!await sourceFile.exists()) {
      throw StateError('A imagem selecionada nao esta mais disponivel.');
    }

    final sourceBytes = await sourceFile.readAsBytes();
    final thumbnailBytes = _buildThumbnailBytes(sourceBytes);
    if (thumbnailBytes == null) {
      throw StateError(
        'Nao foi possivel gerar uma miniatura local da imagem selecionada.',
      );
    }

    final targetDirectory = await _ensurePhotosDirectory();
    final fileName =
        '${DateTime.now().microsecondsSinceEpoch}_${IdGenerator.next()}.jpg';
    final targetPath = path.join(targetDirectory.path, fileName);
    final storedFile = File(targetPath);
    await storedFile.writeAsBytes(thumbnailBytes, flush: true);
    return storedFile.path;
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

  Uint8List? _buildThumbnailBytes(Uint8List sourceBytes) {
    final decoded = img.decodeImage(sourceBytes);
    if (decoded == null) {
      return null;
    }

    final resized = _resizeToFit(decoded);
    final encoded = img.encodeJpg(resized, quality: _thumbnailJpegQuality);
    return Uint8List.fromList(encoded);
  }

  img.Image _resizeToFit(img.Image source) {
    final longestSide = source.width > source.height
        ? source.width
        : source.height;
    if (longestSide <= _thumbnailMaxDimension) {
      return source;
    }

    if (source.width >= source.height) {
      return img.copyResize(
        source,
        width: _thumbnailMaxDimension,
        interpolation: img.Interpolation.average,
      );
    }

    return img.copyResize(
      source,
      height: _thumbnailMaxDimension,
      interpolation: img.Interpolation.average,
    );
  }
}
