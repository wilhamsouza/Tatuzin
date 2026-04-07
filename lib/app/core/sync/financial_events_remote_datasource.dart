import '../network/contracts/remote_datasource_contract.dart';
import '../network/remote_feature_diagnostic.dart';
import 'remote_financial_event_record.dart';

abstract interface class FinancialEventsRemoteDatasource
    implements RemoteDatasourceContract {
  Future<List<RemoteFinancialEventRecord>> listAll();

  Future<RemoteFinancialEventRecord> create(RemoteFinancialEventRecord record);

  Future<RemoteFeatureDiagnostic> fetchDiagnostic();
}
