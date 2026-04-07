import '../../../../app/core/network/contracts/remote_datasource_contract.dart';
import '../../../../app/core/network/remote_feature_diagnostic.dart';
import '../models/remote_supplier_record.dart';

abstract interface class SuppliersRemoteDatasource
    implements RemoteDatasourceContract {
  Future<List<RemoteSupplierRecord>> listAll();

  Future<RemoteSupplierRecord> fetchById(String remoteId);

  Future<RemoteSupplierRecord> create(RemoteSupplierRecord record);

  Future<RemoteSupplierRecord> update(
    String remoteId,
    RemoteSupplierRecord record,
  );

  Future<void> delete(String remoteId);

  Future<RemoteFeatureDiagnostic> fetchDiagnostic();
}
