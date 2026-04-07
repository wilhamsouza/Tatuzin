import '../../../../app/core/errors/app_exceptions.dart';
import '../entities/cash_session.dart';
import '../repositories/cash_repository.dart';

class OpenCashSessionUseCase {
  const OpenCashSessionUseCase(this._cashRepository);

  final CashRepository _cashRepository;

  Future<CashSession> call({
    required int initialFloatCents,
    String? notes,
  }) async {
    if (initialFloatCents < 0) {
      throw const ValidationException('O troco inicial nao pode ser negativo.');
    }

    return _cashRepository.openSession(
      initialFloatCents: initialFloatCents,
      notes: notes,
    );
  }
}
