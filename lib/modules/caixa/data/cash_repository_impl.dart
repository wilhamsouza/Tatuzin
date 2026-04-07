import '../../../app/core/app_context/app_operational_context.dart';
import '../../../app/core/app_context/data_access_policy.dart';
import '../domain/entities/cash_manual_movement_input.dart';
import '../domain/entities/cash_movement.dart';
import '../domain/entities/cash_session.dart';
import '../domain/entities/cash_session_detail.dart';
import '../domain/repositories/cash_repository.dart';
import 'datasources/cash_remote_datasource.dart';

class CashRepositoryImpl implements CashRepository {
  const CashRepositoryImpl({
    required CashRepository localRepository,
    required CashRemoteDatasource remoteDatasource,
    required AppOperationalContext operationalContext,
    required DataAccessPolicy dataAccessPolicy,
  }) : _localRepository = localRepository,
       _remoteDatasource = remoteDatasource,
       _operationalContext = operationalContext,
       _dataAccessPolicy = dataAccessPolicy;

  final CashRepository _localRepository;
  final CashRemoteDatasource _remoteDatasource;
  final AppOperationalContext _operationalContext;
  final DataAccessPolicy _dataAccessPolicy;

  @override
  Future<CashSession> closeSession({String? notes}) async {
    return _executeWrite(() => _localRepository.closeSession(notes: notes));
  }

  @override
  Future<CashSession?> getCurrentSession() async {
    return _executeRead(_localRepository.getCurrentSession);
  }

  @override
  Future<List<CashMovement>> listCurrentSessionMovements() async {
    return _executeRead(_localRepository.listCurrentSessionMovements);
  }

  @override
  Future<List<CashSession>> listSessions() async {
    return _executeRead(_localRepository.listSessions);
  }

  @override
  Future<CashSessionDetail> fetchSessionDetail(int sessionId) async {
    return _executeRead(() => _localRepository.fetchSessionDetail(sessionId));
  }

  @override
  Future<CashSession> openSession({
    required int initialFloatCents,
    String? notes,
  }) async {
    return _executeWrite(
      () => _localRepository.openSession(
        initialFloatCents: initialFloatCents,
        notes: notes,
      ),
    );
  }

  @override
  Future<void> registerManualMovement(CashManualMovementInput input) async {
    await _executeWrite(() => _localRepository.registerManualMovement(input));
  }

  Future<T> _executeRead<T>(Future<T> Function() localAction) async {
    if (_dataAccessPolicy.allowRemoteRead &&
        _operationalContext.canUseCloudReads) {
      await _remoteDatasource.canReachRemote();
    }
    return localAction();
  }

  Future<T> _executeWrite<T>(Future<T> Function() localAction) async {
    if (_dataAccessPolicy.allowRemoteWrite &&
        _operationalContext.canUseCloudWrites) {
      await _remoteDatasource.canReachRemote();
    }
    return localAction();
  }
}
