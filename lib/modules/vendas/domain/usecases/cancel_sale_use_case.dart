import '../../../../app/core/errors/app_exceptions.dart';
import '../repositories/sale_repository.dart';

class CancelSaleUseCase {
  const CancelSaleUseCase(this._saleRepository);

  final SaleRepository _saleRepository;

  Future<void> call({required int saleId, required String reason}) async {
    if (reason.trim().isEmpty) {
      throw const ValidationException(
        'Informe o motivo do cancelamento antes de continuar.',
      );
    }

    await _saleRepository.cancelSale(saleId: saleId, reason: reason.trim());
  }
}
