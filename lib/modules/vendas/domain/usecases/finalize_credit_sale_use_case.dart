import '../../../../app/core/errors/app_exceptions.dart';
import '../entities/checkout_input.dart';
import '../entities/completed_sale.dart';
import '../entities/sale_enums.dart';
import '../repositories/sale_repository.dart';

class FinalizeCreditSaleUseCase {
  const FinalizeCreditSaleUseCase(this._saleRepository);

  final SaleRepository _saleRepository;

  Future<CompletedSale> call(CheckoutInput input) async {
    if (input.items.isEmpty) {
      throw const ValidationException('O carrinho esta vazio.');
    }

    if (input.saleType != SaleType.fiado) {
      throw const ValidationException('Use o fluxo a vista para esta venda.');
    }

    if (input.clientId == null) {
      throw const ValidationException(
        'Selecione um cliente para finalizar no fiado.',
      );
    }

    if (input.dueDate == null) {
      throw const ValidationException('Informe o vencimento da nota a prazo.');
    }

    if (input.paymentMethod != PaymentMethod.fiado) {
      throw const ValidationException(
        'Venda fiado deve ser persistida com forma de pagamento fiado.',
      );
    }

    return _saleRepository.completeCreditSale(input: input);
  }
}
