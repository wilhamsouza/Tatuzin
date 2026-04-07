import '../../../../app/core/network/contracts/remote_datasource_contract.dart';
import '../../../../app/core/network/remote_feature_diagnostic.dart';
import '../models/remote_fiado_payment_record.dart';

abstract interface class FiadoRemoteDatasource
    implements RemoteDatasourceContract {
  Future<RemoteFiadoPaymentRecord> createPayment(
    RemoteFiadoPaymentRecord record,
  );

  Future<RemoteFeatureDiagnostic> fetchDiagnostic();
}
