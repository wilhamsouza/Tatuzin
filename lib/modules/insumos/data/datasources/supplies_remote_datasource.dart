import '../../../../app/core/network/contracts/remote_datasource_contract.dart';
import '../../../../app/core/network/remote_feature_diagnostic.dart';
import '../models/remote_supply_record.dart';

abstract interface class SuppliesRemoteDatasource
    implements RemoteDatasourceContract {
  Future<List<RemoteSupplyRecord>> listAll();

  Future<RemoteSupplyRecord> fetchById(String remoteId);

  Future<RemoteSupplyRecord> create(RemoteSupplyRecord record);

  Future<RemoteSupplyRecord> update(String remoteId, RemoteSupplyRecord record);

  Future<void> delete(String remoteId);

  Future<RemoteFeatureDiagnostic> fetchDiagnostic();
}
