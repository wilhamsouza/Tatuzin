import '../../../../app/core/errors/app_exceptions.dart';
import '../../../vendas/domain/entities/sale_enums.dart';
import '../entities/fiado_detail.dart';
import '../entities/fiado_payment_input.dart';
import '../repositories/fiado_repository.dart';

class RegisterFiadoPaymentUseCase {
  const RegisterFiadoPaymentUseCase(this._fiadoRepository);

  final FiadoRepository _fiadoRepository;

  Future<FiadoDetail> call(FiadoPaymentInput input) async {
    if (input.amountCents <= 0) {
      throw const ValidationException('Informe um valor de pagamento valido.');
    }

    if (input.paymentMethod == PaymentMethod.fiado) {
      throw const ValidationException(
        'O pagamento da divida nao pode usar a forma fiado.',
      );
    }

    if (input.amountCents <= 0) {
      throw const ValidationException('Informe um valor de pagamento valido.');
    }

    return _fiadoRepository.registerPayment(input);
  }
}
