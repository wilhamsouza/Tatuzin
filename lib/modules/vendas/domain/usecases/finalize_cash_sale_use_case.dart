import '../../../../app/core/errors/app_exceptions.dart';
import '../entities/checkout_input.dart';
import '../entities/completed_sale.dart';
import '../entities/sale_enums.dart';
import '../repositories/sale_repository.dart';

class FinalizeCashSaleUseCase {
  const FinalizeCashSaleUseCase(this._saleRepository);

  final SaleRepository _saleRepository;

  Future<CompletedSale> call(CheckoutInput input) async {
    if (input.items.isEmpty) {
      throw const ValidationException('O carrinho esta vazio.');
    }

    if (input.saleType != SaleType.cash) {
      throw const ValidationException('Use o fluxo de fiado para esta venda.');
    }

    if (!input.paymentMethod.isImmediateReceipt) {
      throw const ValidationException(
        'A venda a vista exige uma forma de pagamento recebida na hora.',
      );
    }

    return _saleRepository.completeCashSale(input: input);
  }
}
