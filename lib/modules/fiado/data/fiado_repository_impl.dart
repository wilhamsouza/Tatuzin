import 'dart:async';

import '../../../app/core/app_context/app_operational_context.dart';
import '../../../app/core/app_context/data_access_policy.dart';
import '../../../app/core/utils/app_logger.dart';
import '../domain/entities/fiado_account.dart';
import '../domain/entities/fiado_detail.dart';
import '../domain/entities/fiado_payment_input.dart';
import '../domain/repositories/fiado_repository.dart';
import 'datasources/fiado_remote_datasource.dart';

class FiadoRepositoryImpl implements FiadoRepository {
  const FiadoRepositoryImpl({
    required FiadoRepository localRepository,
    required FiadoRemoteDatasource remoteDatasource,
    required AppOperationalContext operationalContext,
    required DataAccessPolicy dataAccessPolicy,
  }) : _localRepository = localRepository,
       _remoteDatasource = remoteDatasource,
       _operationalContext = operationalContext,
       _dataAccessPolicy = dataAccessPolicy;

  final FiadoRepository _localRepository;
  final FiadoRemoteDatasource _remoteDatasource;
  final AppOperationalContext _operationalContext;
  final DataAccessPolicy _dataAccessPolicy;

  @override
  Future<FiadoDetail> fetchDetail(int fiadoId) async {
    return _executeRead(() => _localRepository.fetchDetail(fiadoId));
  }

  @override
  Future<FiadoDetail> registerPayment(FiadoPaymentInput input) async {
    return _executeWrite(() => _localRepository.registerPayment(input));
  }

  @override
  Future<List<FiadoAccount>> search({
    String query = '',
    String? status,
    bool overdueOnly = false,
  }) async {
    return _executeRead(
      () => _localRepository.search(
        query: query,
        status: status,
        overdueOnly: overdueOnly,
      ),
    );
  }

  Future<T> _executeRead<T>(Future<T> Function() localAction) async {
    AppLogger.info(
      'Fiado PDV read using local-first store; remote preflight is non-blocking.',
    );
    final result = await localAction();
    _scheduleRemoteProbe(operation: 'read');
    return result;
  }

  Future<T> _executeWrite<T>(Future<T> Function() localAction) async {
    AppLogger.info(
      'Fiado PDV write committed locally first; sync remains queued in background.',
    );
    final result = await localAction();
    _scheduleRemoteProbe(operation: 'write');
    return result;
  }

  void _scheduleRemoteProbe({required String operation}) {
    final canProbe = switch (operation) {
      'read' =>
        _dataAccessPolicy.allowRemoteRead &&
            _operationalContext.canUseCloudReads,
      'write' =>
        _dataAccessPolicy.allowRemoteWrite &&
            _operationalContext.canUseCloudWrites,
      _ => false,
    };
    if (!canProbe) {
      return;
    }

    AppLogger.info(
      'Fiado PDV remote reachability probe scheduled in background | operation=$operation',
    );
    unawaited(() async {
      try {
        await _remoteDatasource.canReachRemote();
        AppLogger.info(
          'Fiado PDV remote reachability probe finished | operation=$operation',
        );
      } catch (error, stackTrace) {
        AppLogger.error(
          'Fiado PDV remote reachability probe failed without blocking local operation.',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }());
  }
}
