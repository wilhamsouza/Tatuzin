import '../../../../app/core/network/contracts/remote_datasource_contract.dart';
import '../../../../app/core/network/remote_feature_diagnostic.dart';
import '../models/remote_sale_record.dart';

abstract interface class SalesRemoteDatasource
    implements RemoteDatasourceContract {
  Future<List<RemoteSaleRecord>> listAll();

  Future<RemoteSaleRecord> fetchById(String remoteId);

  Future<RemoteSaleRecord> create(RemoteSaleRecord record);

  Future<RemoteSaleRecord> cancel({
    required String remoteSaleId,
    required String localUuid,
    required DateTime canceledAt,
  });

  Future<RemoteFeatureDiagnostic> fetchDiagnostic();
}
