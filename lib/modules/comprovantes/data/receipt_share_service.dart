import 'dart:io';

import 'package:share_plus/share_plus.dart';

import '../../../app/core/errors/app_exceptions.dart';
import '../domain/entities/commercial_receipt.dart';

class ReceiptShareService {
  Future<void> share({
    required File file,
    required CommercialReceipt receipt,
  }) async {
    try {
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: receipt.title,
        text:
            '${receipt.title} ${receipt.identifier} - ${receipt.businessName}',
      );
    } catch (error) {
      throw ValidationException(
        'Nao foi possivel compartilhar o comprovante.',
        cause: error,
      );
    }
  }
}
