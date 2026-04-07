import '../../../../app/core/network/contracts/remote_datasource_contract.dart';
import '../../../../app/core/network/remote_feature_diagnostic.dart';
import '../models/remote_cash_event_record.dart';

abstract interface class CashRemoteDatasource
    implements RemoteDatasourceContract {
  Future<RemoteCashEventRecord> createEvent(RemoteCashEventRecord record);

  Future<RemoteFeatureDiagnostic> fetchDiagnostic();
}
