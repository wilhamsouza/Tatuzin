import '../../../../app/core/network/contracts/remote_datasource_contract.dart';
import '../../../../app/core/network/remote_feature_diagnostic.dart';
import '../models/remote_purchase_record.dart';

abstract interface class PurchasesRemoteDatasource
    implements RemoteDatasourceContract {
  Future<List<RemotePurchaseRecord>> listAll();

  Future<RemotePurchaseRecord> fetchById(String remoteId);

  Future<RemotePurchaseRecord> create(RemotePurchaseRecord record);

  Future<RemotePurchaseRecord> update(
    String remoteId,
    RemotePurchaseRecord record,
  );

  Future<RemoteFeatureDiagnostic> fetchDiagnostic();
}
