import '../entities/cash_session.dart';
import '../repositories/cash_repository.dart';

class CloseCashSessionUseCase {
  const CloseCashSessionUseCase(this._cashRepository);

  final CashRepository _cashRepository;

  Future<CashSession> call({String? notes}) {
    return _cashRepository.closeSession(notes: notes);
  }
}
