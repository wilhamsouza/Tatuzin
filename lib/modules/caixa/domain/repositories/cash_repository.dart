import '../entities/cash_manual_movement_input.dart';
import '../entities/cash_movement.dart';
import '../entities/cash_session_detail.dart';
import '../entities/cash_session.dart';

abstract interface class CashRepository {
  Future<CashSession?> getCurrentSession();

  Future<List<CashMovement>> listCurrentSessionMovements();

  Future<List<CashSession>> listSessions();

  Future<CashSessionDetail> fetchSessionDetail(int sessionId);

  Future<CashSession> openSession({
    required int initialFloatCents,
    String? notes,
  });

  Future<CashSession> confirmAutoOpenedSession({
    required int initialFloatCents,
  });

  Future<CashSession> closeSession({
    required int countedBalanceCents,
    String? notes,
  });

  Future<void> registerManualMovement(CashManualMovementInput input);
}
