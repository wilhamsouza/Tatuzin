import '../../../app/core/errors/app_exceptions.dart';
import '../../fiado/domain/repositories/fiado_repository.dart';
import '../../historico_vendas/domain/repositories/sale_history_repository.dart';
import '../domain/entities/commercial_receipt.dart';
import '../domain/entities/commercial_receipt_request.dart';
import '../domain/repositories/commercial_receipt_repository.dart';
import 'commercial_receipt_mapper.dart';

class SqliteCommercialReceiptRepository implements CommercialReceiptRepository {
  SqliteCommercialReceiptRepository({
    required SaleHistoryRepository saleHistoryRepository,
    required FiadoRepository fiadoRepository,
  }) : _saleHistoryRepository = saleHistoryRepository,
       _fiadoRepository = fiadoRepository;

  final SaleHistoryRepository _saleHistoryRepository;
  final FiadoRepository _fiadoRepository;

  @override
  Future<CommercialReceipt> build(CommercialReceiptRequest request) async {
    switch (request.type) {
      case CommercialReceiptRequestType.sale:
        final saleId = request.saleId;
        if (saleId == null) {
          throw const ValidationException('Venda nao informada.');
        }
        final detail = await _saleHistoryRepository.fetchDetail(saleId);
        return CommercialReceiptMapper.fromSaleDetail(detail);
      case CommercialReceiptRequestType.fiadoPayment:
        final fiadoId = request.fiadoId;
        final paymentEntryId = request.paymentEntryId;
        if (fiadoId == null || paymentEntryId == null) {
          throw const ValidationException(
            'Pagamento de fiado nao foi identificado corretamente.',
          );
        }
        final detail = await _fiadoRepository.fetchDetail(fiadoId);
        final entry = detail.entries.firstWhere(
          (candidate) =>
              candidate.id == paymentEntryId &&
              candidate.entryType == 'pagamento',
          orElse: () => throw const ValidationException(
            'Nao foi possivel localizar o pagamento selecionado.',
          ),
        );
        return CommercialReceiptMapper.fromFiadoPayment(
          detail: detail,
          entry: entry,
        );
    }
  }
}
