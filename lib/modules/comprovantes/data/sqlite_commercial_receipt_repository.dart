import '../../../app/core/errors/app_exceptions.dart';
import '../../clientes/domain/entities/client.dart';
import '../../clientes/domain/repositories/client_repository.dart';
import '../../clientes/domain/repositories/customer_credit_repository.dart';
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
    required ClientRepository clientRepository,
    required CustomerCreditRepository customerCreditRepository,
  }) : _saleHistoryRepository = saleHistoryRepository,
       _fiadoRepository = fiadoRepository,
       _clientRepository = clientRepository,
       _customerCreditRepository = customerCreditRepository;

  final SaleHistoryRepository _saleHistoryRepository;
  final FiadoRepository _fiadoRepository;
  final ClientRepository _clientRepository;
  final CustomerCreditRepository _customerCreditRepository;

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
      case CommercialReceiptRequestType.customerCredit:
        final transactionId = request.transactionId;
        if (transactionId == null) {
          throw const ValidationException(
            'Lancamento de haver nao foi identificado corretamente.',
          );
        }
        final transaction = await _customerCreditRepository.getTransactionById(
          transactionId,
        );
        final clients = await _clientRepository.search();
        final Client? client =
            clients.where((item) => item.id == transaction.customerId).isEmpty
            ? null
            : clients.firstWhere((item) => item.id == transaction.customerId);
        return CommercialReceiptMapper.fromCustomerCredit(
          transaction: transaction,
          client: client,
        );
    }
  }
}
