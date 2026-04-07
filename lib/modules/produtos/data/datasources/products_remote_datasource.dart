import '../../../../app/core/network/contracts/remote_datasource_contract.dart';
import '../../../../app/core/network/remote_feature_diagnostic.dart';
import '../models/remote_product_record.dart';

abstract interface class ProductsRemoteDatasource
    implements RemoteDatasourceContract {
  Future<List<RemoteProductRecord>> listAll();

  Future<RemoteProductRecord> fetchById(String remoteId);

  Future<RemoteProductRecord> create(RemoteProductRecord record);

  Future<RemoteProductRecord> update(
    String remoteId,
    RemoteProductRecord record,
  );

  Future<void> delete(String remoteId);

  Future<RemoteFeatureDiagnostic> fetchDiagnostic();
}
