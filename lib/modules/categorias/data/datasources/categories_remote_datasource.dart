import '../../../../app/core/network/contracts/remote_datasource_contract.dart';
import '../../../../app/core/network/remote_feature_diagnostic.dart';
import '../models/remote_category_record.dart';

abstract interface class CategoriesRemoteDatasource
    implements RemoteDatasourceContract {
  Future<List<RemoteCategoryRecord>> listAll();

  Future<RemoteCategoryRecord> fetchById(String remoteId);

  Future<RemoteCategoryRecord> create(RemoteCategoryRecord record);

  Future<RemoteCategoryRecord> update(
    String remoteId,
    RemoteCategoryRecord record,
  );

  Future<void> delete(String remoteId);

  Future<RemoteFeatureDiagnostic> fetchDiagnostic();
}
