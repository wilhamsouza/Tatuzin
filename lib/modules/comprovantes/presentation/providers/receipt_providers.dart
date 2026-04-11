import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/providers/app_data_refresh_provider.dart';
import '../../../fiado/presentation/providers/fiado_providers.dart';
import '../../../clientes/presentation/providers/client_providers.dart';
import '../../../historico_vendas/presentation/providers/sale_history_providers.dart';
import '../../data/receipt_pdf_service.dart';
import '../../data/receipt_share_service.dart';
import '../../data/sqlite_commercial_receipt_repository.dart';
import '../../domain/entities/commercial_receipt.dart';
import '../../domain/entities/commercial_receipt_request.dart';
import '../../domain/repositories/commercial_receipt_repository.dart';

final commercialReceiptRepositoryProvider =
    Provider<CommercialReceiptRepository>((ref) {
      return SqliteCommercialReceiptRepository(
        saleHistoryRepository: ref.read(saleHistoryRepositoryProvider),
        fiadoRepository: ref.read(fiadoRepositoryProvider),
        clientRepository: ref.read(clientRepositoryProvider),
        customerCreditRepository: ref.read(customerCreditRepositoryProvider),
      );
    });

final commercialReceiptProvider =
    FutureProvider.family<CommercialReceipt, CommercialReceiptRequest>((
      ref,
      request,
    ) async {
      ref.watch(appDataRefreshProvider);
      return ref.watch(commercialReceiptRepositoryProvider).build(request);
    });

final receiptPdfServiceProvider = Provider<ReceiptPdfService>((ref) {
  return ReceiptPdfService();
});

final receiptShareServiceProvider = Provider<ReceiptShareService>((ref) {
  return ReceiptShareService();
});

final receiptActionControllerProvider =
    AsyncNotifierProvider<ReceiptActionController, void>(
      ReceiptActionController.new,
    );

class ReceiptActionController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<String> savePdf(CommercialReceiptRequest request) async {
    state = const AsyncLoading();
    try {
      final receipt = await ref.read(commercialReceiptProvider(request).future);
      final file = await ref
          .read(receiptPdfServiceProvider)
          .saveToDocuments(receipt);
      state = const AsyncData(null);
      return file.path;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<void> sharePdf(CommercialReceiptRequest request) async {
    state = const AsyncLoading();
    try {
      final receipt = await ref.read(commercialReceiptProvider(request).future);
      final file = await ref
          .read(receiptPdfServiceProvider)
          .saveToTemporary(receipt);
      await ref
          .read(receiptShareServiceProvider)
          .share(file: file, receipt: receipt);
      state = const AsyncData(null);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }
}
