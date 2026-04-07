import '../../../../app/core/network/contracts/remote_datasource_contract.dart';
import '../../../../app/core/network/remote_feature_diagnostic.dart';
import '../models/remote_customer_record.dart';

abstract interface class CustomersRemoteDatasource
    implements RemoteDatasourceContract {
  Future<List<RemoteCustomerRecord>> listAll();

  Future<RemoteCustomerRecord> fetchById(String remoteId);

  Future<RemoteCustomerRecord> create(RemoteCustomerRecord record);

  Future<RemoteCustomerRecord> update(
    String remoteId,
    RemoteCustomerRecord record,
  );

  Future<void> delete(String remoteId);

  Future<RemoteFeatureDiagnostic> fetchDiagnostic();
}
