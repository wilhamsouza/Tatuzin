import '../entities/cash_session.dart';
import '../repositories/cash_repository.dart';

class CloseCashSessionUseCase {
  const CloseCashSessionUseCase(this._cashRepository);

  final CashRepository _cashRepository;

  Future<CashSession> call({required int countedBalanceCents, String? notes}) {
    return _cashRepository.closeSession(
      countedBalanceCents: countedBalanceCents,
      notes: notes,
    );
  }
}
